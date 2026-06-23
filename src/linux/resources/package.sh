#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: package
#
# Supported platforms:
#   Linux:   apt (Debian/Ubuntu), yum (RHEL/CentOS/Amazon Linux),
#            dnf (Fedora/RHEL 8+/Amazon Linux 2023), zypper (SUSE),
#            apk (Alpine)
#   Unix:    pkg (FreeBSD), pkgin (NetBSD/SmartOS), pkg_add (OpenBSD)
#   macOS:   brew (Homebrew)
#
# Usage:
#   package 'nginx' installed
#   package 'nginx' installed version '1.24'
#   package 'telnet' uninstalled
# ═══════════════════════════════════════════════════════════════════════════════

_detect_pkg_manager() {
  # Detect in order of specificity
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  elif command -v zypper &>/dev/null; then
    echo "zypper"
  elif command -v apk &>/dev/null; then
    echo "apk"
  elif command -v brew &>/dev/null; then
    echo "brew"
  elif command -v pkg &>/dev/null && [ "$(uname)" = "FreeBSD" ]; then
    echo "pkg_freebsd"
  elif command -v pkgin &>/dev/null; then
    echo "pkgin"
  elif command -v pkg_add &>/dev/null; then
    echo "pkg_add"
  else
    echo ""
  fi
}

_package_is_installed() {
  local pkg_mgr="$1" name="$2"
  case "$pkg_mgr" in
    apt)
      dpkg -l "$name" 2>/dev/null | grep -q '^ii'
      ;;
    yum|dnf)
      rpm -q "$name" &>/dev/null
      ;;
    zypper)
      rpm -q "$name" &>/dev/null
      ;;
    apk)
      apk info -e "$name" &>/dev/null
      ;;
    brew)
      brew list "$name" &>/dev/null
      ;;
    pkg_freebsd)
      pkg info "$name" &>/dev/null
      ;;
    pkgin)
      pkgin list 2>/dev/null | grep -q "^${name}-"
      ;;
    pkg_add)
      pkg_info "$name" &>/dev/null 2>&1 || pkg_info -e "$name-*" &>/dev/null
      ;;
  esac
}

_package_get_version() {
  local pkg_mgr="$1" name="$2"
  case "$pkg_mgr" in
    apt)
      dpkg -l "$name" 2>/dev/null | grep '^ii' | awk '{print $3}'
      ;;
    yum|dnf|zypper)
      rpm -q --queryformat '%{VERSION}' "$name" 2>/dev/null
      ;;
    apk)
      apk info "$name" 2>/dev/null | head -1 | sed "s/^${name}-//"
      ;;
    brew)
      brew list --versions "$name" 2>/dev/null | awk '{print $2}'
      ;;
    pkg_freebsd)
      pkg info "$name" 2>/dev/null | grep Version | awk '{print $3}'
      ;;
    pkgin)
      pkgin list 2>/dev/null | grep "^${name}-" | sed "s/^${name}-//" | awk '{print $1}'
      ;;
    pkg_add)
      pkg_info "$name" 2>/dev/null | head -1 | sed "s/^.*${name}-//"
      ;;
  esac
}

_package_install() {
  local pkg_mgr="$1" name="$2" version="$3"
  case "$pkg_mgr" in
    apt)
      apt-get update -qq &>/dev/null
      if [ -n "$version" ]; then
        apt-get install -y -qq "${name}=${version}*" &>/dev/null
      else
        apt-get install -y -qq "$name" &>/dev/null
      fi
      ;;
    yum)
      if [ -n "$version" ]; then
        yum install -y -q "${name}-${version}" &>/dev/null
      else
        yum install -y -q "$name" &>/dev/null
      fi
      ;;
    dnf)
      if [ -n "$version" ]; then
        dnf install -y -q "${name}-${version}" &>/dev/null
      else
        dnf install -y -q "$name" &>/dev/null
      fi
      ;;
    zypper)
      if [ -n "$version" ]; then
        zypper install -y --quiet "${name}=${version}" &>/dev/null
      else
        zypper install -y --quiet "$name" &>/dev/null
      fi
      ;;
    apk)
      if [ -n "$version" ]; then
        apk add --quiet "${name}=${version}" &>/dev/null
      else
        apk add --quiet "$name" &>/dev/null
      fi
      ;;
    brew)
      if [ -n "$version" ]; then
        brew install "${name}@${version}" &>/dev/null
      else
        brew install "$name" &>/dev/null
      fi
      ;;
    pkg_freebsd)
      pkg install -y "$name" &>/dev/null
      ;;
    pkgin)
      pkgin -y install "$name" &>/dev/null
      ;;
    pkg_add)
      pkg_add "$name" &>/dev/null
      ;;
  esac
}

_package_remove() {
  local pkg_mgr="$1" name="$2"
  case "$pkg_mgr" in
    apt)         apt-get remove -y -qq "$name" &>/dev/null ;;
    yum)         yum remove -y -q "$name" &>/dev/null ;;
    dnf)         dnf remove -y -q "$name" &>/dev/null ;;
    zypper)      zypper remove -y --quiet "$name" &>/dev/null ;;
    apk)         apk del --quiet "$name" &>/dev/null ;;
    brew)        brew uninstall "$name" &>/dev/null ;;
    pkg_freebsd) pkg delete -y "$name" &>/dev/null ;;
    pkgin)       pkgin -y remove "$name" &>/dev/null ;;
    pkg_add)     pkg_delete "$name" &>/dev/null ;;
  esac
}

package() {
  local name="$1"
  local desired="$2"
  shift 2

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi

  # Parse optional keyword args
  local version=""
  while [ $# -gt 0 ]; do
    case "$1" in
      version) version="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local check_start=$(_now_ms)

  # ── Detect package manager ──
  local pkg_mgr=$(_detect_pkg_manager)
  if [ -z "$pkg_mgr" ]; then
    _log_error "package/$name" "no supported package manager found (tried: apt, dnf, yum, zypper, apk, brew, pkg, pkgin, pkg_add)"
    _record_result "package/$name" "error" false "no package manager"
    return 1
  fi

  # ── Check current state ──
  local installed=false
  local current_version=""

  if _package_is_installed "$pkg_mgr" "$name"; then
    installed=true
    current_version=$(_package_get_version "$pkg_mgr" "$name")
  fi

  local check_end=$(_now_ms)
  local check_ms=$((check_end - check_start))

  # ── Evaluate desired state ──
  case "$desired" in
    installed|present)
      # Check version match if specified
      local version_ok=true
      if [ -n "$version" ] && $installed; then
        if [[ "$current_version" != *"$version"* ]]; then
          version_ok=false
        fi
      fi

      if $installed && $version_ok; then
        _log_ok "package/$name"
        _record_result "package/$name" "compliant" false "" $check_ms 0
      else
        if _should_apply; then
          local apply_start=$(_now_ms)

          _package_install "$pkg_mgr" "$name" "$version"

          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))

          if _package_is_installed "$pkg_mgr" "$name"; then
            _log_changed "package/$name" "installed"
            _record_result "package/$name" "compliant" true "installed" $check_ms $apply_ms
          else
            _log_error "package/$name" "install failed"
            _record_result "package/$name" "error" false "install failed" $check_ms $apply_ms
            return 1
          fi
        else
          _log_drift "package/$name" "not installed"
          _record_result "package/$name" "non_compliant" false "not installed" $check_ms 0
        fi
      fi
      ;;

    uninstalled|removed|absent)
      if ! $installed; then
        _log_ok "package/$name"
        _record_result "package/$name" "compliant" false "" $check_ms 0
      else
        if _should_apply; then
          local apply_start=$(_now_ms)

          _package_remove "$pkg_mgr" "$name"

          local apply_end=$(_now_ms)
          local apply_ms=$((apply_end - apply_start))

          _log_changed "package/$name" "removed"
          _record_result "package/$name" "compliant" true "removed" $check_ms $apply_ms
        else
          _log_drift "package/$name" "still installed (version: $current_version)"
          _record_result "package/$name" "non_compliant" false "installed" $check_ms 0
        fi
      fi
      ;;

    *)
      _log_error "package/$name" "unknown desired state: $desired"
      _record_result "package/$name" "error" false "unknown state: $desired"
      return 1
      ;;
  esac
}
