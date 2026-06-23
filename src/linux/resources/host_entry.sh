#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: host_entry
#
# Manages entries in /etc/hosts
#
# Usage:
#   host_entry '10.0.1.5' present hostname 'myapp.internal'
#   host_entry '10.0.1.5' present hostname 'myapp.internal myapp'
#   host_entry '10.0.1.5' absent
# ═══════════════════════════════════════════════════════════════════════════════

host_entry() {
  local ip="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local hostname="" hosts_file="/etc/hosts"
  while [ $# -gt 0 ]; do
    case "$1" in
      hostname)   hostname="$2"; shift 2 ;;
      hosts_file) hosts_file="$2"; shift 2 ;;
      *)          shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="host_entry[$ip $hostname]"
  local entry_line="${ip} ${hostname}"

  case "$desired" in
    present)
      # Check if exact entry exists
      local check_end
      if grep -qxF "$entry_line" "$hosts_file" 2>/dev/null; then
        check_end=$(_now_ms)
        local check_ms=$((check_end - check_start))
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif grep -q "^${ip}[[:space:]]" "$hosts_file" 2>/dev/null; then
        # IP exists but with different hostname — update
        check_end=$(_now_ms)
        local check_ms=$((check_end - check_start))

        if _should_apply; then
          local apply_start=$(_now_ms)
          sed -i "s|^${ip}[[:space:]].*|${entry_line}|" "$hosts_file" 2>/dev/null || \
          sed -i '' "s|^${ip}[[:space:]].*|${entry_line}|" "$hosts_file" 2>/dev/null
          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))
          _log_changed "$resource_name" "updated"
          _record_result "$resource_name" "compliant" true "updated" $check_ms $apply_ms
        else
          _log_drift "$resource_name" "IP exists with different hostname"
          _record_result "$resource_name" "non_compliant" false "hostname mismatch" $check_ms 0
        fi
      else
        # Entry doesn't exist — add it
        check_end=$(_now_ms)
        local check_ms=$((check_end - check_start))

        if _should_apply; then
          local apply_start=$(_now_ms)
          echo "$entry_line" >> "$hosts_file"
          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))
          _log_changed "$resource_name" "added"
          _record_result "$resource_name" "compliant" true "added" $check_ms $apply_ms
        else
          _log_drift "$resource_name" "missing"
          _record_result "$resource_name" "non_compliant" false "missing" $check_ms 0
        fi
      fi
      ;;

    absent)
      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if ! grep -q "^${ip}[[:space:]]" "$hosts_file" 2>/dev/null; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        sed -i "/^${ip}[[:space:]]/d" "$hosts_file" 2>/dev/null || \
        sed -i '' "/^${ip}[[:space:]]/d" "$hosts_file" 2>/dev/null
        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))
        _log_changed "$resource_name" "removed"
        _record_result "$resource_name" "compliant" true "removed" $check_ms $apply_ms
      else
        _log_drift "$resource_name" "exists (should be absent)"
        _record_result "$resource_name" "non_compliant" false "exists" $check_ms 0
      fi
      ;;
  esac
}
