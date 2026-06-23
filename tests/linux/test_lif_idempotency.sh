#!/bin/bash
# Reproduce the line_in_file idempotency bug.
# First run: 4 lines replaced. Second run should show all 4 as compliant.

export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_LOG_FILE=/tmp/ssm-converge-lif-test.log
export DSC_LOCAL_DIR=/tmp/ssm-converge-lif-test
export DSC_VERBOSE=true

rm -f /tmp/test_sshd_config
cat > /tmp/test_sshd_config <<'EOF'
# SSH config
#PermitRootLogin prohibit-password
#PasswordAuthentication yes
#X11Forwarding yes
#MaxAuthTries 6
EOF

source "$SSM_CONVERGE_HOME/lib.sh"

echo "=== Run 1 ==="
line_in_file '/tmp/test_sshd_config' present line 'PermitRootLogin no' match '^#?PermitRootLogin'
line_in_file '/tmp/test_sshd_config' present line 'PasswordAuthentication no' match '^#?PasswordAuthentication'
line_in_file '/tmp/test_sshd_config' present line 'X11Forwarding no' match '^#?X11Forwarding'
line_in_file '/tmp/test_sshd_config' present line 'MaxAuthTries 3' match '^#?MaxAuthTries'
echo ""
echo "--- file after run 1 ---"
cat /tmp/test_sshd_config
echo ""
echo "=== Run 2 (should be all compliant, 0 changed) ==="
line_in_file '/tmp/test_sshd_config' present line 'PermitRootLogin no' match '^#?PermitRootLogin'
line_in_file '/tmp/test_sshd_config' present line 'PasswordAuthentication no' match '^#?PasswordAuthentication'
line_in_file '/tmp/test_sshd_config' present line 'X11Forwarding no' match '^#?X11Forwarding'
line_in_file '/tmp/test_sshd_config' present line 'MaxAuthTries 3' match '^#?MaxAuthTries'
