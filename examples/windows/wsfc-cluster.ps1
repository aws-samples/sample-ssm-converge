# =============================================================================
# SSM Converge Configuration: Windows Server Failover Cluster (WSFC) node
#
# Brings a Windows Server 2022+ box to "cluster-ready" state and (optionally)
# creates or joins a cluster.
#
# Primitives used:
#   - WindowsFeature        -> Failover-Clustering role + tools
#   - PowerShellModule      -> FailoverClusterDsc (the DSC resource module)
#   - HostEntry             -> cluster nodes in hosts
#   - LocalGroup            -> cluster admin group
#   - DscResource           -> generic wrapper to invoke FailoverClusterDsc.Cluster
#                              / ClusterNode / ClusterResource
#
# PREREQUISITES NOT MANAGED HERE (outside scope for a config-as-code sample):
#   - Both cluster nodes are on the same AD domain
#   - Shared disks or S2D configured
#   - Network interfaces tagged for public / cluster / replication roles
#
# Run:
#   $env:DSC_MODE    = "audit"
#   $env:DSC_PROFILE = "wsfc"
#   . C:\ProgramData\ssm-converge\lib.ps1
#   . examples\windows\wsfc-cluster.ps1
# =============================================================================

. C:\ProgramData\ssm-converge\lib.ps1

$ClusterName    = 'WSFC01'
$ClusterStaticIp = '10.0.1.100/24'
$Node1          = 'WSFC01-A'
$Node2          = 'WSFC01-B'

# -- 1. Required Windows features -------------------------------------------

WindowsFeature 'Failover-Clustering' Installed -IncludeManagementTools
WindowsFeature 'RSAT-Clustering'     Installed

# -- 2. DSC module for cluster resources ------------------------------------
#    FailoverClusterDsc ships the Cluster / ClusterNode / ClusterResource DSC
#    resources we delegate to for the actual cluster operations.

PowerShellModule 'PSDscResources'     Installed
PowerShellModule 'FailoverClusterDsc' Installed

# -- 3. Host entries for both nodes -----------------------------------------
#    Pre-resolving peer names avoids DNS-timing issues during cluster create.

HostEntry '10.0.1.11' Present -Hostname "$Node1 $Node1.corp.example.com"
HostEntry '10.0.1.12' Present -Hostname "$Node2 $Node2.corp.example.com"

# -- 4. Cluster admin group on each node ------------------------------------
#    A local group where cluster-admin service accounts can be added.

LocalGroup 'ClusterAdmins' Present -Description 'Cluster administrators (local)'

# -- 5. Cluster creation -----------------------------------------------------
#    ONLY run this on the first node. Uses the generic DscResource wrapper
#    around FailoverClusterDsc.Cluster - same as the MSSQL FCI example.
#
#    In audit mode this just reports "drift" if the cluster doesn't exist.
#    In enforce mode it would create the cluster.
#
#    GUARD: determine "am I node1?" from hostname. Skip on other nodes.

if ($env:COMPUTERNAME -ieq $Node1) {
    DscResource -Name Cluster -Module FailoverClusterDsc -Properties @{
        Name                = $ClusterName
        StaticIPAddress     = $ClusterStaticIp
        Ensure              = 'Present'
    }
} else {
    # -- 5b. On additional nodes, join the existing cluster ----------------

    DscResource -Name ClusterNode -Module FailoverClusterDsc -Properties @{
        Name    = $env:COMPUTERNAME
        Cluster = $ClusterName
        Ensure  = 'Present'
    } -ResourceId "$env:COMPUTERNAME@$ClusterName"
}

# -- 6. Report ---------------------------------------------------------------

Report-Compliance

if (Test-RebootRequired) {
    Write-Host ""
    Write-Host "Reboot required (Failover-Clustering feature install). Reboot and re-run."
}
