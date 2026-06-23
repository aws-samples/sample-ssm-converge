# =============================================================================
# SSM Converge - Resource Provider: Group (Windows local group)
#
# Manages local groups and membership. For AD groups, use the generic DscResource
# wrapper against ActiveDirectoryDsc/xActiveDirectory.
#
# Usage:
#   Group 'AppOperators' Present -Members 'svc_app','CORP\deployer'
#   Group 'RDP-Users'    Present -MembersToInclude 'CORP\helpdesk'
#   Group 'OldGroup'     Absent
#
# -Members     : declarative; the group's membership is REPLACED with this set.
# -MembersToInclude / -MembersToExclude : additive / subtractive; other members left alone.
# =============================================================================

function LocalGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$Description,
        [string[]]$Members,
        [string[]]$MembersToInclude,
        [string[]]$MembersToExclude
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "group/$Name"

    if (-not (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue)) {
        _Log-Error $resourceName "LocalAccounts module not available"
        _Record-Result $resourceName 'error' $false 'LocalAccounts module missing'
        return
    }

    $existing = Get-LocalGroup -Name $Name -ErrorAction SilentlyContinue

    switch ($State) {
        'Present' {
            # Create group if missing.
            if (-not $existing) {
                $checkMs = (Get-NowMs) - $checkStart
                if (-not (_Should-Apply)) {
                    _Log-Drift $resourceName 'missing'
                    _Record-Result $resourceName 'non_compliant' $false 'missing' $checkMs 0
                    return
                }
                $applyStart = Get-NowMs
                try {
                    $params = @{ Name = $Name; ErrorAction = 'Stop' }
                    if ($Description) { $params['Description'] = $Description }
                    New-LocalGroup @params | Out-Null
                    $existing = Get-LocalGroup -Name $Name
                } catch {
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Error $resourceName $_.Exception.Message
                    _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
                    return
                }
            }

            # Compare membership.
            $currentMembers = @(Get-LocalGroupMember -Name $Name -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name })

            $toAdd    = @()
            $toRemove = @()

            if ($PSBoundParameters.ContainsKey('Members')) {
                $want = @($Members | ForEach-Object { $_ })
                $toAdd    = @($want          | Where-Object { $_ -notin $currentMembers })
                $toRemove = @($currentMembers | Where-Object { $_ -notin $want })
            } else {
                if ($MembersToInclude) {
                    $toAdd = @($MembersToInclude | Where-Object { $_ -notin $currentMembers })
                }
                if ($MembersToExclude) {
                    $toRemove = @($MembersToExclude | Where-Object { $_ -in $currentMembers })
                }
            }

            $checkMs = (Get-NowMs) - $checkStart

            if ($toAdd.Count -eq 0 -and $toRemove.Count -eq 0) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }

            if (-not (_Should-Apply)) {
                $why = "add: $($toAdd -join ',') ; remove: $($toRemove -join ',')"
                _Log-Drift $resourceName $why
                _Record-Result $resourceName 'non_compliant' $false $why $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            $applyErr = $null
            foreach ($m in $toAdd)    {
                try { Add-LocalGroupMember    -Name $Name -Member $m -ErrorAction Stop } catch { $applyErr = $_.Exception.Message }
            }
            foreach ($m in $toRemove) {
                try { Remove-LocalGroupMember -Name $Name -Member $m -ErrorAction Stop } catch { $applyErr = $_.Exception.Message }
            }
            $applyMs = (Get-NowMs) - $applyStart

            if ($applyErr) {
                _Log-Error $resourceName $applyErr
                _Record-Result $resourceName 'error' $false $applyErr $checkMs $applyMs
            } else {
                $summary = "members: +$($toAdd.Count) -$($toRemove.Count)"
                _Log-Changed $resourceName $summary
                _Record-Result $resourceName 'compliant' $true $summary $checkMs $applyMs
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
                Remove-LocalGroup -Name $Name -ErrorAction Stop
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
