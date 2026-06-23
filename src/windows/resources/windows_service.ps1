# ===============================================================================
# SSM Converge - Resource Provider: WindowsService
#
# Usage:
#   WindowsService 'W3SVC' Running -StartupType Automatic
#   WindowsService 'Spooler' Stopped -StartupType Disabled
#   WindowsService 'W3SVC' Restarted
# ===============================================================================

function WindowsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1)][ValidateSet('Running','Stopped','Restarted')][string]$State,
        [ValidateSet('Automatic','Manual','Disabled','AutomaticDelayedStart','')][string]$StartupType = '',
        [string]$Notify
    )

    if (_Is-DestroyMode) {
        $State = _Flip-State $State
        if ($StartupType -eq 'Automatic' -or $StartupType -eq 'AutomaticDelayedStart') { $StartupType = 'Disabled' }
        elseif ($StartupType -eq 'Disabled') { $StartupType = 'Manual' }
    }

    $checkStart   = Get-NowMs
    $resourceName = "service/$Name"

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        $checkMs = (Get-NowMs) - $checkStart
        _Log-Error $resourceName 'service not found on this host'
        _Record-Result $resourceName 'error' $false 'service not found' $checkMs 0
        return
    }

    $checkMs = (Get-NowMs) - $checkStart

    # Restart is always an apply.
    if ($State -eq 'Restarted') {
        if (-not (_Should-Apply)) {
            _Log-Drift $resourceName 'restart requested (audit mode)'
            _Record-Result $resourceName 'non_compliant' $false 'restart pending' $checkMs 0
            return
        }
        $applyStart = Get-NowMs
        try {
            Restart-Service -Name $Name -Force -ErrorAction Stop
            $applyMs = (Get-NowMs) - $applyStart
            _Log-Changed $resourceName 'restarted'
            _Record-Result $resourceName 'compliant' $true 'restarted' $checkMs $applyMs
        } catch {
            $applyMs = (Get-NowMs) - $applyStart
            _Log-Error $resourceName $_.Exception.Message
            _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
        }
        return
    }

    $isRunning = ($svc.Status -eq 'Running')
    $currentStartupType = (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue).StartMode

    # CIM StartMode values: 'Auto' (=Automatic), 'Manual', 'Disabled', and
    # 'Auto' with DelayedAutoStart registry flag means AutomaticDelayedStart.
    # Normalise to our four values.
    $currentStartupNorm = switch ($currentStartupType) {
        'Auto'     { 'Automatic' }
        'Manual'   { 'Manual' }
        'Disabled' { 'Disabled' }
        default    { $currentStartupType }
    }

    $compliant = $true
    $reasons   = [System.Collections.ArrayList]::new()

    if ($State -eq 'Running'  -and -not $isRunning) { $compliant=$false; $null=$reasons.Add('not running') }
    if ($State -eq 'Stopped'  -and     $isRunning)  { $compliant=$false; $null=$reasons.Add('running (should be stopped)') }
    if ($StartupType -and $StartupType -ne $currentStartupNorm) {
        $compliant = $false
        $null = $reasons.Add("startup is $currentStartupNorm, want $StartupType")
    }

    if ($compliant) {
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
        if ($StartupType) {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
        if ($State -eq 'Running') { Start-Service -Name $Name -ErrorAction Stop }
        if ($State -eq 'Stopped') { Stop-Service  -Name $Name -Force -ErrorAction Stop }

        # Verify.
        Start-Sleep -Milliseconds 500
        $svc = Get-Service -Name $Name
        $nowRunning = ($svc.Status -eq 'Running')

        $verifyOk = $true
        if ($State -eq 'Running' -and -not $nowRunning) { $verifyOk = $false }
        if ($State -eq 'Stopped' -and     $nowRunning)  { $verifyOk = $false }

        $applyMs = (Get-NowMs) - $applyStart
        $why = $reasons -join ', '

        if ($verifyOk) {
            _Log-Changed $resourceName "converged ($why)"
            _Record-Result $resourceName 'compliant' $true "converged: $why" $checkMs $applyMs
            if ($Notify) { _Notify-Handler $Notify }
        } else {
            _Log-Error $resourceName "failed to converge ($why)"
            _Record-Result $resourceName 'error' $false "apply failed: $why" $checkMs $applyMs
        }
    } catch {
        $applyMs = (Get-NowMs) - $applyStart
        _Log-Error $resourceName $_.Exception.Message
        _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
    }
}
