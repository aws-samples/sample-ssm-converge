#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: service
#
# Supported platforms:
#   Linux:   systemd (most modern distros), sysvinit/upstart (legacy),
#            openrc (Alpine/Gentoo)
#   Unix:    rc.d (FreeBSD), SMF (Solaris/illumos)
#   macOS:   launchctl (launchd)
#
# Usage:
#   service 'nginx' running enabled
#   service 'nginx' running
#   service 'postfix' stopped disabled
#   service 'nginx' restarted
# ═══════════════════════════════════════════════════════════════════════════════

_detect_init_system() {
  if [ "$(uname)" = "Darwin" ]; then
    echo "launchctl"
  elif command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    echo "systemd"
  elif command -v rc-service &>/dev/null; then
    echo "openrc"
  elif [ "$(uname)" = "FreeBSD" ] && [ -d /etc/rc.d ]; then
    echo "rcd"
  elif command -v svcs &>/dev/null && command -v svcadm &>/dev/null; then
    echo "smf"
  elif command -v service &>/dev/null; then
    echo "sysvinit"
  else
    echo ""
  fi
}

_service_is_active() {
  local init="$1" name="$2"
  case "$init" in
    systemd)
      [ "$(systemctl is-active "$name" 2>/dev/null)" = "active" ]
      ;;
    openrc)
      rc-service "$name" status &>/dev/null
      ;;
    sysvinit)
      service "$name" status &>/dev/null
      ;;
    rcd)
      service "$name" onestatus &>/dev/null
      ;;
    smf)
      [ "$(svcs -H -o state "$name" 2>/dev/null)" = "online" ]
      ;;
    launchctl)
      local label=$(_launchctl_label "$name")
      launchctl list "$label" &>/dev/null
      ;;
  esac
}

_service_is_enabled() {
  local init="$1" name="$2"
  case "$init" in
    systemd)
      [ "$(systemctl is-enabled "$name" 2>/dev/null)" = "enabled" ]
      ;;
    openrc)
      rc-update show 2>/dev/null | grep -q "$name"
      ;;
    sysvinit)
      if command -v chkconfig &>/dev/null; then
        chkconfig --list "$name" 2>/dev/null | grep -q ':on'
      elif command -v update-rc.d &>/dev/null; then
        # Debian-style: check if symlinks exist in runlevel dirs
        ls /etc/rc2.d/S*"$name" &>/dev/null
      else
        return 0  # Assume enabled if we can't check
      fi
      ;;
    rcd)
      grep -q "${name}_enable=\"YES\"" /etc/rc.conf 2>/dev/null
      ;;
    smf)
      # SMF services are enabled if not in "disabled" state
      [ "$(svcs -H -o state "$name" 2>/dev/null)" != "disabled" ]
      ;;
    launchctl)
      # launchd services are enabled if plist is loaded
      local label=$(_launchctl_label "$name")
      launchctl list "$label" &>/dev/null
      ;;
  esac
}

_service_start() {
  local init="$1" name="$2"
  case "$init" in
    systemd)   systemctl start "$name" &>/dev/null ;;
    openrc)    rc-service "$name" start &>/dev/null ;;
    sysvinit)  service "$name" start &>/dev/null ;;
    rcd)       service "$name" onestart &>/dev/null ;;
    smf)       svcadm enable "$name" &>/dev/null ;;
    launchctl)
      local label=$(_launchctl_label "$name")
      launchctl start "$label" &>/dev/null
      ;;
  esac
}

_service_stop() {
  local init="$1" name="$2"
  case "$init" in
    systemd)   systemctl stop "$name" &>/dev/null ;;
    openrc)    rc-service "$name" stop &>/dev/null ;;
    sysvinit)  service "$name" stop &>/dev/null ;;
    rcd)       service "$name" onestop &>/dev/null ;;
    smf)       svcadm disable "$name" &>/dev/null ;;
    launchctl)
      local label=$(_launchctl_label "$name")
      launchctl stop "$label" &>/dev/null
      ;;
  esac
}

_service_restart() {
  local init="$1" name="$2"
  case "$init" in
    systemd)   systemctl restart "$name" &>/dev/null ;;
    openrc)    rc-service "$name" restart &>/dev/null ;;
    sysvinit)  service "$name" restart &>/dev/null ;;
    rcd)       service "$name" onerestart &>/dev/null ;;
    smf)       svcadm restart "$name" &>/dev/null ;;
    launchctl)
      local label=$(_launchctl_label "$name")
      launchctl stop "$label" &>/dev/null
      launchctl start "$label" &>/dev/null
      ;;
  esac
}

_service_enable() {
  local init="$1" name="$2"
  case "$init" in
    systemd)   systemctl enable "$name" &>/dev/null ;;
    openrc)    rc-update add "$name" default &>/dev/null ;;
    sysvinit)
      if command -v chkconfig &>/dev/null; then
        chkconfig "$name" on &>/dev/null
      elif command -v update-rc.d &>/dev/null; then
        update-rc.d "$name" defaults &>/dev/null
      fi
      ;;
    rcd)
      # Add to /etc/rc.conf
      if ! grep -q "${name}_enable" /etc/rc.conf 2>/dev/null; then
        echo "${name}_enable=\"YES\"" >> /etc/rc.conf
      else
        sed -i '' "s/${name}_enable=.*/${name}_enable=\"YES\"/" /etc/rc.conf 2>/dev/null || \
        sed -i "s/${name}_enable=.*/${name}_enable=\"YES\"/" /etc/rc.conf 2>/dev/null
      fi
      ;;
    smf)       svcadm enable "$name" &>/dev/null ;;
    launchctl)
      local plist=$(_launchctl_plist "$name")
      [ -n "$plist" ] && launchctl load "$plist" &>/dev/null
      ;;
  esac
}

_service_disable() {
  local init="$1" name="$2"
  case "$init" in
    systemd)   systemctl disable "$name" &>/dev/null ;;
    openrc)    rc-update del "$name" default &>/dev/null ;;
    sysvinit)
      if command -v chkconfig &>/dev/null; then
        chkconfig "$name" off &>/dev/null
      elif command -v update-rc.d &>/dev/null; then
        update-rc.d "$name" disable &>/dev/null
      fi
      ;;
    rcd)
      sed -i '' "s/${name}_enable=.*/${name}_enable=\"NO\"/" /etc/rc.conf 2>/dev/null || \
      sed -i "s/${name}_enable=.*/${name}_enable=\"NO\"/" /etc/rc.conf 2>/dev/null
      ;;
    smf)       svcadm disable "$name" &>/dev/null ;;
    launchctl)
      local plist=$(_launchctl_plist "$name")
      [ -n "$plist" ] && launchctl unload "$plist" &>/dev/null
      ;;
  esac
}

# macOS helpers
_launchctl_label() {
  local name="$1"
  # Try common label patterns
  if launchctl list "com.apple.$name" &>/dev/null 2>&1; then
    echo "com.apple.$name"
  elif launchctl list "org.homebrew.mxcl.$name" &>/dev/null 2>&1; then
    echo "org.homebrew.mxcl.$name"
  else
    echo "$name"
  fi
}

_launchctl_plist() {
  local name="$1"
  local label=$(_launchctl_label "$name")
  # Search common plist locations
  for dir in /Library/LaunchDaemons /Library/LaunchAgents ~/Library/LaunchAgents /usr/local/opt/*/homebrew.mxcl.*.plist; do
    if [ -f "$dir/$label.plist" ]; then
      echo "$dir/$label.plist"
      return
    fi
  done
}

# ─── Main service function ────────────────────────────────────────────────────

service() {
  local name="$1"
  local desired_state="$2"
  local desired_enabled="${3:-}"
  shift
  shift
  [ $# -gt 0 ] && shift  # shift desired_enabled if present

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired_state=$(_flip_state "$desired_state")
    [ -n "$desired_enabled" ] && desired_enabled=$(_flip_state "$desired_enabled")
  fi

  # Parse additional keyword args
  local notify=""
  while [ $# -gt 0 ]; do
    case "$1" in
      notify) notify="$2"; shift 2 ;;
      *)      shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="service/$name"

  # ── Detect init system ──
  local init_system=$(_detect_init_system)
  if [ -z "$init_system" ]; then
    _log_error "$resource_name" "no supported init system found (tried: systemd, openrc, sysvinit, rcd, smf, launchctl)"
    _record_result "$resource_name" "error" false "no init system"
    return 1
  fi

  # ── Check current state ──
  local is_active=false
  local is_enabled=false

  _service_is_active "$init_system" "$name" && is_active=true
  _service_is_enabled "$init_system" "$name" && is_enabled=true

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  # ── Handle 'restarted' (always applies) ──
  if [ "$desired_state" = "restarted" ]; then
    if _should_apply; then
      local apply_start=$(_now_ms)
      _service_restart "$init_system" "$name"
      local apply_end=$(_now_ms)
      local apply_ms=$((apply_end - apply_start))

      _log_changed "$resource_name" "restarted"
      _record_result "$resource_name" "compliant" true "restarted" $check_ms $apply_ms
    else
      _log_drift "$resource_name" "restart requested (audit mode)"
      _record_result "$resource_name" "non_compliant" false "restart pending" $check_ms 0
    fi
    return 0
  fi

  # ── Evaluate desired state ──
  local compliant=true
  local reasons=()

  case "$desired_state" in
    running)
      if ! $is_active; then
        compliant=false
        reasons+=("not running")
      fi
      ;;
    stopped)
      if $is_active; then
        compliant=false
        reasons+=("running (should be stopped)")
      fi
      ;;
  esac

  case "$desired_enabled" in
    enabled)
      if ! $is_enabled; then
        compliant=false
        reasons+=("not enabled")
      fi
      ;;
    disabled)
      if $is_enabled; then
        compliant=false
        reasons+=("enabled (should be disabled)")
      fi
      ;;
  esac

  if $compliant; then
    _log_ok "$resource_name"
    _record_result "$resource_name" "compliant" false "" $check_ms 0
  elif _should_apply; then
    local apply_start=$(_now_ms)

    case "$desired_state" in
      running) _service_start "$init_system" "$name" ;;
      stopped) _service_stop "$init_system" "$name" ;;
    esac

    case "$desired_enabled" in
      enabled)  _service_enable "$init_system" "$name" ;;
      disabled) _service_disable "$init_system" "$name" ;;
    esac

    local apply_end=$(_now_ms)
    local apply_ms=$((apply_end - apply_start))

    # Verify the service is now in the desired state
    local verify_ok=true
    if [ "$desired_state" = "running" ]; then
      _service_is_active "$init_system" "$name" || verify_ok=false
    elif [ "$desired_state" = "stopped" ]; then
      _service_is_active "$init_system" "$name" && verify_ok=false
    fi

    if $verify_ok; then
      local reason_str=$(IFS=', '; echo "${reasons[*]}")
      _log_changed "$resource_name" "converged ($reason_str)"
      _record_result "$resource_name" "compliant" true "converged: $reason_str" $check_ms $apply_ms
    else
      local reason_str=$(IFS=', '; echo "${reasons[*]}")
      _log_error "$resource_name" "failed to converge ($reason_str)"
      _record_result "$resource_name" "error" false "apply failed: $reason_str" $check_ms $apply_ms
      return 1
    fi
  else
    local reason_str=$(IFS=', '; echo "${reasons[*]}")
    _log_drift "$resource_name" "$reason_str"
    _record_result "$resource_name" "non_compliant" false "$reason_str" $check_ms 0
  fi
}
