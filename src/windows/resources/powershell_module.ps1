# =============================================================================
# SSM Converge - Resource Provider: PowerShellModule
#
# Replaces the Install-FeaturesAndModules.ps1 pattern where PSDscResources,
# FailoverClusterDsc, ComputerManagementDsc (etc.) are pulled in via
# Install-Module. Uses PowerShellGet's Install-Module / Uninstall-Module.
#
# Usage:
#   PowerShellModule 'FailoverClusterDsc'    Installed
#   PowerShellModule 'ComputerManagementDsc' Installed -Version '8.5.0'
#   PowerShellModule 'AzureRM'               Uninstalled
#   PowerShellModule 'MyInternal'            Installed -Repository InternalPSGallery
# =============================================================================

function PowerShellModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Installed','Uninstalled','Present','Absent')][string]$State,
        [string]$Version,
        [string]$Repository = 'PSGallery',
        [ValidateSet('CurrentUser','AllUsers')][string]$Scope = 'AllUsers'
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }
    $wantInstalled = ($State -eq 'Installed' -or $State -eq 'Present')

    $checkStart   = Get-NowMs
    $resourceName = if ($Version) { "psmodule/$Name@$Version" } else { "psmodule/$Name" }

    # Ensure PowerShellGet is loaded.
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        _Log-Error $resourceName "PowerShellGet (Install-Module) not available"
        _Record-Result $resourceName 'error' $false 'PowerShellGet missing'
        return
    }

    # On fresh Windows PowerShell 5.1 installs, Install-Module prompts to bootstrap
    # the NuGet provider on first use. That prompt fails under SSM (non-interactive).
    # Pre-install the NuGet provider silently once; subsequent Install-Module calls
    # are then non-interactive.
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        } catch {
            # Best-effort - if this fails, Install-Module will fail later with a clearer error.
        }
    }

    # Check current install.
    $installed = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending
    $versionMatches = $true
    if ($Version -and $installed) {
        $versionMatches = ($installed | Where-Object { $_.Version -eq $Version })
    }
    $isInstalled = [bool]$installed -and $versionMatches

    $checkMs = (Get-NowMs) - $checkStart

    if ($wantInstalled -and $isInstalled) {
        _Log-Ok $resourceName
        _Record-Result $resourceName 'compliant' $false '' $checkMs 0
        return
    }
    if (-not $wantInstalled -and -not $installed) {
        _Log-Ok $resourceName
        _Record-Result $resourceName 'compliant' $false '' $checkMs 0
        return
    }

    if (-not (_Should-Apply)) {
        $detail = if ($wantInstalled) {
            if ($installed) { "version mismatch (have $($installed[0].Version), want $Version)" } else { 'not installed' }
        } else { 'still installed' }
        _Log-Drift $resourceName $detail
        _Record-Result $resourceName 'non_compliant' $false $detail $checkMs 0
        return
    }

    # Ensure the repository is trusted (PSGallery is Untrusted by default,
    # which blocks Install-Module in non-interactive sessions).
    try {
        $repo = Get-PSRepository -Name $Repository -ErrorAction Stop
        if ($repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name $Repository -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore - Install-Module will -Force through it below.
    }

    $applyStart = Get-NowMs
    try {
        if ($wantInstalled) {
            $params = @{
                Name        = $Name
                Scope       = $Scope
                Force       = $true
                AllowClobber= $true
                Repository  = $Repository
                ErrorAction = 'Stop'
            }
            if ($Version) { $params['RequiredVersion'] = $Version }
            Install-Module @params
            Import-Module $Name -Force -ErrorAction SilentlyContinue | Out-Null
        } else {
            # Uninstall all installed versions.
            Get-InstalledModule -Name $Name -AllVersions | ForEach-Object {
                Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force -ErrorAction Stop
            }
        }

        $applyMs = (Get-NowMs) - $applyStart
        $action = if ($wantInstalled) { 'installed' } else { 'uninstalled' }
        _Log-Changed $resourceName $action
        _Record-Result $resourceName 'compliant' $true $action $checkMs $applyMs
    } catch {
        $applyMs = (Get-NowMs) - $applyStart
        _Log-Error $resourceName $_.Exception.Message
        _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
    }
}
