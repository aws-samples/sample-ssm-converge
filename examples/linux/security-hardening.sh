#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Security Hardening (CIS-inspired)
#
# Applies common security hardening settings:
# - SSH hardening
# - Kernel security parameters
# - Remove unnecessary packages
# - File permission fixes
# - Disable unused services
#
# Run:
#   sudo DSC_MODE=audit DSC_PROFILE=security-hardening bash security-hardening.sh
#   sudo DSC_MODE=enforce DSC_PROFILE=security-hardening bash security-hardening.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

# ── SSH Hardening ─────────────────────────────────────────────────────────────

line_in_file '/etc/ssh/sshd_config' present \
  line 'PermitRootLogin no' \
  match '^#?PermitRootLogin' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'PasswordAuthentication no' \
  match '^#?PasswordAuthentication' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'X11Forwarding no' \
  match '^#?X11Forwarding' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'MaxAuthTries 3' \
  match '^#?MaxAuthTries' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'ClientAliveInterval 300' \
  match '^#?ClientAliveInterval' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'ClientAliveCountMax 2' \
  match '^#?ClientAliveCountMax' \
  notify 'restart-sshd'

# ── Kernel Security Parameters ────────────────────────────────────────────────

sysctl 'net.ipv4.conf.all.send_redirects' value '0'
sysctl 'net.ipv4.conf.default.send_redirects' value '0'
sysctl 'net.ipv4.conf.all.accept_redirects' value '0'
sysctl 'net.ipv4.conf.default.accept_redirects' value '0'
sysctl 'net.ipv4.conf.all.accept_source_route' value '0'
sysctl 'net.ipv4.conf.default.accept_source_route' value '0'
sysctl 'net.ipv4.conf.all.log_martians' value '1'
sysctl 'net.ipv4.icmp_echo_ignore_broadcasts' value '1'
sysctl 'net.ipv4.icmp_ignore_bogus_error_responses' value '1'
sysctl 'net.ipv4.tcp_syncookies' value '1'
sysctl 'kernel.randomize_va_space' value '2'

# ── Remove Unnecessary Packages ───────────────────────────────────────────────

package 'telnet' uninstalled
package 'ftp' uninstalled
package 'rsh' uninstalled
package 'talk' uninstalled
package 'xinetd' uninstalled

# ── File Permissions ──────────────────────────────────────────────────────────

file '/etc/passwd' present owner 'root' group 'root' mode '0644'
file '/etc/shadow' present owner 'root' group 'root' mode '0600'
file '/etc/group' present owner 'root' group 'root' mode '0644'
file '/etc/gshadow' present owner 'root' group 'root' mode '0600'
file '/etc/crontab' present owner 'root' group 'root' mode '0600'

directory '/etc/cron.d' present owner 'root' group 'root' mode '0700'
directory '/etc/cron.daily' present owner 'root' group 'root' mode '0700'
directory '/etc/cron.hourly' present owner 'root' group 'root' mode '0700'
directory '/etc/cron.weekly' present owner 'root' group 'root' mode '0700'
directory '/etc/cron.monthly' present owner 'root' group 'root' mode '0700'

# ── Disable Unused Services ───────────────────────────────────────────────────

service 'avahi-daemon' stopped disabled
service 'cups' stopped disabled

# ── Ensure Required Services ──────────────────────────────────────────────────

service 'sshd' running enabled
service 'auditd' running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────

handler 'restart-sshd' systemctl restart sshd

# ── Report ────────────────────────────────────────────────────────────────────
# For a full compliance report, run via: ssm-converge comply security-hardening.sh
# Or ship the JSON to your compliance system:
#   get_report_json | curl -X POST -H 'Content-Type: application/json' --data-binary @- https://compliance.internal/api/v1/report

report_compliance
