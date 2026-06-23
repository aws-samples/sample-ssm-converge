# =============================================================================
# SSM Converge - Resource Provider: EnvironmentVariable
#
# Manages Machine or User-scoped environment variables persistently.
#
# Usage:
#   EnvironmentVariable 'JAVA_HOME'  Present -Value 'C:\Program Files\Java\jdk-17'
#   EnvironmentVariable 'LEGACY_VAR' Absent
#   EnvironmentVariable 'PATH'       Present -Value 'C:\Tools;%PATH%' -Path   # appends
#
# Target defaults to 'Machine'. Valid: Machine, User, Process.
# =============================================================================

function EnvironmentVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$Value,
        [ValidateSet('Machine','User','Process')][string]$Target = 'Machine',
        [switch]$Path   # Treat as PATH-style list; append / dedupe.
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "env/$Target/$Name"
    $envTarget    = [System.EnvironmentVariableTarget]::$Target

    $current = [Environment]::GetEnvironmentVariable($Name, $envTarget)

    switch ($State) {
        'Present' {
            $desired = $Value
            if ($Path -and $current) {
                # Append Value items to current PATH if not already present.
                $currentItems = $current -split ';' | Where-Object { $_ }
                $wantItems    = $Value   -split ';' | Where-Object { $_ }
                $missing      = $wantItems | Where-Object { $_ -notin $currentItems }
                $desired = if ($missing) { ($currentItems + $missing) -join ';' } else { $current }
            }

            $checkMs = (Get-NowMs) - $checkStart
            if ($current -eq $desired) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'value mismatch'
                _Record-Result $resourceName 'non_compliant' $false "is '$current', want '$desired'" $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                [Environment]::SetEnvironmentVariable($Name, $desired, $envTarget)
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName "set to '$desired'"
                _Record-Result $resourceName 'compliant' $true "set to $desired" $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }
        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart
            if ($null -eq $current) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'still present'
                _Record-Result $resourceName 'non_compliant' $false 'present' $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                [Environment]::SetEnvironmentVariable($Name, $null, $envTarget)
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
