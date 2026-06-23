# =============================================================================
# SSM Converge - Resource Provider: HostEntry (Windows)
#
# Manages entries in C:\Windows\System32\drivers\etc\hosts
#
# Usage:
#   HostEntry '10.0.1.5' Present -Hostname 'myapp.internal'
#   HostEntry '10.0.1.5' Absent
# =============================================================================

function HostEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$IpAddress,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$Hostname,
        [string]$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "host_entry[$IpAddress $Hostname]"

    if (-not (Test-Path $HostsFile)) {
        $checkMs = (Get-NowMs) - $checkStart
        if ($State -eq 'Absent') {
            _Log-Ok $resourceName
            _Record-Result $resourceName 'compliant' $false '' $checkMs 0
            return
        }
        if (-not (_Should-Apply)) {
            _Log-Drift $resourceName 'hosts file missing'
            _Record-Result $resourceName 'non_compliant' $false 'hosts file missing' $checkMs 0
            return
        }
        $null = New-Item -ItemType File -Force -Path $HostsFile
    }

    $existing  = Get-Content $HostsFile -ErrorAction SilentlyContinue
    $entryLine = "$IpAddress`t$Hostname"
    $ipMatch   = $existing | Where-Object { $_ -match "^\s*$([regex]::Escape($IpAddress))\s" }

    switch ($State) {
        'Present' {
            $exactMatch = $existing | Where-Object { $_ -eq $entryLine }
            $checkMs = (Get-NowMs) - $checkStart
            if ($exactMatch -and @($ipMatch).Count -eq 1) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'missing or stale'
                _Record-Result $resourceName 'non_compliant' $false 'missing' $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                # Strip any existing lines for this IP, then append the canonical one.
                $cleaned = $existing | Where-Object { $_ -notmatch "^\s*$([regex]::Escape($IpAddress))\s" }
                $cleaned += $entryLine
                Set-Content -Path $HostsFile -Value $cleaned -Encoding ASCII -ErrorAction Stop
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName 'added/updated'
                _Record-Result $resourceName 'compliant' $true 'added' $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }
        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart
            if (-not $ipMatch) {
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
                $cleaned = $existing | Where-Object { $_ -notmatch "^\s*$([regex]::Escape($IpAddress))\s" }
                Set-Content -Path $HostsFile -Value $cleaned -Encoding ASCII -ErrorAction Stop
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
