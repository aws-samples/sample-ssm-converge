#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: cron
#
# Usage:
#   cron 'backup-db' present \
#     schedule '0 2 * * *' \
#     command '/usr/local/bin/backup.sh' \
#     user 'root'
#
#   cron 'old-job' absent user 'root'
# ═══════════════════════════════════════════════════════════════════════════════

cron() {
  local name="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local schedule="" command="" cron_user="root"
  while [ $# -gt 0 ]; do
    case "$1" in
      schedule) schedule="$2"; shift 2 ;;
      command)  command="$2"; shift 2 ;;
      user)     cron_user="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="cron/$name"
  local marker="# SSM-CONVERGE: $name"

  case "$desired" in
    present)
      # Check if cron entry already exists
      local current_cron
      current_cron=$(crontab -l -u "$cron_user" 2>/dev/null)
      local entry_line="${schedule} ${command} ${marker}"

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if echo "$current_cron" | grep -qF "$marker"; then
        # Entry exists — check if it matches
        local existing_line=$(echo "$current_cron" | grep -F "$marker")
        if [ "$existing_line" = "$entry_line" ]; then
          _log_ok "$resource_name"
          _record_result "$resource_name" "compliant" false "" $check_ms 0
        elif _should_apply; then
          local apply_start=$(_now_ms)
          # Replace existing entry
          local new_cron=$(echo "$current_cron" | grep -vF "$marker")
          new_cron="${new_cron}"$'\n'"${entry_line}"
          echo "$new_cron" | crontab -u "$cron_user" - 2>/dev/null
          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))
          _log_changed "$resource_name" "updated"
          _record_result "$resource_name" "compliant" true "updated" $check_ms $apply_ms
        else
          _log_drift "$resource_name" "schedule/command mismatch"
          _record_result "$resource_name" "non_compliant" false "mismatch" $check_ms 0
        fi
      else
        # Entry doesn't exist
        if _should_apply; then
          local apply_start=$(_now_ms)
          (crontab -l -u "$cron_user" 2>/dev/null; echo "$entry_line") | crontab -u "$cron_user" - 2>/dev/null
          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))
          _log_changed "$resource_name" "created"
          _record_result "$resource_name" "compliant" true "created" $check_ms $apply_ms
        else
          _log_drift "$resource_name" "missing"
          _record_result "$resource_name" "non_compliant" false "missing" $check_ms 0
        fi
      fi
      ;;

    absent)
      local current_cron
      current_cron=$(crontab -l -u "$cron_user" 2>/dev/null)

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if ! echo "$current_cron" | grep -qF "$marker"; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        echo "$current_cron" | grep -vF "$marker" | crontab -u "$cron_user" - 2>/dev/null
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
