# =============================================================================
# SSM Converge - Resource Provider: DscResource (generic wrapper)
#
# Invokes any DSC resource (from any installed module) through SSM Converge's
# modes/reporting pipeline. You get SSM Converge's check/apply/idempotent-
# report semantics around the DSC resources you already depend on.
#
# Works with ANY class-based or MOF-based DSC resource installed on the host.
# Examples of modules this is designed to delegate to:
#   - PSDscResources       (WindowsFeature, Script, etc.)
#   - FailoverClusterDsc   (Cluster, ClusterNode, ClusterResource, ...)
#   - ComputerManagementDsc (Computer, ScheduledTask, TimeZone, ...)
#   - CertificateDsc       (CertificateImport, PfxImport, ...)
#   - ActiveDirectoryDsc   (ADUser, ADServiceAccount, ADGroup, ...)
#   - SqlServerDsc, NetworkingDsc, StorageDsc, ...
#
# How it works:
#   1. Invoke-DscResource -Method Test  -> compliant / non-compliant
#   2. Invoke-DscResource -Method Set   (only if enforce/destroy mode)
#   3. Re-Test afterwards to confirm convergence
#
# Usage:
#   # FailoverClusterDsc cluster creation (replaces FailoverClusterDsc.Cluster):
#   DscResource -Name Cluster -Module FailoverClusterDsc -Properties @{
#       Name            = 'SQLCluster01'
#       StaticIPAddress = '10.0.1.100/24'
#       Ensure          = 'Present'
#   }
#
#   # ComputerManagementDsc domain join (replaces Computer resource):
#   DscResource -Name Computer -Module ComputerManagementDsc -Properties @{
#       Name       = 'SQL01-A'
#       DomainName = 'corp.example.com'
#       Credential = $joinCred
#   }
#
#   # ActiveDirectoryDsc managed service account:
#   DscResource -Name ADManagedServiceAccount -Module ActiveDirectoryDsc -Properties @{
#       ServiceAccountName = 'svc-sql01'
#       AccountType        = 'Group'
#       Members            = 'SQL01-A$','SQL01-B$'
#       Ensure             = 'Present'
#   }
#
# Notes:
#   - The DSC resource module must be installed first (use PowerShellModule).
#   - In destroy mode we set Ensure='Absent' if the properties hash has Ensure.
#   - Properties are passed straight through; we don't validate them.
# =============================================================================

function DscResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][hashtable]$Properties,
        [string]$ResourceId   # Optional label suffix; defaults to a stable key derived from Properties.
    )

    # Compose a stable identifier for the report. DSC resources have a "key"
    # (usually 'Name' or 'DomainName' or similar) - the caller can override
    # with -ResourceId if the default isn't helpful.
    if (-not $ResourceId) {
        $keyCandidates = @('Name','DomainName','Path','ServiceAccountName','Id','Identity')
        foreach ($k in $keyCandidates) {
            if ($Properties.ContainsKey($k)) { $ResourceId = $Properties[$k]; break }
        }
        if (-not $ResourceId) { $ResourceId = '<anonymous>' }
    }
    $resourceName = "dsc/$Module/$Name/$ResourceId"

    # Destroy mode: flip Ensure if the resource supports it.
    if (_Is-DestroyMode -and $Properties.ContainsKey('Ensure')) {
        $Properties = @{} + $Properties   # copy so we don't mutate caller's hash
        $Properties['Ensure'] = if ($Properties['Ensure'] -eq 'Absent') { 'Present' } else { 'Absent' }
    }

    # Guard: PSDesiredStateConfiguration must be available to call
    # Invoke-DscResource. It ships with Windows PowerShell 5.1; on PS 7 you
    # need the PSDesiredStateConfiguration v2 module installed.
    if (-not (Get-Command Invoke-DscResource -ErrorAction SilentlyContinue)) {
        _Log-Error $resourceName "Invoke-DscResource not available. Install PSDesiredStateConfiguration."
        _Record-Result $resourceName 'error' $false 'Invoke-DscResource missing'
        return
    }

    $checkStart = Get-NowMs

    # -- Test phase -----------------------------------------------------------
    $testResult = $null
    try {
        $testResult = Invoke-DscResource -Name $Name -ModuleName $Module `
            -Method Test -Property $Properties -ErrorAction Stop
    } catch {
        $checkMs = (Get-NowMs) - $checkStart
        _Log-Error $resourceName "DSC Test failed: $($_.Exception.Message)"
        _Record-Result $resourceName 'error' $false "Test: $($_.Exception.Message)" $checkMs 0
        return
    }

    $inDesiredState = [bool]$testResult.InDesiredState
    $checkMs = (Get-NowMs) - $checkStart

    if ($inDesiredState) {
        _Log-Ok $resourceName
        _Record-Result $resourceName 'compliant' $false '' $checkMs 0
        return
    }

    if (-not (_Should-Apply)) {
        _Log-Drift $resourceName 'not in desired state (DSC Test returned false)'
        _Record-Result $resourceName 'non_compliant' $false 'drift' $checkMs 0
        return
    }

    # -- Set phase ------------------------------------------------------------
    $applyStart = Get-NowMs
    $setResult = $null
    try {
        $setResult = Invoke-DscResource -Name $Name -ModuleName $Module `
            -Method Set -Property $Properties -ErrorAction Stop
    } catch {
        $applyMs = (Get-NowMs) - $applyStart
        _Log-Error $resourceName "DSC Set failed: $($_.Exception.Message)"
        _Record-Result $resourceName 'error' $false "Set: $($_.Exception.Message)" $checkMs $applyMs
        return
    }

    if ($setResult -and $setResult.RebootRequired) {
        Request-Reboot "DSC resource $Module/$Name"
    }

    # -- Verify by re-testing -------------------------------------------------
    $verifyOk = $true
    try {
        $verify = Invoke-DscResource -Name $Name -ModuleName $Module `
            -Method Test -Property $Properties -ErrorAction Stop
        $verifyOk = [bool]$verify.InDesiredState
    } catch {
        $verifyOk = $false
    }

    $applyMs = (Get-NowMs) - $applyStart
    if ($verifyOk) {
        _Log-Changed $resourceName 'converged'
        _Record-Result $resourceName 'compliant' $true 'converged' $checkMs $applyMs
    } else {
        _Log-Error $resourceName "DSC Set completed but Test still reports drift"
        _Record-Result $resourceName 'error' $false 'set did not converge' $checkMs $applyMs
    }
}
