#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Local Test (runs on macOS/Linux without root)
# Tests: file, directory, line_in_file, host_entry (custom path), timezone check
# ═══════════════════════════════════════════════════════════════════════════════

# Point to our source tree
export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_MODE="enforce"
export DSC_PROFILE="local-test"
export DSC_LOCAL_DIR="/tmp/ssm-converge-test"
export DSC_VERBOSE="true"

# Clean up from previous runs
rm -rf /tmp/ssm-converge-test
rm -rf /tmp/ssm-converge-testfiles

mkdir -p /tmp/ssm-converge-testfiles

source "${SSM_CONVERGE_HOME}/lib.sh"

# ── Test: directory ───────────────────────────────────────────────────────────

directory '/tmp/ssm-converge-testfiles/myapp' present
directory '/tmp/ssm-converge-testfiles/myapp/logs' present
directory '/tmp/ssm-converge-testfiles/myapp/config' present

# ── Test: file with content ───────────────────────────────────────────────────

file '/tmp/ssm-converge-testfiles/myapp/config/app.conf' present \
  content 'port=8080'

# ── Test: file_content (heredoc) ──────────────────────────────────────────────

file_content '/tmp/ssm-converge-testfiles/myapp/config/settings.yml' <<'EOF'
app:
  name: myapp
  port: 8080
  workers: 4
EOF

# ── Test: line_in_file ────────────────────────────────────────────────────────

# First create a file to edit
echo "# SSH Config Test" > /tmp/ssm-converge-testfiles/sshd_config
echo "PermitRootLogin yes" >> /tmp/ssm-converge-testfiles/sshd_config
echo "PasswordAuthentication yes" >> /tmp/ssm-converge-testfiles/sshd_config

line_in_file '/tmp/ssm-converge-testfiles/sshd_config' present \
  line 'PermitRootLogin no' \
  match '^PermitRootLogin'

line_in_file '/tmp/ssm-converge-testfiles/sshd_config' present \
  line 'PasswordAuthentication no' \
  match '^PasswordAuthentication'

# ── Test: host_entry (custom hosts file) ──────────────────────────────────────

echo "127.0.0.1 localhost" > /tmp/ssm-converge-testfiles/hosts
host_entry '10.0.1.5' present hostname 'myapp.internal' hosts_file '/tmp/ssm-converge-testfiles/hosts'
host_entry '10.0.1.6' present hostname 'mydb.internal' hosts_file '/tmp/ssm-converge-testfiles/hosts'

# ── Test: file absent ─────────────────────────────────────────────────────────

touch /tmp/ssm-converge-testfiles/delete_me.txt
file '/tmp/ssm-converge-testfiles/delete_me.txt' absent

# ── Test: directory absent ────────────────────────────────────────────────────

mkdir -p /tmp/ssm-converge-testfiles/remove_this
directory '/tmp/ssm-converge-testfiles/remove_this' absent

# ── Report ────────────────────────────────────────────────────────────────────

report_compliance

echo ""
echo "═══ Verification ═══"
echo ""
echo "Directory created:"
ls -la /tmp/ssm-converge-testfiles/myapp/config/
echo ""
echo "Config file content:"
cat /tmp/ssm-converge-testfiles/myapp/config/app.conf
echo ""
echo "Settings file content:"
cat /tmp/ssm-converge-testfiles/myapp/config/settings.yml
echo ""
echo "SSH config after line_in_file:"
cat /tmp/ssm-converge-testfiles/sshd_config
echo ""
echo "Hosts file after host_entry:"
cat /tmp/ssm-converge-testfiles/hosts
echo ""
echo "File deleted:"
ls /tmp/ssm-converge-testfiles/delete_me.txt 2>&1
echo ""
echo "Directory deleted:"
ls -d /tmp/ssm-converge-testfiles/remove_this 2>&1
echo ""
echo "Local compliance report:"
cat "$DSC_LOCAL_DIR/latest.json" | python3 -m json.tool 2>/dev/null || cat "$DSC_LOCAL_DIR/latest.json"
