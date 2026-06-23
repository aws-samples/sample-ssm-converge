#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Web Server Baseline
#
# Ensures an NGINX web server is properly configured with:
# - Required packages installed, unnecessary packages removed
# - Configuration files in place
# - Proper directory structure and permissions
# - Service running and enabled
# - Kernel tuning for web workloads
# - Hosts entries for internal services
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=webserver-baseline bash webserver-baseline.sh
#   sudo DSC_MODE=audit DSC_PROFILE=webserver-baseline bash webserver-baseline.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

# ── System Configuration ──────────────────────────────────────────────────────

timezone 'UTC'
locale 'en_US.UTF-8'

# ── Kernel Tuning ─────────────────────────────────────────────────────────────

sysctl 'net.core.somaxconn' value '65535'
sysctl 'net.ipv4.tcp_max_syn_backlog' value '65535'
sysctl 'net.ipv4.ip_local_port_range' value '1024 65535'
sysctl 'vm.swappiness' value '10'

# ── Users & Groups ────────────────────────────────────────────────────────────

group 'www-data' present
user 'www-deploy' present \
  shell '/bin/bash' \
  groups 'www-data' \
  home '/home/www-deploy'

# ── Packages ──────────────────────────────────────────────────────────────────

package 'nginx' installed
package 'curl' installed
package 'jq' installed
package 'telnet' uninstalled
package 'ftp' uninstalled

# ── Directories ───────────────────────────────────────────────────────────────

directory '/var/www/app' present \
  owner 'www-deploy' \
  group 'www-data' \
  mode '0755'

directory '/var/www/app/public' present \
  owner 'www-deploy' \
  group 'www-data' \
  mode '0755'

directory '/var/log/nginx' present \
  owner 'root' \
  group 'www-data' \
  mode '0750'

# ── Configuration Files ───────────────────────────────────────────────────────

file '/etc/nginx/nginx.conf' present \
  source 's3://DOC-EXAMPLE-BUCKET/nginx/nginx.conf' \
  owner 'root' \
  mode '0644' \
  notify 'reload-nginx'

file_content '/var/www/app/public/health.html' owner 'www-deploy' mode '0644' <<'EOF'
<!DOCTYPE html>
<html><body><h1>OK</h1></body></html>
EOF

# ── Line-in-file (surgical config edits) ──────────────────────────────────────

line_in_file '/etc/security/limits.conf' present \
  line 'www-data soft nofile 65535' \
  match '^www-data.*soft.*nofile'

line_in_file '/etc/security/limits.conf' present \
  line 'www-data hard nofile 65535' \
  match '^www-data.*hard.*nofile'

# ── Hosts ─────────────────────────────────────────────────────────────────────

host_entry '10.0.1.10' present hostname 'api.internal'
host_entry '10.0.1.20' present hostname 'db-primary.internal'
host_entry '10.0.1.21' present hostname 'db-replica.internal'
host_entry '10.0.1.30' present hostname 'cache.internal'

# ── Cron Jobs ─────────────────────────────────────────────────────────────────

cron 'logrotate-nginx' present \
  schedule '0 0 * * *' \
  command '/usr/sbin/logrotate /etc/logrotate.d/nginx'

cron 'health-check' present \
  schedule '*/5 * * * *' \
  command 'curl -sf http://localhost/health.html > /dev/null || logger -t nginx-health "FAILED"'

# ── Services ──────────────────────────────────────────────────────────────────

service 'nginx' running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────

handler 'reload-nginx' systemctl reload nginx

# ── Report ────────────────────────────────────────────────────────────────────
# Writes /var/lib/ssm-converge/latest.json and prints a one-line summary.
# Pipe get_report_json anywhere you want the full JSON (S3, API, etc.):
#   get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname).json"

report_compliance
