#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: user
#
# Supported platforms: Linux, macOS, FreeBSD, OpenBSD
#
# Usage:
#   user 'deploy' present
#   user 'deploy' present shell '/bin/bash' groups 'www-data,docker' home '/home/deploy'
#   user 'olduser' absent
# ═══════════════════════════════════════════════════════════════════════════════

user() {
  local name="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local shell="" groups="" home="" system="false" uid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      shell)  shell="$2"; shift 2 ;;
      groups) groups="$2"; shift 2 ;;
      home)   home="$2"; shift 2 ;;
      system) system="$2"; shift 2 ;;
      uid)    uid="$2"; shift 2 ;;
      *)      shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="user/$name"

  case "$desired" in
    present)
      local exists=false
      id "$name" &>/dev/null && exists=true

      if $exists; then
        # Check attributes if specified
        local compliant=true
        local reasons=()

        if [ -n "$shell" ]; then
          local cur_shell=$(getent passwd "$name" 2>/dev/null | cut -d: -f7)
          [ -z "$cur_shell" ] && cur_shell=$(grep "^${name}:" /etc/passwd 2>/dev/null | cut -d: -f7)
          if [ "$cur_shell" != "$shell" ]; then
            compliant=false
            reasons+=("shell is $cur_shell, want $shell")
          fi
        fi

        local check_end=$(_now_ms)
        local check_ms=$((check_end - check_start))

        if $compliant; then
          _log_ok "$resource_name"
          _record_result "$resource_name" "compliant" false "" $check_ms 0
        elif _should_apply; then
          local apply_start=$(_now_ms)
          local mod_args=""
          [ -n "$shell" ] && mod_args="$mod_args -s $shell"
          [ -n "$groups" ] && mod_args="$mod_args -G $groups"
          [ -n "$home" ] && mod_args="$mod_args -d $home"

          usermod $mod_args "$name" &>/dev/null

          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))
          local reason_str=$(IFS=', '; echo "${reasons[*]}")
          _log_changed "$resource_name" "modified ($reason_str)"
          _record_result "$resource_name" "compliant" true "modified: $reason_str" $check_ms $apply_ms
        else
          local reason_str=$(IFS=', '; echo "${reasons[*]}")
          _log_drift "$resource_name" "$reason_str"
          _record_result "$resource_name" "non_compliant" false "$reason_str" $check_ms 0
        fi
      else
        local check_end=$(_now_ms)
        local check_ms=$((check_end - check_start))

        if _should_apply; then
          local apply_start=$(_now_ms)
          local add_args=""
          [ -n "$shell" ] && add_args="$add_args -s $shell"
          [ -n "$groups" ] && add_args="$add_args -G $groups"
          [ -n "$home" ] && add_args="$add_args -m -d $home"
          [ "$system" = "true" ] && add_args="$add_args -r"
          [ -n "$uid" ] && add_args="$add_args -u $uid"

          useradd $add_args "$name" &>/dev/null

          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))

          if id "$name" &>/dev/null; then
            _log_changed "$resource_name" "created"
            _record_result "$resource_name" "compliant" true "created" $check_ms $apply_ms
          else
            _log_error "$resource_name" "creation failed"
            _record_result "$resource_name" "error" false "creation failed" $check_ms $apply_ms
            return 1
          fi
        else
          _log_drift "$resource_name" "missing"
          _record_result "$resource_name" "non_compliant" false "missing" $check_ms 0
        fi
      fi
      ;;

    absent)
      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if ! id "$name" &>/dev/null; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        userdel -r "$name" &>/dev/null
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
      _log_error "$resource_name" "unknown state: $desired"
      _record_result "$resource_name" "error" false "unknown state: $desired"
      return 1
      ;;
  esac
}
