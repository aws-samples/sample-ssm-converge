# ===============================================================================
# SSM Converge - Resource Provider: Package (Windows)
#
# Tries package managers in this order: winget, Chocolatey (choco), MSI (via
# Get-Package). winget ships with Windows 10/11 and Server 2022+; Chocolatey is
# a common add-on.
#
# Usage:
#   Package '7zip.7zip' Installed          # winget id or choco id
#   Package 'notepadplusplus' Uninstalled
# ===============================================================================

function _Detect-PkgManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return 'winget' }
    if (Get-Command choco  -ErrorAction SilentlyContinue) { return 'choco' }
    return 'msi'   # PowerShell Get-Package fallback - MSI installers
}

function _Package-Is-Installed {
    param([string]$Manager,[string]$Name)
    switch ($Manager) {
        'winget' {
            $out = & winget list --id $Name --exact --disable-interactivity 2>$null | Out-String
            return ($LASTEXITCODE -eq 0 -and $out -match [regex]::Escape($Name))
        }
        'choco' {
            $out = & choco list --local-only --exact --limit-output $Name 2>$null | Out-String
            return ($LASTEXITCODE -eq 0 -and $out.Trim() -ne '')
        }
        default {
            return [bool](Get-Package -Name $Name -ErrorAction SilentlyContinue)
        }
    }
}

function _Package-Install {
    param([string]$Manager,[string]$Name)
    switch ($Manager) {
        'winget' { & winget install --id $Name --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null }
        'choco'  { & choco install $Name -y --no-progress 2>&1 | Out-Null }
        default  { Install-Package -Name $Name -Force -ErrorAction Stop | Out-Null }
    }
    return $LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE
}

function _Package-Remove {
    param([string]$Manager,[string]$Name)
    switch ($Manager) {
        'winget' { & winget uninstall --id $Name --exact --silent --disable-interactivity 2>&1 | Out-Null }
        'choco'  { & choco uninstall $Name -y --no-progress 2>&1 | Out-Null }
        default  { Uninstall-Package -Name $Name -Force -ErrorAction Stop | Out-Null }
    }
    return $LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE
}

function Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Installed','Uninstalled','Present','Absent')][string]$State
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "package/$Name"

    $manager = _Detect-PkgManager
    $installed = _Package-Is-Installed $manager $Name
    $checkMs = (Get-NowMs) - $checkStart

    $wantInstalled = ($State -eq 'Installed' -or $State -eq 'Present')

    if ($wantInstalled -and $installed) {
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
        $detail = if ($wantInstalled) { 'not installed' } else { 'still installed' }
        _Log-Drift $resourceName $detail
        _Record-Result $resourceName 'non_compliant' $false $detail $checkMs 0
        return
    }

    $applyStart = Get-NowMs
    try {
        if ($wantInstalled) {
            $ok = _Package-Install $manager $Name
            if ($ok -and (_Package-Is-Installed $manager $Name)) {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName "installed (via $manager)"
                _Record-Result $resourceName 'compliant' $true "installed via $manager" $checkMs $applyMs
            } else {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName "install failed (via $manager)"
                _Record-Result $resourceName 'error' $false "install failed via $manager" $checkMs $applyMs
            }
        } else {
            $ok = _Package-Remove $manager $Name
            $applyMs = (Get-NowMs) - $applyStart
            if ($ok -and -not (_Package-Is-Installed $manager $Name)) {
                _Log-Changed $resourceName "removed (via $manager)"
                _Record-Result $resourceName 'compliant' $true "removed via $manager" $checkMs $applyMs
            } else {
                _Log-Error $resourceName "remove failed (via $manager)"
                _Record-Result $resourceName 'error' $false "remove failed via $manager" $checkMs $applyMs
            }
        }
    } catch {
        $applyMs = (Get-NowMs) - $applyStart
        _Log-Error $resourceName $_.Exception.Message
        _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
    }
}
