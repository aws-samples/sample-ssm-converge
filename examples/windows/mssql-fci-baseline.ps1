# =============================================================================
# SSM Converge Configuration: MSSQL Failover Cluster Instance - Node Baseline
#
# Brings a Windows Server 2022 box to a "ready to join a SQL FCI" state.
#
# Demonstrates the pattern for porting existing DSC-based cluster work:
#   - Use SSM Converge PRIMITIVES for plain OS state (LocalUser, LocalGroup,
#     WindowsFeature, PowerShellModule, HostEntry, Certificate).
#   - Use the generic `DscResource` wrapper for any existing DSC resource
#     you already rely on (ComputerManagementDsc, FailoverClusterDsc,
#     ActiveDirectoryDsc, CertificateDsc, PSDscResources, etc.)
#
# That way you keep your existing DSC resource knowledge, but pick up SSM
# Converge's modes (enforce/audit/destroy/comply), idempotent reporting,
# and SSM-native fleet-wide execution.
#
# Run:
#   $env:DSC_MODE    = "audit"     # or enforce / destroy / comply
#   $env:DSC_PROFILE = "sqlfci-node"
#   . C:\ProgramData\ssm-converge\lib.ps1
#   . examples\windows\mssql-fci-baseline.ps1
# =============================================================================

. C:\ProgramData\ssm-converge\lib.ps1

# -- 1. Required Windows features -------------------------------------------
#    Uses the WindowsFeature PRIMITIVE (wraps Install-WindowsFeature under the hood).

WindowsFeature 'Failover-Clustering'    Installed -IncludeManagementTools
WindowsFeature 'RSAT-AD-PowerShell'     Installed
WindowsFeature 'RSAT-Clustering'        Installed

# -- 2. DSC module dependencies ---------------------------------------------
#    The PowerShellModule PRIMITIVE installs the modules your existing DSC
#    configurations depend on, before the DscResource wrapper invokes them.

PowerShellModule 'PSDscResources'        Installed
PowerShellModule 'ComputerManagementDsc' Installed
PowerShellModule 'FailoverClusterDsc'    Installed
PowerShellModule 'ActiveDirectoryDsc'    Installed
PowerShellModule 'CertificateDsc'        Installed

# -- 3. Host entries for cluster/DB peers -----------------------------------

HostEntry '10.0.1.11' Present -Hostname 'SQL01-A.corp.example.com'
HostEntry '10.0.1.12' Present -Hostname 'SQL01-B.corp.example.com'
HostEntry '10.0.1.20' Present -Hostname 'ad-primary.corp.example.com'

# -- 4. Local SQL installation group ----------------------------------------
#    SQL Server's installer expects a local group that SQL service accounts
#    can be added to. LocalUser + LocalGroup are PRIMITIVES.

LocalGroup 'SQLAdmins' Present -Description 'Local admins of this SQL node'

# -- 5. Local service user that SQL Agent can impersonate -------------------
#    For AD-based SQL FCI you'd normally use a gMSA instead; this shows the
#    local account pattern for a lab/PoC setup.
#    Password is read from a local secrets file (or SSM Parameter Store in
#    production - not hard-coded here).

$svcPassword = ConvertTo-SecureString 'PLACEHOLDER-ReplaceMe!' -AsPlainText -Force
LocalUser 'svc_sqlagent' Present `
    -FullName             'SQL Agent service' `
    -Description          'Local account used for scheduled jobs' `
    -Password             $svcPassword `
    -PasswordNeverExpires

# -- 6. Domain join --------------------------------------------------------
#    This is where we HAND OFF to the existing DSC resource via the generic
#    wrapper. ComputerManagementDsc.Computer knows about domain join +
#    rename semantics; we reuse that knowledge instead of re-implementing.
#
#    The credential in production would come from SSM Parameter Store:
#      $cred = Get-Credential -Message 'Domain join' -UserName 'corp\joiner'
#
#    Commented out here because running domain-join on an instance during a
#    demo will disconnect the SSM session if the instance isn't already in AD.

# DscResource -Name Computer -Module ComputerManagementDsc -Properties @{
#     Name       = 'SQL01-A'
#     DomainName = 'corp.example.com'
#     Credential = $joinCred
# }

# -- 7. DSC encryption certificate (replaces LCM-Config.ps1) ---------------
#    The Certificate PRIMITIVE imports the cert; downstream DSC resources
#    that need encrypted credentials pick it up from the store automatically.

# Certificate -Path      'C:\certs\dsc-encryption.pfx' `
#             -Store     'Cert:\LocalMachine\My' `
#             -Password  (ConvertTo-SecureString 'PLACEHOLDER' -AsPlainText -Force) `
#             -Exportable:$false `
#             -State     Present

# -- 8. AD service account (gMSA) -------------------------------------------
#    Reuses the ActiveDirectoryDsc resource you already depend on.
#    Runs ONLY if this node can reach AD (gated by -WhatIf in audit mode).

# DscResource -Name ADManagedServiceAccount -Module ActiveDirectoryDsc -Properties @{
#     ServiceAccountName = 'svc-sql01'
#     AccountType        = 'Group'
#     ManagedPasswordPrincipals = 'SQL01-A$','SQL01-B$'
#     Path               = 'OU=Service Accounts,OU=Corp,DC=corp,DC=example,DC=com'
#     Ensure             = 'Present'
# }

# -- 9. Cluster creation on first node --------------------------------------
#    Reuses FailoverClusterDsc - we don't re-implement clustering in bash/PowerShell.

# DscResource -Name Cluster -Module FailoverClusterDsc -Properties @{
#     Name                = 'SQLCluster01'
#     StaticIPAddress     = '10.0.1.100/24'
#     Ensure              = 'Present'
# }

# -- 10. SQL-specific sysctl/registry tuning --------------------------------
#    Disable NETBIOS over TCP/IP for the replication NIC (SQL FCI best
#    practice). Shows the RegistryKey PRIMITIVE.

RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_ReplicationNIC' Present `
    -ValueName 'NetbiosOptions' -ValueData 2 -ValueType DWord

# -- 11. Finish ------------------------------------------------------------

Report-Compliance

if (Test-RebootRequired) {
    Write-Host ""
    Write-Host "A reboot is required to complete convergence (likely from Failover-Clustering feature install or domain join)."
    Write-Host "Restart this instance via SSM (e.g. aws ssm send-command ... AWS-RestartEC2Instance) and re-run this configuration."
}
