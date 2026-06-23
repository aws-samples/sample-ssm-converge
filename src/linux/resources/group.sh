#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: group
#
# Usage:
#   group 'www-data' present
#   group 'developers' present members 'alice,bob,charlie'
#   group 'oldgroup' absent
# ═══════════════════════════════════════════════════════════════════════════════

group() {
  local name="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local members="" gid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      members) members="$2"; shift 2 ;;
      gid)     gid="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="group/$name"

  case "$desired" in
    present)
      local exists=false
      getent group "$name" &>/dev/null && exists=true

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if $exists; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        local add_args=""
        [ -n "$gid" ] && add_args="$add_args -g $gid"

        groupadd $add_args "$name" &>/dev/null

        if [ -n "$members" ]; then
          IFS=',' read -ra MEMBER_LIST <<< "$members"
          for member in "${MEMBER_LIST[@]}"; do
            usermod -aG "$name" "$(echo "$member" | xargs)" &>/dev/null
          done
        fi

        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))
        _log_changed "$resource_name" "created"
        _record_result "$resource_name" "compliant" true "created" $check_ms $apply_ms
      else
        _log_drift "$resource_name" "missing"
        _record_result "$resource_name" "non_compliant" false "missing" $check_ms 0
      fi
      ;;

    absent)
      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if ! getent group "$name" &>/dev/null; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        groupdel "$name" &>/dev/null
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
