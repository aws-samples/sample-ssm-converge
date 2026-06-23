# =============================================================================
# SSM Converge - Resource Provider: WindowsFeature
#
# Replaces the PSDscResources WindowsFeature / WindowsOptionalFeature resource.
# Manages Windows Server roles and features (e.g. Failover-Clustering, RSAT-AD-
# PowerShell) via the ServerManager module.
#
# Usage:
#   WindowsFeature 'Failover-Clustering'             Installed -IncludeManagementTools
#   WindowsFeature 'RSAT-AD-PowerShell'              Installed
#   WindowsFeature 'FS-SMB1'                         Uninstalled
#   WindowsFeature 'NET-Framework-Core','NET-Framework-45-Core' Installed
#
# Set -Reboot Force to reboot immediately when required, or leave default so a
# reboot request is recorded and the configuration can check Test-RebootRequired
# at the end.
# =============================================================================

function WindowsFeature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string[]]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Installed','Uninstalled','Present','Absent')][string]$State,
        [switch]$IncludeManagementTools,
        [switch]$IncludeAllSubFeature,
        [string]$Source   # Optional side-by-side SxS path for offline installs.
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }
    $wantInstalled = ($State -eq 'Installed' -or $State -eq 'Present')

    # Ensure ServerManager is available (pre-installed on Windows Server).
    if (-not (Get-Module -ListAvailable ServerManager -ErrorAction SilentlyContinue)) {
        foreach ($n in $Name) {
            _Log-Error "windows_feature/$n" "ServerManager module not available (Windows Server required)"
            _Record-Result "windows_feature/$n" 'error' $false 'ServerManager missing'
        }
        return
    }
    Import-Module ServerManager -ErrorAction SilentlyContinue

    foreach ($featureName in $Name) {
        $checkStart   = Get-NowMs
        $resourceName = "windows_feature/$featureName"

        $feat = Get-WindowsFeature -Name $featureName -ErrorAction SilentlyContinue
        if (-not $feat) {
            $checkMs = (Get-NowMs) - $checkStart
            _Log-Error $resourceName "feature not recognised on this host"
            _Record-Result $resourceName 'error' $false 'unknown feature' $checkMs 0
            continue
        }

        # InstallState values: 'Installed', 'InstallPending' (reboot needed),
        # 'Available', 'Removed'. Treat InstallPending as installed for
        # idempotency purposes.
        $isInstalled = ($feat.InstallState -eq 'Installed' -or $feat.InstallState -eq 'InstallPending')
        $checkMs = (Get-NowMs) - $checkStart

        if ($wantInstalled -and $isInstalled) {
            _Log-Ok $resourceName
            _Record-Result $resourceName 'compliant' $false '' $checkMs 0
            continue
        }
        if (-not $wantInstalled -and -not $isInstalled) {
            _Log-Ok $resourceName
            _Record-Result $resourceName 'compliant' $false '' $checkMs 0
            continue
        }

        if (-not (_Should-Apply)) {
            $detail = if ($wantInstalled) { 'not installed' } else { 'still installed' }
            _Log-Drift $resourceName $detail
            _Record-Result $resourceName 'non_compliant' $false $detail $checkMs 0
            continue
        }

        $applyStart = Get-NowMs
        try {
            if ($wantInstalled) {
                $params = @{ Name = $featureName; ErrorAction = 'Stop' }
                if ($IncludeManagementTools) { $params['IncludeManagementTools'] = $true }
                if ($IncludeAllSubFeature)   { $params['IncludeAllSubFeature']   = $true }
                if ($Source)                 { $params['Source']                 = $Source }
                $result = Install-WindowsFeature @params
            } else {
                $result = Uninstall-WindowsFeature -Name $featureName -ErrorAction Stop
            }

            $applyMs = (Get-NowMs) - $applyStart
            if ($result.RestartNeeded -eq 'Yes') {
                Request-Reboot "windows feature: $featureName"
            }

            $now = Get-WindowsFeature -Name $featureName
            $nowInstalled = ($now.InstallState -eq 'Installed' -or $now.InstallState -eq 'InstallPending')
            if ($wantInstalled -eq $nowInstalled) {
                $action = if ($wantInstalled) {
                    if ($now.InstallState -eq 'InstallPending') { 'installed (reboot pending)' } else { 'installed' }
                } else { 'uninstalled' }
                _Log-Changed $resourceName $action
                _Record-Result $resourceName 'compliant' $true $action $checkMs $applyMs
            } else {
                _Log-Error $resourceName "apply did not converge (install state: $($now.InstallState))"
                _Record-Result $resourceName 'error' $false "did not converge: $($now.InstallState)" $checkMs $applyMs
            }
        } catch {
            $applyMs = (Get-NowMs) - $applyStart
            _Log-Error $resourceName $_.Exception.Message
            _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
        }
    }
}
