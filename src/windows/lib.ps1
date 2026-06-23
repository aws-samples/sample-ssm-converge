# ===============================================================================
# SSM Converge - Desired State Configuration Library for AWS Systems Manager
# Windows / PowerShell port.
#
# Version: 0.1.0
# License: Apache 2.0
#
# Usage:
#   . C:\ProgramData\ssm-converge\lib.ps1
#
#   Package 'nginx' Installed
#   File 'C:\inetpub\wwwroot\web.config' Present -Source 's3://bucket/web.config'
#   WindowsService 'W3SVC' Running -StartupType Automatic
#
#   Report-Compliance
#   Get-ReportJson | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname).json"
# ===============================================================================

Set-StrictMode -Version 2
# Don't stop the whole run on a single resource failure - we record errors
# and keep going, same as the bash version.
$ErrorActionPreference = 'Continue'

# --- Configuration ------------------------------------------------------------
# All config vars are overridable via the environment.

$script:SsmConvergeVersion = '0.1.2'

# Execution mode.
#   enforce  - check state, fix drift, write local report, print summary (default)
#   audit    - check state only (no changes), write local report, print summary
#   destroy  - flip desired state (Present->Absent, Running->Stopped) and fix
$script:DscMode = if ($env:DSC_MODE)    { $env:DSC_MODE }    else { 'enforce' }

# Profile/configuration name - appears in reports.
$script:DscProfile = if ($env:DSC_PROFILE) { $env:DSC_PROFILE } else { 'default' }

# Output style for Report-Compliance.
#   summary - one-line header after the run                           (default)
#   full    - detailed compliance report (used by `ssm-converge comply`)
$script:DscReport = if ($env:DSC_REPORT)  { $env:DSC_REPORT }  else { 'summary' }

# Local on-instance report store.
$script:DscLocalDir = if ($env:DSC_LOCAL_DIR) { $env:DSC_LOCAL_DIR } else { 'C:\ProgramData\ssm-converge' }
$script:DscHistoryRetain = if ($env:DSC_HISTORY_RETAIN) { [int]$env:DSC_HISTORY_RETAIN } else { 100 }

# Verbose per-resource logging.
$script:DscVerbose = -not ($env:DSC_VERBOSE -eq 'false')

# Debug log. Falls back to %TEMP% when the default path isn't writable.
$script:DscLogFile = if ($env:DSC_LOG_FILE) { $env:DSC_LOG_FILE } else { 'C:\ProgramData\ssm-converge\ssm-converge.log' }
try {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $script:DscLogFile -Parent) -ErrorAction Stop
    Add-Content -Path $script:DscLogFile -Value '' -ErrorAction Stop
} catch {
    $script:DscLogFile = Join-Path $env:TEMP 'ssm-converge.log'
}
$script:DscDebug = -not ($env:DSC_DEBUG -eq 'false')

# --- Internal state -----------------------------------------------------------

$script:DscRunId = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$PID"
$script:DscResults = [System.Collections.ArrayList]::new()
$script:DscHandlersTriggered = [System.Collections.Generic.HashSet[string]]::new()
$script:DscHandlerDefs = @{}

# Instance metadata (lazy-loaded).
$script:InstanceId = $null
$script:AccountId  = $null
$script:Region     = $null
$script:ImdsToken  = $null

# Resources may signal that a reboot is required to complete convergence
# (e.g. domain join, Windows feature install, cluster creation).
# Configurations can check `Test-RebootRequired` at the end and decide how
# to handle it - most fleets will schedule it via SSM State Manager rather
# than letting a recipe reboot mid-run.
$script:RebootRequired = $false

function Request-Reboot {
    param([string]$Reason = '')
    $script:RebootRequired = $true
    _Debug "Reboot requested: $Reason"
    _Log "  [REBOOT]  pending - $Reason"
}

function Test-RebootRequired { $script:RebootRequired }

# --- Helpers - millisecond timestamps -----------------------------------------

function Get-NowMs {
    [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

$script:DscStartTime = Get-NowMs

# --- Helpers - metadata (IMDSv2) ----------------------------------------------
# PowerShell lacks a timeout-friendly curl, so we hit IMDS with Invoke-WebRequest
# plus a short -TimeoutSec so offline/non-EC2 hosts don't hang.

function _Get-ImdsToken {
    if ($null -eq $script:ImdsToken) {
        try {
            $script:ImdsToken = (Invoke-RestMethod `
                -Method Put `
                -Uri 'http://169.254.169.254/latest/api/token' `
                -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '300' } `
                -TimeoutSec 2 `
                -ErrorAction Stop)
        } catch {
            $script:ImdsToken = ''
        }
    }
    return $script:ImdsToken
}

function _Imds-Get {
    param([string]$Path)
    $token = _Get-ImdsToken
    $headers = if ($token) { @{ 'X-aws-ec2-metadata-token' = $token } } else { @{} }
    try {
        Invoke-RestMethod -Uri "http://169.254.169.254/$Path" -Headers $headers -TimeoutSec 2 -ErrorAction Stop
    } catch {
        $null
    }
}

function Get-InstanceId {
    if (-not $script:InstanceId) {
        $v = _Imds-Get 'latest/meta-data/instance-id'
        $script:InstanceId = if ($v) { $v } else { 'unknown' }
    }
    return $script:InstanceId
}

function _Imds-Field {
    param([string]$Field)
    try {
        $doc = _Imds-Get 'latest/dynamic/instance-identity/document'
        if ($doc -is [string]) { $doc = $doc | ConvertFrom-Json }
        if ($doc -and $doc.PSObject.Properties.Name -contains $Field) {
            return $doc.$Field
        }
    } catch {}
    return 'unknown'
}

function Get-AccountId {
    if (-not $script:AccountId) { $script:AccountId = _Imds-Field 'accountId' }
    return $script:AccountId
}

function Get-Region {
    if (-not $script:Region) { $script:Region = _Imds-Field 'region' }
    return $script:Region
}

# --- Debug logging ------------------------------------------------------------

function _Debug {
    param([string]$Message)
    if ($script:DscDebug) {
        try {
            $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Add-Content -Path $script:DscLogFile -Value "[$ts] $Message" -ErrorAction SilentlyContinue
        } catch {}
    }
}

_Debug "=== SSM Converge v$($script:SsmConvergeVersion) starting ==="
_Debug "Mode=$($script:DscMode) Profile=$($script:DscProfile)"

# --- Output helpers -----------------------------------------------------------

function _Log         { param([string]$m) if ($script:DscVerbose) { Write-Host $m } }
function _Log-Ok      { param([string]$r) _Log "  [OK]      $r";      _Debug "OK: $r" }
function _Log-Changed { param([string]$r,[string]$d) _Log "  [CHANGED] $r - $d"; _Debug "CHANGED: $r - $d" }
function _Log-Drift   { param([string]$r,[string]$d) _Log "  [DRIFT]   $r - $d"; _Debug "DRIFT: $r - $d" }
function _Log-Error   { param([string]$r,[string]$d) Write-Host -ForegroundColor Red "  [ERROR]   $r - $d"; _Debug "ERROR: $r - $d" }

# --- Mode helpers -------------------------------------------------------------

function _Should-Apply    { $script:DscMode -eq 'enforce' -or $script:DscMode -eq 'destroy' }
function _Is-DestroyMode  { $script:DscMode -eq 'destroy' }

# Flip desired state for destroy mode. Mirrors the bash _flip_state helper.
function _Flip-State {
    param([string]$State)
    switch -regex ($State) {
        '^(?i)(Present|Installed|Mounted)$'             { return 'Absent' }
        '^(?i)(Absent|Uninstalled|Removed|Unmounted)$'  { return 'Present' }
        '^(?i)Running$'   { return 'Stopped' }
        '^(?i)Stopped$'   { return 'Running' }
        '^(?i)Enabled$'   { return 'Disabled' }
        '^(?i)Disabled$'  { return 'Enabled' }
        default           { return $State }
    }
}

# --- Result recording ---------------------------------------------------------

function _Record-Result {
    param(
        [string]$Resource,
        [string]$Status,        # compliant | non_compliant | error
        [bool]$Changed = $false,
        [string]$Detail = '',
        [int64]$CheckMs = 0,
        [int64]$ApplyMs = 0
    )
    $entry = [ordered]@{
        resource          = $Resource
        status            = $Status
        changed           = $Changed
        detail            = $Detail
        timestamp         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        run_id            = $script:DscRunId
        check_duration_ms = $CheckMs
        apply_duration_ms = $ApplyMs
    }
    $null = $script:DscResults.Add([pscustomobject]$entry)
}

function _Notify-Handler {
    param([string]$Name)
    $null = $script:DscHandlersTriggered.Add($Name)
}

# --- Handler registration -----------------------------------------------------

function Handler {
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Mandatory, Position=1, ValueFromRemainingArguments=$true)][string[]]$Command
    )
    $script:DscHandlerDefs[$Name] = ($Command -join ' ')
}

function _Run-Handlers {
    foreach ($name in $script:DscHandlersTriggered) {
        if ($script:DscHandlerDefs.ContainsKey($name)) {
            _Log "  [HANDLER] $name"
            try {
                Invoke-Expression $script:DscHandlerDefs[$name]
            } catch {
                _Log-Error "handler/$name" $_.Exception.Message
            }
        }
    }
}

# --- Source resource providers ------------------------------------------------

$script:SsmConvergeHome = if ($env:SSM_CONVERGE_HOME) { $env:SSM_CONVERGE_HOME } else { $PSScriptRoot }
$resourcesDir = Join-Path $script:SsmConvergeHome 'resources'
_Debug "Loading resources from $resourcesDir"
if (Test-Path $resourcesDir) {
    Get-ChildItem -Path $resourcesDir -Filter '*.ps1' | ForEach-Object {
        _Debug "  Sourcing: $($_.FullName)"
        . $_.FullName
    }
}

# --- Compliance reporting -----------------------------------------------------

function _Build-Report {
    $total       = $script:DscResults.Count
    $compliant     = @($script:DscResults | Where-Object { $_.status -eq 'compliant' }).Count
    $nonCompliant  = @($script:DscResults | Where-Object { $_.status -eq 'non_compliant' }).Count
    $errors        = @($script:DscResults | Where-Object { $_.status -eq 'error' }).Count
    $changed       = @($script:DscResults | Where-Object { $_.changed }).Count
    $compliancePct = if ($total -gt 0) { [math]::Round(($compliant * 100.0 / $total), 1) } else { 0 }

    [pscustomobject][ordered]@{
        schema       = 'ssm-converge/report/v1'
        run_id       = $script:DscRunId
        timestamp    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        instance_id  = (Get-InstanceId)
        account_id   = (Get-AccountId)
        region       = (Get-Region)
        profile      = $script:DscProfile
        mode         = $script:DscMode
        summary      = [ordered]@{
            total           = $total
            compliant       = $compliant
            non_compliant   = $nonCompliant
            errors          = $errors
            changed         = $changed
            compliance_pct  = $compliancePct
        }
        resources    = @($script:DscResults)
    }
}

# Public: return the run as a JSON string. Customer pipes it wherever.
function Get-ReportJson {
    _Build-Report | ConvertTo-Json -Depth 10
}

function _Write-LocalReport {
    param([string]$ReportJson)
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:DscLocalDir 'history') -ErrorAction SilentlyContinue

    Set-Content -Path (Join-Path $script:DscLocalDir 'latest.json') -Value $ReportJson -ErrorAction SilentlyContinue

    $historyFile = Join-Path (Join-Path $script:DscLocalDir 'history') "$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mm-ss')).json"
    Set-Content -Path $historyFile -Value $ReportJson -ErrorAction SilentlyContinue

    # Drift log (one line per non-compliant).
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $driftLog = Join-Path $script:DscLocalDir 'drift.log'
    foreach ($r in $script:DscResults) {
        if ($r.status -eq 'non_compliant') {
            $detail = if ($r.detail) { $r.detail } else { 'drift' }
            Add-Content -Path $driftLog -Value "$ts [$($script:DscProfile)] $($r.resource) - $detail" -ErrorAction SilentlyContinue
        }
    }

    # Rotate history.
    $allHistory = @(Get-ChildItem -Path (Join-Path $script:DscLocalDir 'history') -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($allHistory.Count -gt $script:DscHistoryRetain) {
        $allHistory | Select-Object -Skip $script:DscHistoryRetain | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Report-Compliance {
    _Debug "Report-Compliance called with $($script:DscResults.Count) results"

    if (_Should-Apply) { _Run-Handlers }

    $report = _Build-Report
    $json   = $report | ConvertTo-Json -Depth 10
    _Write-LocalReport $json

    $total         = $report.summary.total
    $compliant     = $report.summary.compliant
    $nonCompliant  = $report.summary.non_compliant
    $errors        = $report.summary.errors
    $changed       = $report.summary.changed

    if ($script:DscReport -eq 'full') {
        Write-Host ''
        Write-Host '==================================================='
        Write-Host '  SSM Converge - Compliance Report'
        Write-Host "  Profile: $($script:DscProfile) | Mode: $($script:DscMode)"
        Write-Host '==================================================='
        Write-Host ''
        Write-Host '  --- Detailed Results -----------------------------'
        foreach ($r in $script:DscResults) {
            $label = 'PASS'
            if     ($r.status -eq 'non_compliant') { $label = 'FAIL' }
            elseif ($r.status -eq 'error')         { $label = 'ERROR' }
            elseif ($r.changed)                    { $label = 'FIXED' }

            $suffix = if ($r.detail) { " ($($r.detail))" } else { '' }
            Write-Host ("  [{0}] {1}{2}" -f $label.PadRight(5), $r.resource, $suffix)
        }
        Write-Host ''
        Write-Host '  --- Summary --------------------------------------'
        Write-Host "  Total Checks:   $total"
        Write-Host "  Compliant:      $compliant"
        Write-Host "  Non-Compliant:  $nonCompliant"
        Write-Host "  Errors:         $errors"
        Write-Host ''
        Write-Host "  Run ID:         $($script:DscRunId)"
        Write-Host "  Local Report:   $(Join-Path $script:DscLocalDir 'latest.json')"
        Write-Host '==================================================='
    } else {
        Write-Host ''
        Write-Host "=== $($total) checks | $($compliant) ok | $($nonCompliant) failed | $($errors) errors | $($changed) changed ==="
    }

    # Exit semantics mirror Linux.
    #   errors present          -> 1
    #   audit mode + drift      -> 2
    #   else                    -> 0
    if ($errors -gt 0) {
        $global:LASTEXITCODE = 1
        return 1
    }
    if ($nonCompliant -gt 0 -and $script:DscMode -eq 'audit') {
        $global:LASTEXITCODE = 2
        return 2
    }
    $global:LASTEXITCODE = 0
    return 0
}

# Alias - many shops prefer verb-noun; provide the hyphenated form too.
Set-Alias -Name 'report_compliance'  -Value 'Report-Compliance'
Set-Alias -Name 'get_report_json'    -Value 'Get-ReportJson'

_Log ''
_Log "=== SSM Converge v$($script:SsmConvergeVersion) ==="
_Log "  Mode:    $($script:DscMode)"
_Log "  Profile: $($script:DscProfile)"
_Log ''
