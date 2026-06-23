#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: execute
#
# Run a shell command. Idempotency comes from one of three guards: the command
# is only executed when its guard says it needs to run. Without a guard, the
# command runs on every enforce/destroy pass (use sparingly).
#
# Guards (any one — or both — may be supplied):
#   creates  '/path/to/marker'   — skip if path exists
#   only_if  'shell test'        — run only if test succeeds (rc=0)
#   not_if   'shell test'        — skip if test succeeds (rc=0)
#
# Optional knobs:
#   user     'username'          — sudo -u runner
#   cwd      '/some/dir'         — chdir before running
#   env      'KEY=VALUE'         — repeatable; sets one env var
#   timeout  300                 — wall-clock timeout in seconds
#
# Usage:
#   # Install a vendor .deb that's already on disk; idempotent via creates.
#   execute 'install-cw-agent' \
#     command 'dpkg -i /tmp/amazon-cloudwatch-agent.deb' \
#     creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'
#
#   # Run a one-shot only when a sentinel file is missing.
#   execute 'first-boot-init' \
#     command '/opt/app/bin/initialize.sh' \
#     not_if  'test -f /var/lib/app/.initialized'
#
#   # Pair with `file` to download + install.
#   file '/tmp/agent.rpm' present source 'https://vendor.com/agent.rpm'
#   execute 'install-vendor-agent' \
#     command 'rpm -i /tmp/agent.rpm' \
#     not_if  'rpm -q vendor-agent'
# ═══════════════════════════════════════════════════════════════════════════════

execute() {
  local name="$1"
  shift

  local desired="run"
  # If second positional arg looks like a state token, consume it; otherwise it's a kw arg.
  case "$1" in
    run|once|present) desired="$1"; shift ;;
  esac

  # Parse keyword args
  local cmd="" creates="" only_if="" not_if=""
  local run_user="" cwd="" timeout=""
  local _env=()
  while [ $# -gt 0 ]; do
    case "$1" in
      command) cmd="$2"; shift 2 ;;
      creates) creates="$2"; shift 2 ;;
      only_if) only_if="$2"; shift 2 ;;
      not_if)  not_if="$2"; shift 2 ;;
      user)    run_user="$2"; shift 2 ;;
      cwd)     cwd="$2"; shift 2 ;;
      env)     _env+=("$2"); shift 2 ;;
      timeout) timeout="$2"; shift 2 ;;
      notify)  notify="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="execute/$name"

  if [ -z "$cmd" ]; then
    _log_error "$resource_name" "command is required"
    _record_result "$resource_name" "error" false "missing command"
    return 1
  fi

  # ── Decide whether to run ──
  # Precedence: creates → not_if → only_if. If multiple are set they all have
  # to agree the command is needed.
  local needs_run=true
  local skip_reason=""

  if [ -n "$creates" ] && [ -e "$creates" ]; then
    needs_run=false
    skip_reason="$creates exists"
  fi

  if $needs_run && [ -n "$not_if" ]; then
    if eval "$not_if" &>/dev/null; then
      needs_run=false
      skip_reason="not_if succeeded"
    fi
  fi

  if $needs_run && [ -n "$only_if" ]; then
    if ! eval "$only_if" &>/dev/null; then
      needs_run=false
      skip_reason="only_if failed"
    fi
  fi

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  # In destroy mode, an execute is treated as a no-op unless a separate destroy
  # resource is wired up. Most installer commands don't have a one-line undo.
  if _is_destroy_mode; then
    _log_ok "$resource_name (skipped in destroy mode)"
    _record_result "$resource_name" "compliant" false "skipped in destroy mode" $check_ms 0
    return 0
  fi

  if ! $needs_run; then
    _log_ok "$resource_name"
    _record_result "$resource_name" "compliant" false "$skip_reason" $check_ms 0
    return 0
  fi

  # Audit mode: report drift, don't run.
  if ! _should_apply; then
    _log_drift "$resource_name" "would run"
    _record_result "$resource_name" "non_compliant" false "would run" $check_ms 0
    return 0
  fi

  # ── Build invocation ──
  local apply_start=$(_now_ms)

  # Compose env vars + cwd into a single bash -c string so `sudo -u` can pick
  # them up cleanly without inheriting the parent shell's environment.
  local script="set -e"
  if [ -n "$cwd" ]; then
    script+=$'\n'"cd \"$cwd\""
  fi
  if [ ${#_env[@]} -gt 0 ]; then
    local kv
    for kv in "${_env[@]}"; do
      script+=$'\n'"export $kv"
    done
  fi
  script+=$'\n'"$cmd"

  local rc=0
  local cmd_output

  # The command runs synchronously. Stdout+stderr captured for the report,
  # but only logged on failure to avoid drowning the verbose stream.
  local runner=()
  if [ -n "$timeout" ] && command -v timeout &>/dev/null; then
    runner+=(timeout --kill-after=10 "$timeout")
  fi

  # Safe expansion for empty arrays under set -u (bash 4.x): use the
  # ${arr[@]+"${arr[@]}"} guard.
  if [ -n "$run_user" ] && [ "$(id -un)" != "$run_user" ]; then
    cmd_output=$(${runner[@]+"${runner[@]}"} sudo -u "$run_user" -E bash -c "$script" 2>&1)
    rc=$?
  else
    cmd_output=$(${runner[@]+"${runner[@]}"} bash -c "$script" 2>&1)
    rc=$?
  fi

  local apply_end=$(_now_ms)
  local apply_ms=$((apply_end - apply_start))

  if [ $rc -eq 0 ]; then
    _log_changed "$resource_name" "executed"
    _record_result "$resource_name" "compliant" true "executed" $check_ms $apply_ms
    [ -n "${notify:-}" ] && _notify_handler "$notify"
    return 0
  fi

  # On failure, surface a single-line snippet of the captured output. Full
  # output goes to the debug log. We grab the last non-empty line as the most
  # likely-useful summary; fall back to a head if every line is empty.
  local snippet
  snippet=$(printf '%s' "$cmd_output" | tr -d '\r' | awk 'NF{last=$0} END{print last}')
  [ -z "$snippet" ] && snippet=$(printf '%s' "$cmd_output" | head -c 200 | tr '\n' ' ')
  # Trim to keep log lines readable (~200 chars).
  snippet="${snippet:0:200}"

  _debug "execute/$name failed (rc=$rc): $(printf '%s' "$cmd_output" | head -c 2000)"
  _log_error "$resource_name" "exit $rc: $snippet"
  _record_result "$resource_name" "error" false "exit $rc: $snippet" $check_ms $apply_ms
  return 1
}
