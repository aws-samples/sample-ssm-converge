#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: mount
#
# Usage:
#   mount '/mnt/data' present \
#     device '/dev/xvdf' \
#     fstype 'ext4' \
#     options 'defaults,noatime'
#
#   mount '/mnt/old' absent
# ═══════════════════════════════════════════════════════════════════════════════

mount_fs() {
  local mount_point="$1"
  local desired="$2"

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi
  shift 2

  local device="" fstype="auto" options="defaults" dump="0" pass="0" persist="true"
  while [ $# -gt 0 ]; do
    case "$1" in
      device)  device="$2"; shift 2 ;;
      fstype)  fstype="$2"; shift 2 ;;
      options) options="$2"; shift 2 ;;
      dump)    dump="$2"; shift 2 ;;
      pass)    pass="$2"; shift 2 ;;
      persist) persist="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="mount[$mount_point]"

  case "$desired" in
    present|mounted)
      local is_mounted=false
      local in_fstab=false

      mount | grep -q " on ${mount_point} " && is_mounted=true
      grep -q "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab 2>/dev/null && in_fstab=true

      local compliant=true
      local reasons=()

      ! $is_mounted && compliant=false && reasons+=("not mounted")
      [ "$persist" = "true" ] && ! $in_fstab && compliant=false && reasons+=("not in fstab")

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if $compliant; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)

        # Create mount point if needed
        mkdir -p "$mount_point" 2>/dev/null

        # Add to fstab if not present
        if [ "$persist" = "true" ] && ! $in_fstab; then
          echo "${device} ${mount_point} ${fstype} ${options} ${dump} ${pass}" >> /etc/fstab
        fi

        # Mount if not mounted
        if ! $is_mounted; then
          mount "$mount_point" &>/dev/null || mount -t "$fstype" -o "$options" "$device" "$mount_point" &>/dev/null
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

    absent|unmounted)
      local is_mounted=false
      mount | grep -q " on ${mount_point} " && is_mounted=true

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if ! $is_mounted; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        umount "$mount_point" &>/dev/null

        # Remove from fstab
        if grep -q "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab 2>/dev/null; then
          sed -i "\|[[:space:]]${mount_point}[[:space:]]|d" /etc/fstab 2>/dev/null || \
          sed -i '' "\|[[:space:]]${mount_point}[[:space:]]|d" /etc/fstab 2>/dev/null
        fi

        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))
        _log_changed "$resource_name" "unmounted"
        _record_result "$resource_name" "compliant" true "unmounted" $check_ms $apply_ms
      else
        _log_drift "$resource_name" "mounted (should be absent)"
        _record_result "$resource_name" "non_compliant" false "mounted" $check_ms 0
      fi
      ;;
  esac
}
