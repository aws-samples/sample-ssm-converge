# =============================================================================
# SSM Converge - Resource Provider: ScheduledTask
#
# Windows equivalent of the Linux `cron` resource. Wraps the ScheduledTasks
# module (Register-ScheduledTask etc.).
#
# Usage:
#   # Daily at 02:00:
#   ScheduledTask 'Nightly-Cleanup' Present `
#       -Execute  'powershell.exe' `
#       -Argument '-NoProfile -File C:\scripts\cleanup.ps1' `
#       -Daily    '02:00' `
#       -RunAsUser 'SYSTEM'
#
#   # Every 30 minutes:
#   ScheduledTask 'Health-Check' Present `
#       -Execute  'C:\scripts\health.ps1' `
#       -IntervalMinutes 30 `
#       -RunAsUser 'SYSTEM'
#
# A sentinel description comment ('[managed by ssm-converge]') is added to
# flag tasks under our control - without touching tasks created by other tools.
# =============================================================================

function ScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$Execute,
        [string]$Argument,
        [string]$Daily,           # HH:mm
        [int]$IntervalMinutes,
        [string]$RunAsUser = 'SYSTEM',
        [string]$Path = '\'
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "scheduled_task/$Name"
    $marker       = '[managed by ssm-converge]'

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        _Log-Error $resourceName "ScheduledTasks module not available"
        _Record-Result $resourceName 'error' $false 'ScheduledTasks missing'
        return
    }

    $existing = Get-ScheduledTask -TaskName $Name -TaskPath $Path -ErrorAction SilentlyContinue

    switch ($State) {
        'Present' {
            # Compose the desired trigger + action.
            if (-not $Execute) {
                $checkMs = (Get-NowMs) - $checkStart
                _Log-Error $resourceName "-Execute is required for Present"
                _Record-Result $resourceName 'error' $false 'missing -Execute' $checkMs 0
                return
            }

            $isManaged = $false
            if ($existing) {
                $isManaged = ($existing.Description -match [regex]::Escape($marker))
            }

            $checkMs = (Get-NowMs) - $checkStart

            if ($existing -and $isManaged) {
                # Rough idempotency check: action matches.
                $existingAction = $existing.Actions | Select-Object -First 1
                $sameExec = ($existingAction.Execute -eq $Execute)
                $sameArg  = ([string]$existingAction.Arguments -eq [string]$Argument)
                if ($sameExec -and $sameArg) {
                    _Log-Ok $resourceName
                    _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                    return
                }
            }

            if (-not (_Should-Apply)) {
                $detail = if ($existing) { 'exists but differs' } else { 'missing' }
                _Log-Drift $resourceName $detail
                _Record-Result $resourceName 'non_compliant' $false $detail $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                # Build trigger.
                $trigger = $null
                if ($Daily)            { $trigger = New-ScheduledTaskTrigger -Daily -At $Daily }
                elseif ($IntervalMinutes) {
                    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
                }
                else { throw "ScheduledTask requires either -Daily HH:mm or -IntervalMinutes N" }

                $actionParams = @{ Execute = $Execute }
                if ($Argument) { $actionParams['Argument'] = $Argument }
                $action = New-ScheduledTaskAction @actionParams

                $principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType ServiceAccount -RunLevel Highest

                if ($existing) {
                    Unregister-ScheduledTask -TaskName $Name -TaskPath $Path -Confirm:$false -ErrorAction Stop
                }
                Register-ScheduledTask -TaskName $Name -TaskPath $Path `
                    -Action $action -Trigger $trigger -Principal $principal `
                    -Description "$marker - $Name" -Force -ErrorAction Stop | Out-Null

                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName 'registered'
                _Record-Result $resourceName 'compliant' $true 'registered' $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }

        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart
            if (-not $existing) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'exists (should be absent)'
                _Record-Result $resourceName 'non_compliant' $false 'exists' $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                Unregister-ScheduledTask -TaskName $Name -TaskPath $Path -Confirm:$false -ErrorAction Stop
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName 'removed'
                _Record-Result $resourceName 'compliant' $true 'removed' $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }
    }
}
