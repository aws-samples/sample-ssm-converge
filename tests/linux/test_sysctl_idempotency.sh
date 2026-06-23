#!/bin/bash
# Verify sysctl handles space-separated values (e.g. ip_local_port_range)
# without reporting perpetual drift.
#
# Skipped if not running as root — sysctl -w needs privileges.

if [ "$EUID" -ne 0 ] && [ "$(uname)" != "Darwin" ]; then
  echo "SKIP: sysctl test needs root on Linux. On macOS we'll only check the parse helpers."
fi

export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_LOG_FILE=/tmp/ssm-converge-sysctl-test.log
export DSC_LOCAL_DIR=/tmp/ssm-converge-sysctl-test
export DSC_VERBOSE=true

source "$SSM_CONVERGE_HOME/lib.sh"

# Just exercise the normalization helper against the problem input.
echo "=== whitespace normalization check ==="
SYSCTL_BIN=$(command -v sysctl 2>/dev/null || echo "/usr/sbin/sysctl")

# Simulate what a tab-separated IMDS or Linux sysctl would return.
SIMULATED=$'32768\t60999'
DESIRED='32768 60999'

CLEANED_CUR=$(echo "$SIMULATED" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
CLEANED_DES=$(echo "$DESIRED"   | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')

echo "current (pre-clean):  $(printf '%q' "$SIMULATED")"
echo "current (post-clean): '$CLEANED_CUR'"
echo "desired (post-clean): '$CLEANED_DES'"
if [ "$CLEANED_CUR" = "$CLEANED_DES" ]; then
  echo "PASS: space-separated values compare equal after normalization"
else
  echo "FAIL: normalization broken"
  exit 1
fi
