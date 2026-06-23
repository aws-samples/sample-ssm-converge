#!/bin/bash
# Verify true idempotency: run test_local.sh, then re-declare a subset and
# assert that 0 changes happen on the second run.

rm -rf /tmp/ssm-converge-test /tmp/ssm-converge-testfiles
bash "$(dirname "$0")/test_local.sh" > /dev/null 2>&1

export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_MODE="enforce"
export DSC_PROFILE="local-test"
export DSC_LOCAL_DIR="/tmp/ssm-converge-test"
export DSC_VERBOSE="true"

source "${SSM_CONVERGE_HOME}/lib.sh"

directory '/tmp/ssm-converge-testfiles/myapp' present
directory '/tmp/ssm-converge-testfiles/myapp/logs' present
file '/tmp/ssm-converge-testfiles/myapp/config/app.conf' present content 'port=8080'
host_entry '10.0.1.5' present hostname 'myapp.internal' hosts_file '/tmp/ssm-converge-testfiles/hosts'

report_compliance
