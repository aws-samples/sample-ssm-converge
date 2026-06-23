# =============================================================================
# SSM Distributor install script for ssm-converge (Windows).
#
# SSM Agent unpacks the package into the current working directory before
# invoking this script. Package layout (produced by build-package.sh):
#
#   install.ps1                <- this file
#   uninstall.ps1
#   src\lib.ps1
#   src\resources\*.ps1
#   cli\ssm-converge.ps1
#
# This script copies the library into place and makes the CLI addressable.
# =============================================================================

$ErrorActionPreference = 'Stop'

$InstallPath = if ($env:INSTALL_PATH) { $env:INSTALL_PATH } else { 'C:\ProgramData\ssm-converge' }
$CliPath     = Join-Path $InstallPath 'ssm-converge.ps1'
$StateRoot   = 'C:\ProgramData\ssm-converge'     # Same for now; compliance state lives next to the library.

Write-Host "[ssm-converge] Installing to $InstallPath"

# Clean previous install so we don't leave stale files behind. We keep any
# compliance history by only wiping the library + CLI, not the whole StateRoot.
if (Test-Path $InstallPath) {
    # Remove lib.ps1, resources/, old ssm-converge.ps1. Leave latest.json + history/ alone.
    foreach ($toRemove in @('lib.ps1','resources','ssm-converge.ps1')) {
        $p = Join-Path $InstallPath $toRemove
        if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Create the install directory (covers first-time install and any gaps).
$null = New-Item -ItemType Directory -Force -Path $InstallPath
$null = New-Item -ItemType Directory -Force -Path (Join-Path $StateRoot 'history')

# Copy lib.ps1 and resources/ from the unpacked package.
Copy-Item -Path 'src\lib.ps1' -Destination (Join-Path $InstallPath 'lib.ps1') -Force
$null = New-Item -ItemType Directory -Force -Path (Join-Path $InstallPath 'resources')
Copy-Item -Path 'src\resources\*' -Destination (Join-Path $InstallPath 'resources') -Recurse -Force

# Install the CLI alongside the library. Users call it with `& $CliPath` or
# add $InstallPath to PATH.
Copy-Item -Path 'cli\ssm-converge.ps1' -Destination $CliPath -Force

# Surface a discoverable shim: if PowerShell is on PATH and $env:PATH already
# contains WindowsApps, dropping the CLI here makes `ssm-converge` resolve
# naturally. We skip the PATH edit - leaving PATH management to the operator
# is the safer default for a shared Windows box.

# Report what we installed, so Distributor's exit log is useful.
$version = Get-Content (Join-Path $InstallPath 'lib.ps1') |
    Select-String -Pattern '^\s*\$script:SsmConvergeVersion\s*=\s*''([^'']+)''' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Select-Object -First 1

Write-Host "[ssm-converge] Installed version: $version"
Write-Host "[ssm-converge] Library path:      $InstallPath"
Write-Host "[ssm-converge] CLI path:          $CliPath"
Write-Host "[ssm-converge] Invoke CLI with:"
Write-Host "                 & '$CliPath' help"
