#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: directory
#
# Usage:
#   directory '/var/www/app' present owner 'deploy' mode '0755'
#   directory '/tmp/old-cache' absent
# ═══════════════════════════════════════════════════════════════════════════════

directory() {
  local path="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  # Parse keyword args
  local owner="" group="" mode="" recursive="false"
  while [ $# -gt 0 ]; do
    case "$1" in
      owner)     owner="$2"; shift 2 ;;
      group)     group="$2"; shift 2 ;;
      mode)      mode="$2"; shift 2 ;;
      recursive) recursive="$2"; shift 2 ;;
      *)         shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="directory$path"

  case "$desired" in
    present)
      local compliant=true
      local reasons=()

      if [ ! -d "$path" ]; then
        compliant=false
        reasons+=("missing")
      else
        # Check owner
        if [ -n "$owner" ]; then
          local cur_owner=$(stat -c '%U' "$path" 2>/dev/null)
          if [ "$cur_owner" != "$owner" ]; then
            compliant=false
            reasons+=("owner is $cur_owner, want $owner")
          fi
        fi

        # Check group
        if [ -n "$group" ]; then
          local cur_group=$(stat -c '%G' "$path" 2>/dev/null)
          if [ "$cur_group" != "$group" ]; then
            compliant=false
            reasons+=("group is $cur_group, want $group")
          fi
        fi

        # Check mode
        if [ -n "$mode" ]; then
          local cur_mode
          cur_mode=$(_normalize_mode "$(stat -c '%a' "$path" 2>/dev/null)")
          local want_mode
          want_mode=$(_normalize_mode "$mode")
          if [ "$cur_mode" != "$want_mode" ]; then
            compliant=false
            reasons+=("mode is $cur_mode, want $want_mode")
          fi
        fi
      fi

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if $compliant; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)

        mkdir -p "$path" 2>/dev/null

        local chown_flag=""
        [ "$recursive" = "true" ] && chown_flag="-R"

        if [ -n "$owner" ] && [ -n "$group" ]; then
          chown $chown_flag "${owner}:${group}" "$path" 2>/dev/null
        elif [ -n "$owner" ]; then
          chown $chown_flag "$owner" "$path" 2>/dev/null
        elif [ -n "$group" ]; then
          chgrp $chown_flag "$group" "$path" 2>/dev/null
        fi

        if [ -n "$mode" ]; then
          if [ "$recursive" = "true" ]; then
            chmod -R "$mode" "$path" 2>/dev/null
          else
            chmod "$mode" "$path" 2>/dev/null
          fi
        fi

        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))

        local reason_str=$(IFS=', '; echo "${reasons[*]}")
        _log_changed "$resource_name" "converged ($reason_str)"
        _record_result "$resource_name" "compliant" true "converged: $reason_str" $check_ms $apply_ms
      else
        local reason_str=$(IFS=', '; echo "${reasons[*]}")
        _log_drift "$resource_name" "$reason_str"
        _record_result "$resource_name" "non_compliant" false "$reason_str" $check_ms 0
      fi
      ;;

    absent)
      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if [ ! -d "$path" ]; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        rm -rf "$path"
        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))

        _log_changed "$resource_name" "removed"
        _record_result "$resource_name" "compliant" true "removed" $check_ms $apply_ms
      else
        _log_drift "$resource_name" "exists (should be absent)"
        _record_result "$resource_name" "non_compliant" false "exists" $check_ms 0
      fi
      ;;

    *)
      _log_error "$resource_name" "unknown desired state: $desired"
      _record_result "$resource_name" "error" false "unknown state: $desired"
      return 1
      ;;
  esac
}
