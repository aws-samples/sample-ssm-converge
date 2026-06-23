#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Post-Build OS Configuration
#
# The canonical steps every newly provisioned EC2 instance should go through
# before it joins the fleet. Apply this once in your AMI build pipeline, or
# as the first State Manager association on boot — or both.
#
# What it covers:
#   1. System identity              — timezone, locale, hostname /etc/hosts
#   2. Baseline packages            — common utilities every box should have
#   3. Agents & monitoring          — CloudWatch agent, SSM tooling
#   4. Users & sudo                 — operator group, deploy user
#   5. SSH hardening                — sane defaults before anything ships
#   6. Kernel & limits              — file descriptors, swappiness
#   7. Audit logging                — auditd running
#   8. Chrony (time sync)           — required for TLS, Kerberos, logs
#   9. Unattended security updates  — yum-cron / unattended-upgrades
#  10. MOTD + banner                — operational ownership marker
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=os-baseline bash os-post-build.sh
#   sudo DSC_MODE=audit   DSC_PROFILE=os-baseline bash os-post-build.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

# ── 1. System identity ────────────────────────────────────────────────────────

timezone 'UTC'
locale   'en_US.UTF-8'

host_entry '127.0.0.1' present hostname 'localhost localhost.localdomain'
host_entry '::1'       present hostname 'localhost6 localhost6.localdomain6'

# ── 2. Baseline packages every box should have ────────────────────────────────
# ── 2. Baseline packages every box should have ────────────────────────────────
# Package names below work on Amazon Linux 2023. Some notes:
#   - `curl` on AL2023 conflicts with the pre-installed `curl-minimal`. Don't
#     declare both; stick with whatever the AMI ships unless you specifically
#     need the full curl feature set.
#   - `vim` doesn't exist as a package on AL2023 — use `vim-enhanced` instead.
#   - `audit` pulls in auditd; note that auditd needs a rules file to start.

package 'wget'         installed
package 'jq'           installed
package 'vim-enhanced' installed
package 'rsync'        installed
package 'lsof'         installed
package 'bind-utils'   installed       # dig, nslookup
package 'tcpdump'      installed
package 'htop'         installed
package 'unzip'        installed
package 'bzip2'        installed
package 'chrony'       installed

# Remove legacy / unwanted
package 'telnet'    uninstalled
package 'ftp'       uninstalled
package 'rsh'       uninstalled
package 'talk'      uninstalled
package 'xinetd'    uninstalled

# ── 3. Agents & monitoring ────────────────────────────────────────────────────
# SSM Agent is baked into AWS AMIs; this is just the assertion.
# The CloudWatch Agent is installed but NOT started here — starting it requires
# a config file (handled by your org's CloudWatch config pipeline, Parameter
# Store, or a separate SSM document). Writing the config is out of scope for
# this OS baseline.

package 'amazon-ssm-agent'        installed
package 'amazon-cloudwatch-agent' installed

service 'amazon-ssm-agent' running enabled

# ── 4. Users, groups, sudo ────────────────────────────────────────────────────

group 'operators' present
user  'deploy'    present \
  shell  '/bin/bash' \
  groups 'operators,wheel' \
  home   '/home/deploy'

file_content '/etc/sudoers.d/90-operators' owner 'root' mode '0440' <<'EOF'
# Managed by SSM Converge.
%operators ALL=(ALL) NOPASSWD: /bin/systemctl, /usr/bin/journalctl, /bin/cat, /usr/bin/tail
EOF

# ── 5. SSH hardening ──────────────────────────────────────────────────────────

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

# ── 6. Kernel tuning & limits ─────────────────────────────────────────────────

sysctl 'vm.swappiness'                          value '10'
sysctl 'fs.file-max'                            value '2097152'
sysctl 'net.core.somaxconn'                     value '4096'
sysctl 'net.ipv4.tcp_syncookies'                value '1'
sysctl 'net.ipv4.conf.all.send_redirects'       value '0'
sysctl 'net.ipv4.conf.default.send_redirects'   value '0'
sysctl 'net.ipv4.conf.all.accept_redirects'     value '0'
sysctl 'net.ipv4.conf.default.accept_redirects' value '0'
sysctl 'net.ipv4.conf.all.accept_source_route'  value '0'
sysctl 'net.ipv4.conf.all.log_martians'         value '1'
sysctl 'kernel.randomize_va_space'              value '2'

line_in_file '/etc/security/limits.conf' present \
  line '* soft nofile 65535' \
  match '^\*[[:space:]]+soft[[:space:]]+nofile'

line_in_file '/etc/security/limits.conf' present \
  line '* hard nofile 65535' \
  match '^\*[[:space:]]+hard[[:space:]]+nofile'

# ── 7. Audit logging ──────────────────────────────────────────────────────────

package 'audit'   installed
service 'auditd'  running enabled

# ── 8. Time sync (chrony) ─────────────────────────────────────────────────────

file_content '/etc/chrony.conf' owner 'root' mode '0644' notify 'restart-chronyd' <<'EOF'
# Managed by SSM Converge.
# Amazon Time Sync Service — available on all EC2 instances.

server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4
pool 2.amazon.pool.ntp.org iburst

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
leapsectz right/UTC
EOF

service 'chronyd' running enabled

# ── 9. Unattended security updates (Amazon Linux / RHEL) ──────────────────────
# On Amazon Linux 2023 the dnf-automatic package handles this.

package 'dnf-automatic' installed

file_content '/etc/dnf/automatic.conf' owner 'root' mode '0644' notify 'restart-dnf-automatic' <<'EOF'
# Managed by SSM Converge.
[commands]
upgrade_type = security
random_sleep = 300
network_online_timeout = 60
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[base]
debuglevel = 1
EOF

service 'dnf-automatic.timer' running enabled

# ── 10. MOTD + issue banner ───────────────────────────────────────────────────

file_content '/etc/motd' owner 'root' mode '0644' <<EOF
***************************************************************
 This system is managed by SSM Converge.
 Manual changes will be reverted on the next convergence run.

 Owner:    platform-team@example.com
 Profile:  ${DSC_PROFILE}
***************************************************************
EOF

file_content '/etc/issue.net' owner 'root' mode '0644' <<'EOF'
WARNING: Unauthorized access to this system is prohibited and
will be prosecuted by law. By accessing this system, you
consent to monitoring for authorized uses only.
EOF

# ── Cron: remove stale /tmp files nightly ─────────────────────────────────────

cron 'tmp-cleanup' present \
  schedule '15 2 * * *' \
  command  'find /tmp -type f -atime +14 -delete'

# ── Handlers ──────────────────────────────────────────────────────────────────

handler 'restart-sshd'          systemctl restart sshd
handler 'restart-chronyd'       systemctl restart chronyd
handler 'restart-dnf-automatic' systemctl restart dnf-automatic.timer

# ── Report ────────────────────────────────────────────────────────────────────
# For a full pass/fail report, invoke via:
#   ssm-converge comply examples/os-post-build.sh

report_compliance
