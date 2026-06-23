#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Desired State Configuration Library for AWS Systems Manager
# Version: 0.1.0
# License: Apache 2.0
#
# Usage:
#   source /opt/ssm-converge/lib.sh
#
#   package 'nginx' installed
#   file '/etc/nginx/nginx.conf' present source 's3://bucket/nginx.conf'
#   service 'nginx' running enabled
#
#   # Persist local report + print one-line summary.
#   report_compliance
#
#   # Optional: ship the full report anywhere the customer wants.
#   get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname).json"
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ─── Configuration ─────────────────────────────────────────────────────────────
# All config vars are overridable via the environment.

SSM_CONVERGE_VERSION="0.1.2"

# Execution mode.
#   enforce  — check state, fix drift, write local report, print summary    (default)
#   audit    — check state only (no changes), write local report, print summary
#   destroy  — flip desired state (present→absent, running→stopped) and fix
DSC_MODE="${DSC_MODE:-enforce}"

# Profile/configuration name — appears in reports.
DSC_PROFILE="${DSC_PROFILE:-default}"

# Output style for report_compliance.
#   summary  — one-line header after the run                                 (default)
#   full     — detailed compliance report (used by `ssm-converge comply`)
DSC_REPORT="${DSC_REPORT:-summary}"

# Local on-instance report store (latest.json, history/, drift.log).
DSC_LOCAL_DIR="${DSC_LOCAL_DIR:-/var/lib/ssm-converge}"
DSC_HISTORY_RETAIN="${DSC_HISTORY_RETAIN:-100}"

# Verbose per-resource logging to stdout.
DSC_VERBOSE="${DSC_VERBOSE:-true}"

# Debug log (always-on by default; cheap to keep).
# Falls back to /tmp when the default path isn't writable (e.g. local macOS runs).
DSC_LOG_FILE="${DSC_LOG_FILE:-/var/log/ssm-converge.log}"
if ! ( : >> "$DSC_LOG_FILE" ) 2>/dev/null; then
  DSC_LOG_FILE="/tmp/ssm-converge.log"
fi
DSC_DEBUG="${DSC_DEBUG:-true}"

# Central reporting — OPTIONAL.
# The library ships get_report_json() as the primary integration point; the
# customer pipes the JSON wherever they want. Sample reporters under
# src/reporters/ read their own env vars when you source them on demand:
#   DSC_S3_BUCKET        — used by reporters/s3.sh          (e.g. s3://DOC-EXAMPLE-BUCKET/prefix)
#   DSC_EVENTBRIDGE_BUS  — used by reporters/eventbridge.sh (defaults to 'default')

# ─── Internal State ───────────────────────────────────────────────────────────

DSC_RUN_ID="$(date +%s)-$$"
DSC_RESULTS=()
DSC_HANDLERS_TRIGGERED=()
DSC_HANDLER_DEFS=()

# Cross-platform millisecond timestamp helper.
_now_ms() {
  if date +%s%3N 2>/dev/null | grep -qv 'N'; then
    date +%s%3N
  else
    # macOS/BSD fallback: seconds * 1000.
    echo $(( $(date +%s) * 1000 ))
  fi
}

# Normalize a file-mode string to zero-padded 4-digit octal.
#   "644"   -> "0644"
#   "0644"  -> "0644"
#   "600"   -> "0600"
#   "0"     -> "0000"
#   "000"   -> "0000"
# Makes `stat -c %a` output comparable to user-supplied modes even when the
# actual mode is something like 0000 (which stat prints as "0").
_normalize_mode() {
  local m="${1#0}"           # strip one leading zero if present
  [ -z "$m" ] && m="0"       # "0" -> "0" (not empty)
  printf '%04o' "$((8#$m))" 2>/dev/null || printf '%s' "$1"
}

DSC_START_TIME=$(_now_ms)

# Instance metadata (lazy-loaded, respects pre-set values).
_INSTANCE_ID="${_INSTANCE_ID:-}"
_ACCOUNT_ID="${_ACCOUNT_ID:-}"
_REGION="${_REGION:-}"

# Resolve install path (where lib.sh lives).
SSM_CONVERGE_HOME="${SSM_CONVERGE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ─── Metadata Helpers ─────────────────────────────────────────────────────────
# IMDS lookups. python3 ships with every major distro's base install
# (including Amazon Linux 2023), so no extra package needed.
#
# We grab an IMDSv2 session token once per run and cache it. New AWS AMIs
# ship with HttpTokens=required by default, so token-less IMDSv1 calls 401.
# Falling back to a token-less request is fine for old AMIs that allow it.

_IMDS_TOKEN="${_IMDS_TOKEN:-}"

_get_imds_token() {
  if [ -z "$_IMDS_TOKEN" ]; then
    _IMDS_TOKEN=$(curl -s -X PUT --connect-timeout 2 \
      -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
      http://169.254.169.254/latest/api/token 2>/dev/null || echo "")
  fi
  echo "$_IMDS_TOKEN"
}

_imds_get() {
  local path="$1"
  local token
  token=$(_get_imds_token)
  if [ -n "$token" ]; then
    curl -s --connect-timeout 2 \
      -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/$path" 2>/dev/null
  else
    curl -s --connect-timeout 2 "http://169.254.169.254/$path" 2>/dev/null
  fi
}

_get_instance_id() {
  if [ -z "$_INSTANCE_ID" ]; then
    _INSTANCE_ID=$(_imds_get latest/meta-data/instance-id)
    [ -z "$_INSTANCE_ID" ] && _INSTANCE_ID="unknown"
  fi
  echo "$_INSTANCE_ID"
}

# Pull one field out of the IMDS identity document.
# The document is passed to python as argv[1] to avoid the python-heredoc
# vs pipe-stdin conflict (`python - <<PY` consumes the heredoc as stdin).
_imds_field() {
  local field="$1"
  local doc
  doc=$(_imds_get latest/dynamic/instance-identity/document)

  python3 - "$doc" "$field" <<'PY' 2>/dev/null
import json, sys
doc, field = sys.argv[1], sys.argv[2]
try:
    print(json.loads(doc).get(field, 'unknown'))
except Exception:
    print('unknown')
PY
}

_get_account_id() {
  if [ -z "$_ACCOUNT_ID" ]; then
    _ACCOUNT_ID=$(_imds_field accountId)
  fi
  echo "$_ACCOUNT_ID"
}

_get_region() {
  if [ -z "$_REGION" ]; then
    _REGION=$(_imds_field region)
  fi
  echo "$_REGION"
}

# ─── Debug Logging ─────────────────────────────────────────────────────────────

_debug() {
  if [ "$DSC_DEBUG" = "true" ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$DSC_LOG_FILE" 2>/dev/null
  fi
}

_debug "═══ SSM Converge v$SSM_CONVERGE_VERSION starting ═══"
_debug "Mode=$DSC_MODE Profile=$DSC_PROFILE"
_debug "SSM_CONVERGE_HOME=$SSM_CONVERGE_HOME"

# ─── Output Helpers ───────────────────────────────────────────────────────────

_log() {
  if [ "$DSC_VERBOSE" = "true" ]; then
    echo "$@"
  fi
}

_log_ok()      { _log "  ✓ $1";      _debug "OK: $1"; }
_log_changed() { _log "  ↻ $1 — $2"; _debug "CHANGED: $1 — $2"; }
_log_drift()   { _log "  ✗ $1 — $2"; _debug "DRIFT: $1 — $2"; }
_log_error()   { echo "  ✗ ERROR: $1 — $2" >&2; _debug "ERROR: $1 — $2"; }

# ─── Core Engine ──────────────────────────────────────────────────────────────

_should_apply() {
  [ "$DSC_MODE" = "enforce" ] || [ "$DSC_MODE" = "destroy" ]
}

_is_destroy_mode() {
  [ "$DSC_MODE" = "destroy" ]
}

# Flip desired state for destroy mode.
#   present → absent, installed → uninstalled, running → stopped, ...
_flip_state() {
  local state="$1"
  case "$state" in
    present|installed|mounted)                     echo "absent" ;;
    absent|uninstalled|removed|unmounted)          echo "present" ;;
    running)                                       echo "stopped" ;;
    stopped)                                       echo "running" ;;
    enabled)                                       echo "disabled" ;;
    disabled)                                      echo "enabled" ;;
    *)                                             echo "$state" ;;
  esac
}

_record_result() {
  local resource="$1"
  local status="$2"
  local changed="${3:-false}"
  local detail="${4:-}"
  local check_ms="${5:-0}"
  local apply_ms="${6:-0}"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local entry="{\"resource\":\"$resource\",\"status\":\"$status\",\"changed\":$changed,\"detail\":\"$detail\",\"timestamp\":\"$timestamp\",\"run_id\":\"$DSC_RUN_ID\",\"check_duration_ms\":$check_ms,\"apply_duration_ms\":$apply_ms}"
  DSC_RESULTS+=("$entry")
}

_notify_handler() {
  local handler_name="$1"
  local already=false
  for h in "${DSC_HANDLERS_TRIGGERED[@]}"; do
    [ "$h" = "$handler_name" ] && already=true && break
  done
  if ! $already; then
    DSC_HANDLERS_TRIGGERED+=("$handler_name")
  fi
}

# ─── Handler Registration ────────────────────────────────────────────────────

handler() {
  # Usage: handler 'restart-nginx' systemctl restart nginx
  local name="$1"
  shift
  DSC_HANDLER_DEFS+=("$name|$*")
}

_run_handlers() {
  for triggered in "${DSC_HANDLERS_TRIGGERED[@]}"; do
    for def in "${DSC_HANDLER_DEFS[@]}"; do
      local def_name="${def%%|*}"
      local def_cmd="${def#*|}"
      if [ "$def_name" = "$triggered" ]; then
        _log "  ⚡ Handler: $triggered"
        eval "$def_cmd"
      fi
    done
  done
}

# ─── Source Resource Providers ────────────────────────────────────────────────

_source_resources() {
  local resources_dir="$SSM_CONVERGE_HOME/resources"
  _debug "Loading resources from $resources_dir"
  if [ -d "$resources_dir" ]; then
    for provider in "$resources_dir"/*.sh; do
      if [ -f "$provider" ]; then
        _debug "  Sourcing: $provider"
        source "$provider"
      fi
    done
  else
    _debug "  WARNING: resources dir not found"
  fi
}

# ─── Compliance Reporting ─────────────────────────────────────────────────────
#
# The library gives you two primitives:
#
#   get_report_json   — returns the full run as a JSON string (stdout).
#                       Use this to ship reports to S3, SSM Compliance,
#                       EventBridge, CloudWatch, a custom API — whatever.
#
#   report_compliance — runs any triggered handlers, writes the local
#                       report to $DSC_LOCAL_DIR/latest.json, appends
#                       drift events, and prints a summary (or a full
#                       compliance report when DSC_REPORT=full).
#
# A typical configuration looks like:
#
#   source /opt/ssm-converge/lib.sh
#   ... resources ...
#   report_compliance
#   get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname).json"

# Build the report JSON from the current DSC_RESULTS.
_build_report_json() {
  local timestamp instance_id account_id region
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  instance_id=$(_get_instance_id)
  account_id=$(_get_account_id)
  region=$(_get_region)

  local resources_json="[" first=true
  for result in "${DSC_RESULTS[@]}"; do
    $first || resources_json+=","
    resources_json+="$result"
    first=false
  done
  resources_json+="]"

  local total=${#DSC_RESULTS[@]}
  local compliant=0 non_compliant=0 errors=0 changed=0

  for result in "${DSC_RESULTS[@]}"; do
    if   echo "$result" | grep -q '"status":"compliant"';     then ((compliant++))
    elif echo "$result" | grep -q '"status":"non_compliant"'; then ((non_compliant++))
    else                                                           ((errors++))
    fi
    echo "$result" | grep -q '"changed":true' && ((changed++))
  done

  local compliance_pct=0
  if [ $total -gt 0 ]; then
    compliance_pct=$(echo "scale=1; $compliant * 100 / $total" | bc 2>/dev/null || echo "0")
  fi

  cat <<JSON
{
  "schema": "ssm-converge/report/v1",
  "run_id": "$DSC_RUN_ID",
  "timestamp": "$timestamp",
  "instance_id": "$instance_id",
  "account_id": "$account_id",
  "region": "$region",
  "profile": "$DSC_PROFILE",
  "mode": "$DSC_MODE",
  "summary": {
    "total": $total,
    "compliant": $compliant,
    "non_compliant": $non_compliant,
    "errors": $errors,
    "changed": $changed,
    "compliance_pct": $compliance_pct
  },
  "resources": $resources_json
}
JSON
}

# Public: return the run as a JSON string. Customer pipes it wherever.
get_report_json() {
  _build_report_json
}

# Write latest.json + history + drift.log.
_write_local_report() {
  local report="$1"
  mkdir -p "$DSC_LOCAL_DIR/history" 2>/dev/null

  echo "$report" > "$DSC_LOCAL_DIR/latest.json" 2>/dev/null

  local history_file="$DSC_LOCAL_DIR/history/$(date -u +%Y-%m-%dT%H:%M:%S).json"
  echo "$report" > "$history_file" 2>/dev/null

  # Append drift events (one per non-compliant resource) to drift.log.
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for result in "${DSC_RESULTS[@]}"; do
    if echo "$result" | grep -q '"status":"non_compliant"'; then
      local res detail
      res=$(echo "$result"    | sed -n 's/.*"resource":"\([^"]*\)".*/\1/p')
      detail=$(echo "$result" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
      echo "$ts [$DSC_PROFILE] $res — ${detail:-drift}" >> "$DSC_LOCAL_DIR/drift.log" 2>/dev/null
    fi
  done

  # Rotate history.
  local retain="${DSC_HISTORY_RETAIN:-100}"
  ls -t "$DSC_LOCAL_DIR/history/"*.json 2>/dev/null | tail -n +$((retain + 1)) | xargs rm -f 2>/dev/null
}

report_compliance() {
  _debug "report_compliance() called with ${#DSC_RESULTS[@]} results"

  # Run any triggered handlers before tallying (handlers may change state).
  if _should_apply; then
    _run_handlers
  fi

  local report
  report=$(_build_report_json)

  _write_local_report "$report"

  # Extract summary for printing.
  local total compliant non_compliant errors changed
  total=$(echo "$report"         | sed -n 's/.*"total": \([0-9]*\).*/\1/p' | head -1)
  compliant=$(echo "$report"     | sed -n 's/.*"compliant": \([0-9]*\).*/\1/p' | head -1)
  non_compliant=$(echo "$report" | sed -n 's/.*"non_compliant": \([0-9]*\).*/\1/p' | head -1)
  errors=$(echo "$report"        | sed -n 's/.*"errors": \([0-9]*\).*/\1/p' | head -1)
  changed=$(echo "$report"       | sed -n 's/.*"changed": \([0-9]*\).*/\1/p' | head -1)

  if [ "$DSC_REPORT" = "full" ]; then
    # Full compliance report (used by `ssm-converge comply`).
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  SSM Converge — Compliance Report"
    echo "  Profile: $DSC_PROFILE | Mode: $DSC_MODE"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  ─── Detailed Results ─────────────────────────────"
    for result in "${DSC_RESULTS[@]}"; do
      local res_name res_status res_changed res_detail
      res_name=$(echo "$result"    | sed -n 's/.*"resource":"\([^"]*\)".*/\1/p')
      res_status=$(echo "$result"  | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
      res_changed=$(echo "$result" | sed -n 's/.*"changed":\([^,}]*\).*/\1/p')
      res_detail=$(echo "$result"  | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')

      local icon="✓" label="PASS"
      if   [ "$res_status" = "non_compliant" ]; then icon="✗"; label="FAIL"
      elif [ "$res_status" = "error" ];         then icon="!"; label="ERROR"
      elif [ "$res_changed" = "true" ];         then icon="↻"; label="FIXED"
      fi

      local suffix=""
      [ -n "$res_detail" ] && suffix=" ($res_detail)"
      printf "  %s %-7s %s%s\n" "$icon" "[$label]" "$res_name" "$suffix"
    done
    echo ""
    echo "  ─── Summary ──────────────────────────────────────"
    echo "  Total Checks:   $total"
    echo "  Compliant:      $compliant"
    echo "  Non-Compliant:  $non_compliant"
    echo "  Errors:         $errors"
    echo ""
    echo "  Run ID:         $DSC_RUN_ID"
    echo "  Local Report:   $DSC_LOCAL_DIR/latest.json"
    echo "═══════════════════════════════════════════════════"
  else
    # Summary line (used by `ssm-converge run` / `check` / `destroy`).
    echo ""
    echo "═══ ${total} checks | ${compliant} ok | ${non_compliant} failed | ${errors} errors | ${changed} changed ═══"
  fi

  # Exit semantics.
  #   audit mode + drift     → 2  (SSM step can detect and alert)
  #   errors present         → 1
  #   else                   → 0
  if [ "${errors:-0}" -gt 0 ]; then
    return 1
  fi
  if [ "${non_compliant:-0}" -gt 0 ] && [ "$DSC_MODE" = "audit" ]; then
    return 2
  fi
  return 0
}

# ─── Initialize ───────────────────────────────────────────────────────────────

mkdir -p "$DSC_LOCAL_DIR/history" 2>/dev/null
_source_resources

_log ""
_log "═══ SSM Converge v$SSM_CONVERGE_VERSION ═══"
_log "  Mode:    $DSC_MODE"
_log "  Profile: $DSC_PROFILE"
_log ""
