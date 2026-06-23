#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: line_in_file
#
# Ensures a specific line exists or is absent in a file.
# Similar to Ansible's lineinfile module.
#
# Usage:
#   line_in_file '/etc/ssh/sshd_config' present \
#     line 'PermitRootLogin no' \
#     match '^#?PermitRootLogin'
#
#   line_in_file '/etc/hosts' present \
#     line '10.0.1.5 myapp.internal'
#
#   line_in_file '/etc/crontab' absent \
#     match '^.*old-script.sh'
# ═══════════════════════════════════════════════════════════════════════════════

# Cross-platform in-place sed. GNU sed needs `-i`, BSD sed (macOS) needs `-i ''`.
# Detect once at source-time.
if sed --version 2>/dev/null | grep -q GNU; then
  _LIF_SED_INPLACE=(sed -i)
else
  _LIF_SED_INPLACE=(sed -i '')
fi

line_in_file() {
  local path="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local line="" match="" after="" notify=""
  while [ $# -gt 0 ]; do
    case "$1" in
      line)   line="$2"; shift 2 ;;
      match)  match="$2"; shift 2 ;;
      after)  after="$2"; shift 2 ;;
      notify) notify="$2"; shift 2 ;;
      *)      shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="line_in_file[$path]"

  # ── File doesn't exist ────────────────────────────────────────────────────

  if [ ! -f "$path" ]; then
    local check_end=$(_now_ms)
    local check_ms=$((check_end - check_start))

    if [ "$desired" = "present" ] && _should_apply; then
      local apply_start=$(_now_ms)
      mkdir -p "$(dirname "$path")" 2>/dev/null
      echo "$line" > "$path"
      local apply_end=$(_now_ms)
      local apply_ms=$((apply_end - apply_start))
      _log_changed "$resource_name" "file created with line"
      _record_result "$resource_name" "compliant" true "file created" $check_ms $apply_ms
      [ -n "$notify" ] && _notify_handler "$notify"
    elif [ "$desired" = "present" ]; then
      _log_drift "$resource_name" "file missing"
      _record_result "$resource_name" "non_compliant" false "file missing" $check_ms 0
    else
      _log_ok "$resource_name"
      _record_result "$resource_name" "compliant" false "" $check_ms 0
    fi
    return
  fi

  case "$desired" in
    present)
      # Compliance rule:
      #   - The exact desired line must be present AT LEAST ONCE.
      #   - When a `match` regex is provided, NO other line must match the regex
      #     (otherwise the file has both a stale and a fixed version, and we'd
      #     re-fire the replacement forever).
      # Equivalent to saying: after convergence, exactly one line satisfies both
      # "matches the regex" and "equals the desired line".

      local has_exact=false
      grep -qxF "$line" "$path" 2>/dev/null && has_exact=true

      local extra_match_count=0
      if [ -n "$match" ]; then
        # Count lines that match the regex BUT are not the desired line.
        extra_match_count=$(grep -E "$match" "$path" 2>/dev/null | grep -vxF "$line" | wc -l | tr -d ' ')
      fi

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if $has_exact && [ "${extra_match_count:-0}" = "0" ]; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
        return
      fi

      if ! _should_apply; then
        if ! $has_exact; then
          _log_drift "$resource_name" "line missing"
          _record_result "$resource_name" "non_compliant" false "line missing" $check_ms 0
        else
          _log_drift "$resource_name" "$extra_match_count stale line(s) matching regex"
          _record_result "$resource_name" "non_compliant" false "stale lines: $extra_match_count" $check_ms 0
        fi
        return
      fi

      # Apply
      local apply_start=$(_now_ms)

      if [ -n "$match" ]; then
        if $has_exact; then
          # Correct line is present + some stale lines also match. Delete the
          # stale ones but keep the correct one.
          grep -E "$match" "$path" | grep -vxF "$line" | while IFS= read -r stale; do
            # Escape sed special chars in the literal line content.
            local esc
            esc=$(printf '%s' "$stale" | sed -e 's/[\/&|]/\\&/g')
            "${_LIF_SED_INPLACE[@]}" "\|^${esc}\$|d" "$path"
          done
        else
          # No exact line yet. If any line matches the regex, replace the
          # FIRST match and delete the rest. If nothing matches, append.
          if [ "${extra_match_count:-0}" = "0" ]; then
            echo "$line" >> "$path"
          else
            # Replace first occurrence, delete any subsequent matches.
            local esc_line
            esc_line=$(printf '%s' "$line" | sed -e 's/[\/&|]/\\&/g')
            awk -v pat="$match" -v repl="$line" '
              $0 ~ pat && !done { print repl; done=1; next }
              $0 ~ pat && done  { next }
              { print }
            ' "$path" > "${path}.new" && mv "${path}.new" "$path"
          fi
        fi
      else
        # No match pattern — just ensure the exact line exists.
        if ! $has_exact; then
          echo "$line" >> "$path"
        fi
      fi

      local apply_end=$(_now_ms)
      local apply_ms=$((apply_end - apply_start))
      _log_changed "$resource_name" "converged"
      _record_result "$resource_name" "compliant" true "converged" $check_ms $apply_ms
      [ -n "$notify" ] && _notify_handler "$notify"
      ;;

    absent)
      local found
      if [ -n "$match" ]; then
        found=$(grep -cE "$match" "$path" 2>/dev/null)
      else
        found=$(grep -cxF "$line" "$path" 2>/dev/null)
      fi

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if [ "${found:-0}" = "0" ]; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        if [ -n "$match" ]; then
          "${_LIF_SED_INPLACE[@]}" "/${match}/d" "$path"
        else
          grep -vxF "$line" "$path" > "${path}.tmp" && mv "${path}.tmp" "$path"
        fi
        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))
        _log_changed "$resource_name" "line removed"
        _record_result "$resource_name" "compliant" true "line removed" $check_ms $apply_ms
        [ -n "$notify" ] && _notify_handler "$notify"
      else
        _log_drift "$resource_name" "line exists (should be absent)"
        _record_result "$resource_name" "non_compliant" false "line exists" $check_ms 0
      fi
      ;;
  esac
}
