#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: locale
#
# Supported platforms: Linux (Debian/Ubuntu, RHEL/CentOS, Amazon Linux)
#
# Usage:
#   locale 'en_US.UTF-8'
#   locale 'ja_JP.UTF-8'
# ═══════════════════════════════════════════════════════════════════════════════

locale() {
  local desired_locale="$1"

  # Skip in destroy mode — no safe inverse for locale
  if _is_destroy_mode; then
    _log "  ⊘ locale/$desired_locale — skipped (no inverse in destroy mode)"
    _record_result "locale/$desired_locale" "compliant" false "skipped in destroy mode" 0 0
    return 0
  fi

  local check_start=$(_now_ms)
  local resource_name="locale/$desired_locale"

  # Get current LANG
  local current_locale=""
  if [ -f /etc/default/locale ]; then
    current_locale=$(grep '^LANG=' /etc/default/locale 2>/dev/null | cut -d= -f2 | tr -d '"')
  elif [ -f /etc/locale.conf ]; then
    current_locale=$(grep '^LANG=' /etc/locale.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
  else
    current_locale="${LANG:-}"
  fi

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  if [ "$current_locale" = "$desired_locale" ]; then
    _log_ok "$resource_name"
    _record_result "$resource_name" "compliant" false "" $check_ms 0
  elif _should_apply; then
    local apply_start=$(_now_ms)

    if command -v localectl &>/dev/null; then
      # systemd-based
      localectl set-locale "LANG=$desired_locale" &>/dev/null
    elif [ -f /etc/default/locale ]; then
      # Debian/Ubuntu
      echo "LANG=$desired_locale" > /etc/default/locale
      # Generate locale if locale-gen is available
      command -v locale-gen &>/dev/null && locale-gen "$desired_locale" &>/dev/null
    elif [ -f /etc/locale.conf ]; then
      # RHEL/CentOS
      echo "LANG=$desired_locale" > /etc/locale.conf
    fi

    export LANG="$desired_locale"

    local apply_end=$(_now_ms)
    local apply_ms=$((apply_end - apply_start))
    _log_changed "$resource_name" "set (was: $current_locale)"
    _record_result "$resource_name" "compliant" true "set from $current_locale" $check_ms $apply_ms
  else
    _log_drift "$resource_name" "is $current_locale, want $desired_locale"
    _record_result "$resource_name" "non_compliant" false "is $current_locale" $check_ms 0
  fi
}
