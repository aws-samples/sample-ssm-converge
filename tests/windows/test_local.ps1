# ===============================================================================
# SSM Converge - Local PowerShell smoke test.
# Runs on Windows + PowerShell Core on any OS (where file/registry operations
# that require Windows are skipped gracefully).
# ===============================================================================

$env:SSM_CONVERGE_HOME = Resolve-Path (Join-Path $PSScriptRoot '..\..\src\windows') | Select-Object -ExpandProperty Path
$env:DSC_MODE          = 'enforce'
$env:DSC_PROFILE       = 'ps-local-test'
$env:DSC_LOCAL_DIR     = Join-Path $env:TEMP 'ssm-converge-pstest'
$env:DSC_LOG_FILE      = Join-Path $env:TEMP 'ssm-converge-pstest.log'
$env:DSC_VERBOSE       = 'true'

# Clean slate.
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue `
    $env:DSC_LOCAL_DIR,
    (Join-Path $env:TEMP 'ssm-converge-pstestfiles')

$testDir = Join-Path $env:TEMP 'ssm-converge-pstestfiles'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null

. (Join-Path $env:SSM_CONVERGE_HOME 'lib.ps1')

# -- Test: Directory -----------------------------------------------------------
Directory (Join-Path $testDir 'app')         Present
Directory (Join-Path $testDir 'app\config')  Present
Directory (Join-Path $testDir 'app\logs')    Present

# -- Test: File with inline content --------------------------------------------
File (Join-Path $testDir 'app\config\app.conf') Present -Content "port=8080`nworkers=4"

# -- Test: File-Content (heredoc-style) ----------------------------------------
File-Content -Path (Join-Path $testDir 'app\config\settings.json') -Content @'
{
    "app": {
        "name": "myapp",
        "port": 8080
    }
}
'@

# -- Test: File Absent ---------------------------------------------------------
$toDelete = Join-Path $testDir 'delete_me.txt'
New-Item -ItemType File -Force -Path $toDelete | Out-Null
File $toDelete Absent

# -- Test: Directory Absent ----------------------------------------------------
$toRemove = Join-Path $testDir 'remove_this'
New-Item -ItemType Directory -Force -Path $toRemove | Out-Null
Directory $toRemove Absent

Report-Compliance

Write-Host ''
Write-Host '=== Verification ==='
Write-Host ''
Write-Host "Directory created:"
Get-ChildItem (Join-Path $testDir 'app\config') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host ''
Write-Host "app.conf content:"
Get-Content (Join-Path $testDir 'app\config\app.conf') -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "File deleted: $(if (Test-Path $toDelete) { 'NO (BUG)' } else { 'YES' })"
Write-Host "Directory deleted: $(if (Test-Path $toRemove) { 'NO (BUG)' } else { 'YES' })"
Write-Host ''
Write-Host 'Local compliance report:'
Get-Content (Join-Path $env:DSC_LOCAL_DIR 'latest.json') -ErrorAction SilentlyContinue
