# Windows EC2 test: all four modes (audit, enforce, comply, destroy) + idempotency.

# Reset state from any previous run.
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\modes-test
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue HKLM:\SOFTWARE\SSMConverge\ModesTest
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue `
    C:\ProgramData\ssm-converge\history,
    C:\ProgramData\ssm-converge\latest.json,
    C:\ProgramData\ssm-converge\drift.log

$env:DSC_PROFILE = "ModesTest"

function Reset-Run {
    $script:DscResults.Clear()
    $script:DscHandlersTriggered.Clear()
}

# -------------------------------------------------------------------
Write-Host ""
Write-Host "============================================="
Write-Host "  1. AUDIT mode (no changes)"
Write-Host "============================================="
$env:DSC_MODE = "audit"
. C:\ProgramData\ssm-converge\lib.ps1

Directory "C:\modes-test"               Present
File-Content -Path "C:\modes-test\app.conf" -Content "v=1"
RegistryKey "HKLM:\SOFTWARE\SSMConverge\ModesTest" Present -ValueName "Version" -ValueData "0.1.0"
WindowsService "W32Time" Running -StartupType Automatic

Report-Compliance
Write-Host "post-audit: modes-test exists? $(Test-Path C:\modes-test)"

# -------------------------------------------------------------------
Reset-Run
Write-Host ""
Write-Host "============================================="
Write-Host "  2. ENFORCE mode (fix drift)"
Write-Host "============================================="
$env:DSC_MODE = "enforce"
. C:\ProgramData\ssm-converge\lib.ps1

Directory "C:\modes-test"               Present
File-Content -Path "C:\modes-test\app.conf" -Content "v=1"
RegistryKey "HKLM:\SOFTWARE\SSMConverge\ModesTest" Present -ValueName "Version" -ValueData "0.1.0"
WindowsService "W32Time" Running -StartupType Automatic

Report-Compliance
Write-Host "post-enforce: modes-test=$(Test-Path C:\modes-test), file=$(Test-Path C:\modes-test\app.conf), regkey=$(Test-Path HKLM:\SOFTWARE\SSMConverge\ModesTest)"

# -------------------------------------------------------------------
Reset-Run
Write-Host ""
Write-Host "============================================="
Write-Host "  3. ENFORCE again (idempotency: 0 changed)"
Write-Host "============================================="
. C:\ProgramData\ssm-converge\lib.ps1

Directory "C:\modes-test"               Present
File-Content -Path "C:\modes-test\app.conf" -Content "v=1"
RegistryKey "HKLM:\SOFTWARE\SSMConverge\ModesTest" Present -ValueName "Version" -ValueData "0.1.0"
WindowsService "W32Time" Running -StartupType Automatic

Report-Compliance

# -------------------------------------------------------------------
Reset-Run
Write-Host ""
Write-Host "============================================="
Write-Host "  4. COMPLY mode (full report)"
Write-Host "============================================="
$env:DSC_MODE = "audit"
$env:DSC_REPORT = "full"
. C:\ProgramData\ssm-converge\lib.ps1

Directory "C:\modes-test"               Present
File-Content -Path "C:\modes-test\app.conf" -Content "v=1"
RegistryKey "HKLM:\SOFTWARE\SSMConverge\ModesTest" Present -ValueName "Version" -ValueData "0.1.0"
WindowsService "W32Time" Running -StartupType Automatic

Report-Compliance
$env:DSC_REPORT = "summary"

# -------------------------------------------------------------------
Reset-Run
Write-Host ""
Write-Host "============================================="
Write-Host "  5. DESTROY mode (flip state, tear down)"
Write-Host "============================================="
$env:DSC_MODE = "destroy"
. C:\ProgramData\ssm-converge\lib.ps1

Directory "C:\modes-test"               Present
File-Content -Path "C:\modes-test\app.conf" -Content "v=1"
RegistryKey "HKLM:\SOFTWARE\SSMConverge\ModesTest" Present -ValueName "Version" -ValueData "0.1.0"

Report-Compliance
Write-Host "post-destroy: modes-test=$(Test-Path C:\modes-test), regkey=$(Test-Path HKLM:\SOFTWARE\SSMConverge\ModesTest)"
