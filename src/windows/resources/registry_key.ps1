# ===============================================================================
# SSM Converge - Resource Provider: RegistryKey
#
# Manages a single registry value or key.
#
# Usage:
#   # Ensure a value exists with a specific data:
#   RegistryKey 'HKLM:\SOFTWARE\MyCompany\App' Present -ValueName 'Version' -ValueData '1.2.3' -ValueType 'String'
#
#   # Ensure a key exists (no specific value):
#   RegistryKey 'HKLM:\SOFTWARE\MyCompany\App' Present
#
#   # Remove a value:
#   RegistryKey 'HKLM:\SOFTWARE\MyCompany\App' Absent -ValueName 'LegacyFlag'
#
#   # Remove the whole key:
#   RegistryKey 'HKLM:\SOFTWARE\MyCompany\LegacyApp' Absent
#
# ValueType defaults to String. Valid: String, DWord, QWord, Binary, MultiString, ExpandString.
# ===============================================================================

function RegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Path,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$ValueName,
        $ValueData,
        [ValidateSet('String','DWord','QWord','Binary','MultiString','ExpandString')][string]$ValueType = 'String'
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart = Get-NowMs

    $label = if ($ValueName) { "registry[$Path\$ValueName]" } else { "registry[$Path]" }

    switch ($State) {
        'Present' {
            $keyExists   = Test-Path -LiteralPath $Path
            $valueMatches = $true
            $reasons = [System.Collections.ArrayList]::new()

            if (-not $keyExists) {
                $null = $reasons.Add('key missing')
                $valueMatches = $false
            } elseif ($ValueName) {
                try {
                    $current = (Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop).$ValueName
                    if ($null -eq $current) {
                        $valueMatches = $false
                        $null = $reasons.Add('value not set')
                    } elseif ("$current" -ne "$ValueData") {
                        $valueMatches = $false
                        $null = $reasons.Add("value is $current, want $ValueData")
                    }
                } catch {
                    $valueMatches = $false
                    $null = $reasons.Add('value not set')
                }
            }

            $checkMs = (Get-NowMs) - $checkStart

            if ($keyExists -and $valueMatches) {
                _Log-Ok $label
                _Record-Result $label 'compliant' $false '' $checkMs 0
                return
            }

            if (-not (_Should-Apply)) {
                $why = $reasons -join ', '
                _Log-Drift $label $why
                _Record-Result $label 'non_compliant' $false $why $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                if (-not $keyExists) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
                if ($ValueName) {
                    $null = New-ItemProperty -LiteralPath $Path -Name $ValueName -Value $ValueData -PropertyType $ValueType -Force -ErrorAction Stop
                }
                $applyMs = (Get-NowMs) - $applyStart
                $why = $reasons -join ', '
                _Log-Changed $label "converged ($why)"
                _Record-Result $label 'compliant' $true "converged: $why" $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $label $_.Exception.Message
                _Record-Result $label 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }

        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart

            if (-not (Test-Path -LiteralPath $Path)) {
                _Log-Ok $label
                _Record-Result $label 'compliant' $false '' $checkMs 0
                return
            }

            if ($ValueName) {
                $valuePresent = $null -ne (Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction SilentlyContinue)
                if (-not $valuePresent) {
                    _Log-Ok $label
                    _Record-Result $label 'compliant' $false '' $checkMs 0
                    return
                }

                if (-not (_Should-Apply)) {
                    _Log-Drift $label 'value exists (should be absent)'
                    _Record-Result $label 'non_compliant' $false 'value exists' $checkMs 0
                    return
                }

                $applyStart = Get-NowMs
                try {
                    Remove-ItemProperty -LiteralPath $Path -Name $ValueName -Force -ErrorAction Stop
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Changed $label 'value removed'
                    _Record-Result $label 'compliant' $true 'value removed' $checkMs $applyMs
                } catch {
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Error $label $_.Exception.Message
                    _Record-Result $label 'error' $false $_.Exception.Message $checkMs $applyMs
                }
            } else {
                # Remove whole key.
                if (-not (_Should-Apply)) {
                    _Log-Drift $label 'key exists (should be absent)'
                    _Record-Result $label 'non_compliant' $false 'key exists' $checkMs 0
                    return
                }
                $applyStart = Get-NowMs
                try {
                    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Changed $label 'key removed'
                    _Record-Result $label 'compliant' $true 'key removed' $checkMs $applyMs
                } catch {
                    $applyMs = (Get-NowMs) - $applyStart
                    _Log-Error $label $_.Exception.Message
                    _Record-Result $label 'error' $false $_.Exception.Message $checkMs $applyMs
                }
            }
        }
    }
}
