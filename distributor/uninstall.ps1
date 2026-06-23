# =============================================================================
# SSM Distributor uninstall script for ssm-converge (Windows).
# Removes the library + CLI. Compliance history under C:\ProgramData\ssm-converge
# (latest.json, history\, drift.log, ssm-converge.log) is preserved so you
# don't lose audit data on upgrade.
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'

$InstallPath = if ($env:INSTALL_PATH) { $env:INSTALL_PATH } else { 'C:\ProgramData\ssm-converge' }
$CliPath     = Join-Path $InstallPath 'ssm-converge.ps1'

Write-Host "[ssm-converge] Removing library at $InstallPath"
foreach ($toRemove in @('lib.ps1','resources','ssm-converge.ps1')) {
    $p = Join-Path $InstallPath $toRemove
    if (Test-Path $p) {
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}

Write-Host "[ssm-converge] Compliance history left at $InstallPath\ (latest.json, history\, drift.log)"
Write-Host "[ssm-converge] Uninstall complete."
