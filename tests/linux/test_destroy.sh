#!/bin/bash
# Verify destroy mode flips present -> absent and actually removes resources.

rm -rf /tmp/ssm-converge-test /tmp/ssm-converge-testfiles
bash "$(dirname "$0")/test_local.sh" > /dev/null 2>&1

echo "=== Before destroy ==="
ls -la /tmp/ssm-converge-testfiles/myapp 2>&1 | head -5
echo ""

export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_MODE="destroy"
export DSC_PROFILE="local-test"
export DSC_LOCAL_DIR="/tmp/ssm-converge-test"
export DSC_VERBOSE="true"

source "${SSM_CONVERGE_HOME}/lib.sh"

directory '/tmp/ssm-converge-testfiles/myapp' present
file '/tmp/ssm-converge-testfiles/myapp/config/app.conf' present content 'port=8080'

report_compliance

echo ""
echo "=== After destroy ==="
ls -la /tmp/ssm-converge-testfiles/myapp 2>&1 | head -5 || true
