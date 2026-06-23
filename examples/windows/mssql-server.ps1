# =============================================================================
# SSM Converge Configuration: Microsoft SQL Server (standalone)
#
# Brings a Windows Server to "SQL Server 2022 Developer edition installed and
# running" state. Standalone (not FCI); for FCI see mssql-fci-baseline.ps1.
#
# Primitives used:
#   - WindowsFeature        -> .NET / VC runtime prerequisites
#   - PowerShellModule      -> SqlServerDsc (the DSC resource module)
#   - Directory / File      -> data + log directory layout
#   - LocalUser / LocalGroup -> sysadmin group + service account
#   - WindowsService        -> SQL service state + startup
#   - DscResource           -> SqlServerDsc.SqlSetup for the actual install
#   - RegistryKey           -> post-install tuning
#
# PREREQUISITES STAGED OUTSIDE THIS CONFIG:
#   - SQL Server 2022 installer media at \\fileshare\SQL or in S3
#     (SourcePath parameter points to extracted media)
#   - sa password provided via SSM Parameter Store (not hard-coded here)
#
# Run:
#   $env:DSC_MODE    = "audit"
#   $env:DSC_PROFILE = "mssql-server"
#   . C:\ProgramData\ssm-converge\lib.ps1
#   . examples\windows\mssql-server.ps1
# =============================================================================

. C:\ProgramData\ssm-converge\lib.ps1

# -- Config knobs ------------------------------------------------------------
$InstanceName  = 'MSSQLSERVER'             # Default instance
$SqlFeatures   = 'SQLENGINE,FULLTEXT,AS'   # SQL Engine + full-text + Analysis Services
$SourcePath    = 'C:\sql-media'            # Where the extracted installer lives
$InstallDir    = 'C:\Program Files\Microsoft SQL Server'
$DataDir       = 'D:\SqlData'
$LogDir        = 'D:\SqlLogs'
$BackupDir     = 'D:\SqlBackups'
$ServiceAccount = 'NT Service\MSSQLSERVER' # Use the built-in service SID

# -- 1. Prerequisite OS features --------------------------------------------
WindowsFeature 'NET-Framework-45-Core' Installed

# -- 2. DSC module for SQL install ------------------------------------------
#    SqlServerDsc ships the SqlSetup / SqlLogin / SqlDatabase / SqlRole /
#    SqlRSSetup / ... resources. We delegate the install through DscResource.

PowerShellModule 'PSDscResources' Installed
PowerShellModule 'SqlServerDsc'   Installed

# -- 3. Data + log directories -----------------------------------------------

Directory $DataDir   Present
Directory $LogDir    Present
Directory $BackupDir Present

# -- 4. Local sysadmin group -------------------------------------------------
#    Users added to this group will later be granted sysadmin on the SQL
#    instance via the SqlLogin DSC resource (not shown here).

LocalGroup 'SqlAdmins' Present -Description 'Local group granted SQL sysadmin role'

# -- 5. SQL Server install via DscResource -----------------------------------
#    SqlServerDsc.SqlSetup runs setup.exe with the right parameters and tests
#    idempotently by checking the already-installed instance.
#
#    The SAPwd / SecurityMode / SAPwd etc. should come from SSM Parameter
#    Store in production. Here we show the shape - replace the credential.

#   $saPwd = (Get-SSMParameterValue -Names sql/sa-password -WithDecryption $true).Parameters[0].Value
#   $saCred = [pscredential]::new('sa', (ConvertTo-SecureString $saPwd -AsPlainText -Force))

DscResource -Name SqlSetup -Module SqlServerDsc -Properties @{
    InstanceName            = $InstanceName
    Features                = $SqlFeatures
    SourcePath              = $SourcePath
    InstallSharedDir        = $InstallDir
    SQLSvcAccountUsername   = $ServiceAccount
    AgtSvcAccountUsername   = $ServiceAccount
    InstallSQLDataDir       = $DataDir
    SQLUserDBDir            = $DataDir
    SQLUserDBLogDir         = $LogDir
    SQLBackupDir            = $BackupDir
    SecurityMode            = 'SQL'
#   SAPwd                   = $saCred           # uncomment in production
    SQLSysAdminAccounts     = @("$env:COMPUTERNAME\SqlAdmins", "BUILTIN\Administrators")
    UpdateEnabled           = 'True'
}

# -- 6. Service state --------------------------------------------------------
#    SqlSetup starts the service, but we assert the desired end state so any
#    drift (someone stops the service manually) gets reported + fixed.

WindowsService 'MSSQLSERVER'  Running -StartupType Automatic
WindowsService 'SQLSERVERAGENT' Running -StartupType Automatic

# -- 7. Post-install tuning via registry -------------------------------------
#    Disable SQL Server telemetry ("CEIP") across all installed instances.

RegistryKey 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\160\ConfigurationState' Present `
    -ValueName 'SQM_REPORTING' -ValueData 0 -ValueType DWord

# -- 8. Firewall via registry hint (informational) ---------------------------
#    The actual firewall rule is typically pushed via Group Policy in prod.
#    We document the desired state here via a host_entry marker for the SQL
#    endpoint so monitoring knows this box is a SQL server.

HostEntry '127.0.0.1' Present -Hostname "sql.$env:COMPUTERNAME.local"

# -- 9. Report ---------------------------------------------------------------

Report-Compliance

if (Test-RebootRequired) {
    Write-Host ""
    Write-Host "Reboot required after SQL Server install. Reboot then run again."
}
