# ===============================================================================
# SSM Converge - Resource Provider: Execute (Windows)
#
# Run a shell command (PowerShell or external EXE). Idempotency comes from one
# of three guards: the command is only invoked when its guard says it needs to
# run. Without a guard, the command runs on every enforce/destroy pass.
#
# Guards:
#   -Creates 'C:\Path\To\Marker'      - skip if path exists
#   -OnlyIf  'powershell expression'  - run only if the expression is $true / rc 0
#   -NotIf   'powershell expression'  - skip if the expression is $true / rc 0
#
# Optional knobs:
#   -Cwd       'C:\some\dir'
#   -EnvVars   @{ KEY = 'value' }
#   -TimeoutSec 600
#   -Interpreter 'pwsh' | 'powershell' | 'cmd'   (default: 'powershell')
#
# Usage:
#   # Install an MSI; idempotent via -Creates.
#   Execute 'install-vendor-msi' `
#       -Command 'msiexec /i C:\temp\vendor.msi /qn /norestart' `
#       -Creates 'C:\Program Files\Vendor\app.exe' `
#       -Interpreter 'cmd'
#
#   # Run a one-shot setup unless it has already completed.
#   Execute 'first-boot-init' `
#       -Command 'C:\scripts\Initialize-Server.ps1' `
#       -NotIf   'Test-Path C:\ProgramData\app\.initialized'
#
#   # Pair with File for download + install.
#   File    'C:\temp\agent.msi' Present -Source 'https://vendor.com/agent.msi' -Checksum 'sha256:...'
#   Execute 'install-vendor-agent' `
#       -Command 'msiexec /i C:\temp\agent.msi /qn /norestart' `
#       -NotIf   '(Get-Package -Name "Vendor Agent" -ErrorAction SilentlyContinue) -ne $null' `
#       -Interpreter 'cmd'
# ===============================================================================

function Execute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter()][ValidateSet('Run','Once','Present')][string]$State = 'Run',
        [Parameter(Mandatory)][string]$Command,
        [string]$Creates,
        [string]$OnlyIf,
        [string]$NotIf,
        [string]$Cwd,
        [hashtable]$EnvVars,
        [int]$TimeoutSec = 600,
        [ValidateSet('powershell','pwsh','cmd')]
        [string]$Interpreter = 'powershell',
        [string]$Notify
    )

    $checkStart   = Get-NowMs
    $resourceName = "execute/$Name"

    # In destroy mode, treat as a no-op. Most installer commands have no
    # one-line undo; users wire up explicit Uninstall flows when needed.
    if (_Is-DestroyMode) {
        $checkMs = (Get-NowMs) - $checkStart
        _Log-Ok "$resourceName (skipped in destroy mode)"
        _Record-Result $resourceName 'compliant' $false 'skipped in destroy mode' $checkMs 0
        return
    }

    # ---- Decide whether to run ----
    $needsRun   = $true
    $skipReason = ''

    if ($Creates -and (Test-Path -LiteralPath $Creates)) {
        $needsRun   = $false
        $skipReason = "$Creates exists"
    }

    if ($needsRun -and $NotIf) {
        try {
            $r = Invoke-Expression $NotIf
            if ($r -or ($LASTEXITCODE -eq 0 -and $null -ne $LASTEXITCODE)) {
                $needsRun   = $false
                $skipReason = 'not_if succeeded'
            }
        } catch { }
    }

    if ($needsRun -and $OnlyIf) {
        $shouldRun = $false
        try {
            $r = Invoke-Expression $OnlyIf
            $shouldRun = [bool]$r -or ($LASTEXITCODE -eq 0 -and $null -ne $LASTEXITCODE)
        } catch { $shouldRun = $false }
        if (-not $shouldRun) {
            $needsRun   = $false
            $skipReason = 'only_if failed'
        }
    }

    $checkMs = (Get-NowMs) - $checkStart

    if (-not $needsRun) {
        _Log-Ok $resourceName
        _Record-Result $resourceName 'compliant' $false $skipReason $checkMs 0
        return
    }

    if (-not (_Should-Apply)) {
        _Log-Drift $resourceName 'would run'
        _Record-Result $resourceName 'non_compliant' $false 'would run' $checkMs 0
        return
    }

    # ---- Build invocation ----
    $applyStart = Get-NowMs

    # Prepare a transient working dir change + env injection so the user's
    # command runs in a predictable shell context.
    $prelude = ''
    if ($Cwd) {
        $prelude += "Set-Location -LiteralPath '$($Cwd -replace "'","''")'`n"
    }
    if ($EnvVars) {
        foreach ($k in $EnvVars.Keys) {
            $v = [string]$EnvVars[$k]
            $prelude += "`$env:$k = '$($v -replace "'","''")'`n"
        }
    }

    $rc           = 0
    $cmdOutput    = ''
    $exe          = ''
    $exeArgs      = @()

    switch ($Interpreter) {
        'powershell' {
            $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
            if (-not $exe) { $exe = 'powershell.exe' }
            $script  = "$prelude$Command"
            $exeArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command', $script)
        }
        'pwsh' {
            $exe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
            if (-not $exe) {
                _Log-Error $resourceName 'pwsh.exe not found on PATH'
                _Record-Result $resourceName 'error' $false 'pwsh missing' $checkMs 0
                return
            }
            $script  = "$prelude$Command"
            $exeArgs = @('-NoProfile','-NonInteractive','-Command', $script)
        }
        'cmd' {
            # cmd.exe ignores PowerShell prelude; if Cwd/EnvVars supplied we
            # apply them in the parent process instead.
            if ($Cwd) {
                Push-Location -LiteralPath $Cwd
            }
            if ($EnvVars) {
                foreach ($k in $EnvVars.Keys) {
                    [Environment]::SetEnvironmentVariable($k, [string]$EnvVars[$k], 'Process')
                }
            }
            $exe     = (Get-Command cmd.exe -ErrorAction SilentlyContinue).Source
            if (-not $exe) { $exe = 'cmd.exe' }
            $exeArgs = @('/c', $Command)
        }
    }

    try {
        $tmpOut = New-TemporaryFile
        $tmpErr = New-TemporaryFile

        # Use the call operator (&) so we can rely on $LASTEXITCODE. Start-Process
        # has known quirks where $proc.ExitCode is not always populated after
        # WaitForExit on Windows PowerShell 5.1.
        if ($TimeoutSec -gt 0) {
            $job = Start-Job -ScriptBlock {
                param($exe, $exeArgs, $outFile, $errFile)
                & $exe @exeArgs > $outFile 2> $errFile
                $LASTEXITCODE
            } -ArgumentList $exe, $exeArgs, $tmpOut.FullName, $tmpErr.FullName

            if (Wait-Job -Job $job -Timeout $TimeoutSec) {
                $rc = (Receive-Job -Job $job)
                if ($null -eq $rc) { $rc = 0 }
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            } else {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                $rc = -1
                $cmdOutput = "TIMEOUT after $TimeoutSec seconds"
            }
        } else {
            & $exe @exeArgs > $tmpOut.FullName 2> $tmpErr.FullName
            $rc = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        }

        if ($rc -ne -1) {
            $cmdOutput = (Get-Content $tmpOut.FullName -Raw -ErrorAction SilentlyContinue) +
                         (Get-Content $tmpErr.FullName -Raw -ErrorAction SilentlyContinue)
        }

        Remove-Item -LiteralPath $tmpOut.FullName,$tmpErr.FullName -Force -ErrorAction SilentlyContinue
    } catch {
        $rc        = 1
        $cmdOutput = $_.Exception.Message
    } finally {
        if ($Interpreter -eq 'cmd' -and $Cwd) { Pop-Location }
    }

    $applyMs = (Get-NowMs) - $applyStart

    if ($rc -eq 0) {
        _Log-Changed $resourceName 'executed'
        _Record-Result $resourceName 'compliant' $true 'executed' $checkMs $applyMs
        if ($Notify) { _Notify-Handler $Notify }
        return
    }

    # On failure, surface a single-line snippet of the captured output. Full
    # output goes to the debug log. Last non-empty line is usually the most
    # useful summary (final stack frame, last warning).
    $clean   = if ($cmdOutput) { $cmdOutput.Trim() } else { '' }
    $snippet = ''
    if ($clean) {
        $lines = $clean -split "`r?`n" | Where-Object { $_.Trim() }
        if ($lines.Count -gt 0) {
            $snippet = ($lines[-1]).Trim()
        }
    }
    if (-not $snippet -and $clean) {
        $snippet = $clean.Substring(0, [Math]::Min(200, $clean.Length))
    }
    # Trim to keep log lines readable (~200 chars).
    if ($snippet.Length -gt 200) { $snippet = $snippet.Substring(0, 200) }

    # Trim to keep debug log entries manageable.
    $debugSnippet = if ($cmdOutput) { $cmdOutput.Substring(0, [Math]::Min(2000, $cmdOutput.Length)) } else { '' }
    _Debug "execute/$Name failed (rc=$rc): $debugSnippet"
    $detail = if ($snippet) { "exit $rc`: $snippet" } else { "exit $rc" }
    _Log-Error $resourceName $detail
    _Record-Result $resourceName 'error' $false $detail $checkMs $applyMs
}
