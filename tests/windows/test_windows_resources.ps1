# Windows EC2 sanity test: exercise every new resource once in audit mode
# (no system changes). We just want to prove the functions load and their
# check phase runs without crashing.

$env:DSC_MODE    = "audit"
$env:DSC_PROFILE = "WinResSweep"
. C:\ProgramData\ssm-converge\lib.ps1

Write-Host "=== Resource sweep (audit mode, no changes) ==="

# 1. LocalUser
LocalUser 'svc_ssmconverge_test' Present -FullName 'SSM Converge test user' -Description 'audit-mode test'

# 2. LocalGroup
LocalGroup 'SSMConvergeTesters' Present -Members 'Administrator','Guest'

# 3. HostEntry
HostEntry '10.77.0.9' Present -Hostname 'winresource.test.internal'

# 4. EnvironmentVariable
EnvironmentVariable 'SSMCONVERGE_TEST' Present -Value 'hello-from-audit' -Target Machine

# 5. ScheduledTask
ScheduledTask 'SSMConverge-Test-Task' Present `
    -Execute  'powershell.exe' `
    -Argument '-NoProfile -Command "Write-Output hi"' `
    -Daily    '03:00' `
    -RunAsUser 'SYSTEM'

# 6. WindowsFeature (checks installed state; RSAT-AD-PowerShell might not be installed)
WindowsFeature 'RSAT-AD-PowerShell' Installed

# 7. PowerShellModule (should report missing unless already installed)
PowerShellModule 'FailoverClusterDsc' Installed

# 8. DscResource - use WindowsFeature from PSDscResources (ships in box on 5.1)
DscResource -Name WindowsFeature -Module PSDesiredStateConfiguration -Properties @{
    Name   = 'Telnet-Client'
    Ensure = 'Absent'
}

Report-Compliance
