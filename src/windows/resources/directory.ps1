# ===============================================================================
# SSM Converge - Resource Provider: Directory (Windows)
#
# Usage:
#   Directory 'C:\inetpub\wwwroot\app' Present
#   Directory 'C:\temp\old-cache'      Absent
# ===============================================================================

function Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Path,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [switch]$Recursive
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "directory$Path"

    switch ($State) {
        'Present' {
            $checkMs = (Get-NowMs) - $checkStart

            if (Test-Path -LiteralPath $Path -PathType Container) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }

            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'missing'
                _Record-Result $resourceName 'non_compliant' $false 'missing' $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                $null = New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName 'created'
                _Record-Result $resourceName 'compliant' $true 'created' $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }

        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart

            if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
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
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
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
