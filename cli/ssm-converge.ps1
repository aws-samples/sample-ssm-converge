#Requires -Version 5.1
<#
.SYNOPSIS
  SSM Converge CLI (Windows / PowerShell).

.DESCRIPTION
  Query local compliance state, history, and drift events, and execute
  configurations in enforce / audit / destroy / comply modes.

.EXAMPLE
  ssm-converge status
  ssm-converge history 5
  ssm-converge run  C:\configs\webserver.ps1
  ssm-converge check C:\configs\webserver.ps1
  ssm-converge comply C:\configs\webserver.ps1
  ssm-converge destroy C:\configs\webserver.ps1
  ssm-converge --version
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'help',
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]$Rest
)

$SsmConvergeVersion = '0.1.2'
$DscLocalDir = if ($env:DSC_LOCAL_DIR) { $env:DSC_LOCAL_DIR } else { 'C:\ProgramData\ssm-converge' }

function _Require-Config {
    param([string]$Action,[string]$Path)
    if (-not $Path) {
        Write-Host "Usage: ssm-converge $Action <config.ps1>"
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host -ForegroundColor Red "Error: Configuration not found: $Path"
        exit 1
    }
}

function Cmd-Status {
    $report = Join-Path $DscLocalDir 'latest.json'
    if (-not (Test-Path $report)) {
        Write-Host -ForegroundColor Yellow 'No compliance data yet. Run a configuration first.'
        return
    }
    $r = Get-Content $report -Raw | ConvertFrom-Json
    $s = $r.summary
    Write-Host ''
    Write-Host '==================================================='
    Write-Host '  SSM Converge - Compliance Status'
    Write-Host '==================================================='
    Write-Host "  Last Run:   $($r.timestamp)"
    Write-Host "  Profile:    $($r.profile)"
    Write-Host "  Mode:       $($r.mode)"
    Write-Host "  Run ID:     $($r.run_id)"
    Write-Host ''
    Write-Host "  Resources:  $($s.total)"
    Write-Host "  Compliant:  $($s.compliant)/$($s.total) ($($s.compliance_pct)%)"
    if ($s.non_compliant) { Write-Host "  Drift:      $($s.non_compliant)" }
    if ($s.errors)        { Write-Host "  Errors:     $($s.errors)" }
    if ($s.changed)       { Write-Host "  Changed:    $($s.changed)" }
    Write-Host ''
    foreach ($res in $r.resources) {
        $icon = switch ($res.status) {
            'compliant'     { if ($res.changed) { '[CHANGED]' } else { '[OK]' } }
            'non_compliant' { '[FAIL]' }
            'error'         { '[ERROR]' }
            default         { '[?]' }
        }
        $suffix = if ($res.detail) { " - $($res.detail)" } else { '' }
        Write-Host ("  {0,-10} {1}{2}" -f $icon, $res.resource, $suffix)
    }
    Write-Host ''
    Write-Host '==================================================='
}

function Cmd-History {
    param([int]$Count = 10)
    $dir = Join-Path $DscLocalDir 'history'
    if (-not (Test-Path $dir)) {
        Write-Host -ForegroundColor Yellow 'No history available.'
        return
    }
    $files = Get-ChildItem -Path $dir -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First $Count
    if (-not $files) { Write-Host -ForegroundColor Yellow 'No history available.'; return }

    Write-Host ''
    Write-Host "  Recent Runs (last $Count)"
    Write-Host '  -------------------------------------------------------------'
    Write-Host ('  {0,-22} {1,-8} {2,-12} {3,-8} {4}' -f 'TIMESTAMP','MODE','PROFILE','SCORE','CHANGED')
    Write-Host '  -------------------------------------------------------------'
    foreach ($f in $files) {
        try {
            $r = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $s = $r.summary
            $ts = if ($r.timestamp) { $r.timestamp.Substring(0,[math]::Min(19,$r.timestamp.Length)) } else { 'unknown' }
            $score = "$($s.compliant)/$($s.total)"
            Write-Host ('  {0,-22} {1,-8} {2,-12} {3,-8} {4}' -f $ts, $r.mode, $r.profile.Substring(0,[math]::Min(12,$r.profile.Length)), $score, $s.changed)
        } catch {}
    }
    Write-Host ''
}

function Cmd-Drift {
    $driftLog = Join-Path $DscLocalDir 'drift.log'
    if (-not (Test-Path $driftLog)) {
        Write-Host -ForegroundColor Green 'No drift recorded. All clear.'
        return
    }
    Write-Host ''
    Write-Host '  Recent Drift Events'
    Write-Host '  -------------------------------------------------------------'
    Get-Content $driftLog | Select-Object -Last 20 | ForEach-Object { Write-Host -ForegroundColor Red "  X $_" }
    Write-Host ''
}

function Cmd-Export {
    $report = Join-Path $DscLocalDir 'latest.json'
    if (-not (Test-Path $report)) {
        '{"error": "No compliance data available"}' | Write-Output
        exit 1
    }
    $r = Get-Content $report -Raw | ConvertFrom-Json
    $inspec = [pscustomobject]@{
        platform = @{ name = 'aws-ssm-converge'; release = $SsmConvergeVersion }
        profiles = @(
            [pscustomobject]@{
                name     = $r.profile
                title    = "SSM Converge: $($r.profile)"
                controls = @($r.resources | ForEach-Object {
                    [pscustomobject]@{
                        id      = ($_.resource -replace '[\\/\s\[\]:]', '_')
                        title   = $_.resource
                        desc    = $_.detail
                        impact  = 0.7
                        results = @(@{
                            status    = if ($_.status -eq 'compliant') { 'passed' } else { 'failed' }
                            code_desc = $_.detail
                            run_time  = ($_.check_duration_ms + $_.apply_duration_ms) / 1000.0
                        })
                    }
                })
            }
        )
        statistics = @{ duration = (($r.resources | Measure-Object -Property check_duration_ms,apply_duration_ms -Sum).Sum / 1000.0) }
        version    = $SsmConvergeVersion
    }
    $inspec | ConvertTo-Json -Depth 10
}

function Cmd-Run     { param([string]$Path) _Require-Config 'run'     $Path; $env:DSC_MODE='enforce'; & $Path }
function Cmd-Check   { param([string]$Path) _Require-Config 'check'   $Path; $env:DSC_MODE='audit';   & $Path }
function Cmd-Destroy { param([string]$Path) _Require-Config 'destroy' $Path; $env:DSC_MODE='destroy'; & $Path }
function Cmd-Comply  { param([string]$Path) _Require-Config 'comply'  $Path; $env:DSC_MODE='audit'; $env:DSC_REPORT='full'; & $Path }

function Cmd-Version { "ssm-converge v$SsmConvergeVersion" }

function Cmd-Help {
    @'

SSM Converge - Desired state configuration for AWS Systems Manager

Usage: ssm-converge <command> [options]

Commands:
  status            Show latest compliance state
  history [n]       Show last N runs (default: 10)
  drift             Show recent drift events
  export            Export latest report as InSpec-compatible JSON
  run <config>      Run a configuration in enforce mode
  check <config>    Run a configuration in audit mode (no changes)
  comply <config>   Run compliance checks and generate full report
  destroy <config>  Tear down resources defined in a configuration
  version           Show version (also: --version, -v)
  help              Show this help (also: --help, -h)

Examples:
  ssm-converge status
  ssm-converge history 5
  ssm-converge check C:\configs\webserver.ps1
  ssm-converge run   C:\configs\webserver.ps1

'@
}

switch ($Command.ToLower()) {
    'status'   { Cmd-Status }
    'history'  { Cmd-History -Count $(if ($Rest) { [int]$Rest[0] } else { 10 }) }
    'drift'    { Cmd-Drift }
    'export'   { Cmd-Export }
    'run'      { Cmd-Run     -Path $(if ($Rest) { $Rest[0] } else { $null }) }
    'check'    { Cmd-Check   -Path $(if ($Rest) { $Rest[0] } else { $null }) }
    'comply'   { Cmd-Comply  -Path $(if ($Rest) { $Rest[0] } else { $null }) }
    'destroy'  { Cmd-Destroy -Path $(if ($Rest) { $Rest[0] } else { $null }) }
    'version'  { Cmd-Version }
    '--version'{ Cmd-Version }
    '-v'       { Cmd-Version }
    'help'     { Cmd-Help }
    '--help'   { Cmd-Help }
    '-h'       { Cmd-Help }
    default {
        Write-Host -ForegroundColor Red "Unknown command: $Command"
        Cmd-Help
        exit 1
    }
}
