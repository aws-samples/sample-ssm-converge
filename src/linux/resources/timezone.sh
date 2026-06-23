#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: timezone
#
# Supported platforms: Linux (timedatectl, /etc/timezone), macOS, FreeBSD
#
# Usage:
#   timezone 'UTC'
#   timezone 'America/New_York'
#   timezone 'Asia/Tokyo'
# ═══════════════════════════════════════════════════════════════════════════════

timezone() {
  local desired_tz="$1"

  # Skip in destroy mode — no safe inverse for timezone
  if _is_destroy_mode; then
    _log "  ⊘ timezone/$desired_tz — skipped (no inverse in destroy mode)"
    _record_result "timezone/$desired_tz" "compliant" false "skipped in destroy mode" 0 0
    return 0
  fi

  local check_start=$(_now_ms)
  local resource_name="timezone/$desired_tz"

  # Get current timezone
  local current_tz=""
  if command -v timedatectl &>/dev/null; then
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
  elif [ -f /etc/timezone ]; then
    current_tz=$(cat /etc/timezone 2>/dev/null | tr -d '[:space:]')
  elif [ -L /etc/localtime ]; then
    current_tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
  elif [ "$(uname)" = "Darwin" ]; then
    current_tz=$(systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}')
  fi

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  if [ "$current_tz" = "$desired_tz" ]; then
    _log_ok "$resource_name"
    _record_result "$resource_name" "compliant" false "" $check_ms 0
  elif _should_apply; then
    local apply_start=$(_now_ms)

    if command -v timedatectl &>/dev/null; then
      timedatectl set-timezone "$desired_tz" &>/dev/null
    elif [ "$(uname)" = "Darwin" ]; then
      systemsetup -settimezone "$desired_tz" &>/dev/null
    elif [ "$(uname)" = "FreeBSD" ]; then
      cp "/usr/share/zoneinfo/$desired_tz" /etc/localtime 2>/dev/null
    else
      # Fallback for older Linux
      ln -sf "/usr/share/zoneinfo/$desired_tz" /etc/localtime 2>/dev/null
      echo "$desired_tz" > /etc/timezone 2>/dev/null
    fi

    local apply_end=$(_now_ms)
    local apply_ms=$((apply_end - apply_start))
    _log_changed "$resource_name" "set (was: $current_tz)"
    _record_result "$resource_name" "compliant" true "set from $current_tz" $check_ms $apply_ms
  else
    _log_drift "$resource_name" "is $current_tz, want $desired_tz"
    _record_result "$resource_name" "non_compliant" false "is $current_tz" $check_ms 0
  fi
}
