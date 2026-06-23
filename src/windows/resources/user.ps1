# =============================================================================
# SSM Converge - Resource Provider: User (Windows local user)
#
# Manages local user accounts via the LocalAccounts module (pre-installed on
# Windows 10/Server 2016+). For Active Directory users, use the generic
# DscResource wrapper against ActiveDirectoryDsc/xActiveDirectory.
#
# Usage:
#   User 'svc_app' Present -Password (Read-Host -AsSecureString)
#   User 'svc_app' Present -FullName 'App Service' -Description 'Runs MyApp' -PasswordNeverExpires
#   User 'olduser' Absent
# =============================================================================

function LocalUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [System.Security.SecureString]$Password,
        [string]$FullName,
        [string]$Description,
        [switch]$PasswordNeverExpires,
        [switch]$UserMayNotChangePassword,
        [switch]$Disabled
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart   = Get-NowMs
    $resourceName = "user/$Name"

    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) {
        _Log-Error $resourceName "LocalAccounts module not available"
        _Record-Result $resourceName 'error' $false 'LocalAccounts module missing'
        return
    }

    $existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue

    switch ($State) {
        'Present' {
            if ($existing) {
                $reasons = [System.Collections.ArrayList]::new()
                if ($FullName            -and $existing.FullName            -ne $FullName)            { $null=$reasons.Add("full name: $($existing.FullName) -> $FullName") }
                if ($Description         -and $existing.Description         -ne $Description)         { $null=$reasons.Add("description changed") }
                if ($PasswordNeverExpires.IsPresent -and -not $existing.PasswordNeverExpires)         { $null=$reasons.Add("PasswordNeverExpires false") }
                if (-not $PasswordNeverExpires.IsPresent -and $existing.PasswordNeverExpires -and $PSBoundParameters.ContainsKey('PasswordNeverExpires')) {
                    $null=$reasons.Add("PasswordNeverExpires true")
                }
                if ($Disabled.IsPresent  -and $existing.Enabled)             { $null=$reasons.Add("account is enabled (should be disabled)") }
                if (-not $Disabled.IsPresent -and -not $existing.Enabled -and $PSBoundParameters.ContainsKey('Disabled')) {
                    $null=$reasons.Add("account is disabled")
                }

                $checkMs = (Get-NowMs) - $checkStart
                if ($reasons.Count -eq 0) {
                    _Log-Ok $resourceName
                    _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                    return
                }
                if (-not (_Should-Apply)) {
                    $why = $reasons -join ', '
                    _Log-Drift $resourceName $why
                    _Record-Result $resourceName 'non_compliant' $false $why $checkMs 0
                    return
                }

                $applyStart = Get-NowMs
                try {
                    $params = @{ Name = $Name; ErrorAction = 'Stop' }
                    if ($FullName)           { $params['FullName']             = $FullName }
                    if ($Description)        { $params['Description']          = $Description }
                    if ($PSBoundParameters.ContainsKey('PasswordNeverExpires')) {
                        $params['PasswordNeverExpires'] = $PasswordNeverExpires.IsPresent
                    }
                    if ($PSBoundParameters.ContainsKey('UserMayNotChangePassword')) {
                        $params['UserMayNotChangePassword'] = $UserMayNotChangePassword.IsPresent
                    }
                    Set-LocalUser @params
                    if ($PSBoundParameters.ContainsKey('Disabled')) {
                        if ($Disabled) { Disable-LocalUser -Name $Name -ErrorAction Stop }
                        else           { Enable-LocalUser  -Name $Name -ErrorAction Stop }
                    }
                    $applyMs = (Get-NowMs) - $applyStart
                    $why = $reasons -join ', '
                    _Log-Changed $resourceName "modified ($why)"
                    _Record-Result $resourceName 'compliant' $true "modified: $why" $checkMs $applyMs
                } catch {
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Error $resourceName $_.Exception.Message
                    _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
                }
                return
            }

            # Doesn't exist - create.
            $checkMs = (Get-NowMs) - $checkStart

            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'missing'
                _Record-Result $resourceName 'non_compliant' $false 'missing' $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                $params = @{ Name = $Name; ErrorAction = 'Stop' }
                if ($Password)         { $params['Password']           = $Password }
                else                   { $params['NoPassword']         = $true }
                if ($FullName)         { $params['FullName']           = $FullName }
                if ($Description)      { $params['Description']        = $Description }
                if ($PasswordNeverExpires) { $params['PasswordNeverExpires'] = $true }
                if ($UserMayNotChangePassword) { $params['UserMayNotChangePassword'] = $true }
                New-LocalUser @params | Out-Null
                if ($Disabled) { Disable-LocalUser -Name $Name -ErrorAction SilentlyContinue }

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
                Remove-LocalUser -Name $Name -ErrorAction Stop
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
