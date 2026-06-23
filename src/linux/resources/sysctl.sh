#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: sysctl
#
# Usage:
#   sysctl 'net.ipv4.ip_forward' value '1'
#   sysctl 'vm.swappiness' value '10'
#   sysctl 'net.ipv6.conf.all.disable_ipv6' value '1' persist true
# ═══════════════════════════════════════════════════════════════════════════════

# Find the system sysctl binary (avoid recursive call to our function)
_SYSCTL_BIN=$(command -v sysctl 2>/dev/null || echo "/usr/sbin/sysctl")

sysctl() {
  local key="$1"
  shift

  # Skip in destroy mode — no safe inverse for kernel parameters
  if _is_destroy_mode; then
    _log "  ⊘ sysctl/$key — skipped (no inverse in destroy mode)"
    _record_result "sysctl/$key" "compliant" false "skipped in destroy mode" 0 0
    return 0
  fi

  local value="" persist="true"
  while [ $# -gt 0 ]; do
    case "$1" in
      value)   value="$2"; shift 2 ;;
      persist) persist="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="sysctl/$key"

  # Get current value using the system binary (not this function). Kernel
  # sysctls like net.ipv4.ip_local_port_range return tab-separated values
  # ("32768\t60999"), so we normalise all internal whitespace runs to single
  # spaces for comparison — without stripping the spaces entirely, which would
  # glue two numbers together.
  local current
  current=$("$_SYSCTL_BIN" -n "$key" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
  local desired_clean
  desired_clean=$(echo "$value" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  if [ "$current" = "$desired_clean" ]; then
    _log_ok "$resource_name"
    _record_result "$resource_name" "compliant" false "" $check_ms 0
  elif _should_apply; then
    local apply_start=$(_now_ms)

    # Apply immediately using system binary
    if ! "$_SYSCTL_BIN" -w "${key}=${value}" &>/dev/null; then
      local apply_end=$(_now_ms)
      local apply_ms=$((apply_end - apply_start))
      _log_error "$resource_name" "failed to set (invalid key or permission denied)"
      _record_result "$resource_name" "error" false "sysctl -w failed" $check_ms $apply_ms
      return 1
    fi

    # Persist to /etc/sysctl.d/ if requested
    if [ "$persist" = "true" ]; then
      local conf_file="/etc/sysctl.d/99-ssm-converge.conf"
      mkdir -p /etc/sysctl.d 2>/dev/null

      if [ -f "$conf_file" ] && grep -q "^${key}" "$conf_file" 2>/dev/null; then
        sed -i "s|^${key}.*|${key} = ${value}|" "$conf_file" 2>/dev/null || \
        sed -i '' "s|^${key}.*|${key} = ${value}|" "$conf_file" 2>/dev/null
      else
        echo "${key} = ${value}" >> "$conf_file"
      fi
    fi

    local apply_end=$(_now_ms)
    local apply_ms=$((apply_end - apply_start))
    _log_changed "$resource_name" "set to $value (was: $current)"
    _record_result "$resource_name" "compliant" true "set to $value" $check_ms $apply_ms
  else
    _log_drift "$resource_name" "is $current, want $desired_clean"
    _record_result "$resource_name" "non_compliant" false "is $current, want $desired_clean" $check_ms 0
  fi
}
