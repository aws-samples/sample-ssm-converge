#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: NGINX Web Server
#
# Installs and configures NGINX as a reverse proxy / static site server with:
#   - Dedicated nginx user & group (distro default)
#   - Main nginx.conf tuned for modern workloads
#   - A virtual host for example.com serving /var/www/example.com
#   - TLS certificate directory layout (certificates not generated here)
#   - Log rotation
#   - Kernel tuning for high connection counts
#
# Works on Amazon Linux 2023, RHEL/CentOS, Ubuntu/Debian. Uses the distro
# package manager and init system automatically.
#
# Run:
#   sudo DSC_MODE=enforce  DSC_PROFILE=nginx bash nginx-webserver.sh
#   sudo DSC_MODE=audit    DSC_PROFILE=nginx bash nginx-webserver.sh
#   sudo DSC_MODE=destroy  DSC_PROFILE=nginx bash nginx-webserver.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

SITE_NAME="example.com"
SITE_ROOT="/var/www/${SITE_NAME}"

# ── Kernel tuning for a web tier ──────────────────────────────────────────────

sysctl 'net.core.somaxconn'               value '65535'
sysctl 'net.ipv4.tcp_max_syn_backlog'     value '65535'
sysctl 'net.ipv4.ip_local_port_range'     value '1024 65535'
sysctl 'net.ipv4.tcp_tw_reuse'            value '1'
sysctl 'net.ipv4.tcp_fin_timeout'         value '15'

# ── Package ───────────────────────────────────────────────────────────────────

package 'nginx' installed

# ── Directory layout ──────────────────────────────────────────────────────────

directory '/etc/nginx'           present owner 'root' group 'root' mode '0755'
directory '/etc/nginx/conf.d'    present owner 'root' group 'root' mode '0755'
directory '/etc/nginx/sites-available' present owner 'root' group 'root' mode '0755'
directory '/etc/nginx/sites-enabled'   present owner 'root' group 'root' mode '0755'
directory '/etc/nginx/ssl'       present owner 'root' group 'root' mode '0700'
directory "${SITE_ROOT}"         present owner 'nginx' group 'nginx' mode '0755'
directory "${SITE_ROOT}/public"  present owner 'nginx' group 'nginx' mode '0755'
directory '/var/log/nginx'       present owner 'nginx' group 'nginx' mode '0755'

# ── Main nginx.conf ───────────────────────────────────────────────────────────

file_content '/etc/nginx/nginx.conf' owner 'root' mode '0644' notify 'reload-nginx' <<'EOF'
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections  8192;
    multi_accept        on;
    use                 epoll;
}

http {
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    server_tokens       off;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    error_log   /var/log/nginx/error.log   warn;

    gzip              on;
    gzip_vary         on;
    gzip_min_length   1024;
    gzip_types        text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*.conf;
}
EOF

# ── Virtual host for example.com ──────────────────────────────────────────────

file_content "/etc/nginx/sites-available/${SITE_NAME}.conf" owner 'root' mode '0644' notify 'reload-nginx' <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${SITE_NAME} www.${SITE_NAME};

    root ${SITE_ROOT}/public;
    index index.html index.htm;

    access_log /var/log/nginx/${SITE_NAME}.access.log main;
    error_log  /var/log/nginx/${SITE_NAME}.error.log  warn;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /healthz {
        access_log off;
        return 200 "ok\\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site by symlinking into sites-enabled.
file "/etc/nginx/sites-enabled/${SITE_NAME}.conf" present \
  content "include /etc/nginx/sites-available/${SITE_NAME}.conf;" \
  owner 'root' mode '0644' \
  notify 'reload-nginx'

# ── Default placeholder page ──────────────────────────────────────────────────

file_content "${SITE_ROOT}/public/index.html" owner 'nginx' mode '0644' <<EOF
<!DOCTYPE html>
<html>
<head><title>${SITE_NAME}</title></head>
<body><h1>It works — ${SITE_NAME}</h1></body>
</html>
EOF

# ── Log rotation ──────────────────────────────────────────────────────────────

file_content '/etc/logrotate.d/nginx' owner 'root' mode '0644' <<'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 nginx nginx
    sharedscripts
    postrotate
        [ ! -f /run/nginx.pid ] || kill -USR1 $(cat /run/nginx.pid)
    endscript
}
EOF

# ── Service ───────────────────────────────────────────────────────────────────

service 'nginx' running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────

handler 'reload-nginx' systemctl reload nginx

# ── Report ────────────────────────────────────────────────────────────────────
# Writes /var/lib/ssm-converge/latest.json and prints a summary.
# To ship the full JSON to S3:
#   get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/nginx/$(hostname)-$(date +%s).json"

report_compliance
