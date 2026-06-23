#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Application Deployment
#
# Sets up a Node.js application with:
# - Application user and group
# - Directory structure
# - Environment configuration
# - Systemd service unit
# - Log rotation
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=myapp bash app-deploy.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

APP_NAME="myapp"
APP_USER="myapp"
APP_DIR="/opt/${APP_NAME}"
APP_PORT="3000"

# ── User & Group ──────────────────────────────────────────────────────────────

group "$APP_USER" present
user "$APP_USER" present \
  shell '/usr/sbin/nologin' \
  home "$APP_DIR" \
  system true

# ── Directory Structure ───────────────────────────────────────────────────────

directory "$APP_DIR" present owner "$APP_USER" group "$APP_USER" mode '0755'
directory "${APP_DIR}/current" present owner "$APP_USER" group "$APP_USER" mode '0755'
directory "${APP_DIR}/shared" present owner "$APP_USER" group "$APP_USER" mode '0755'
directory "${APP_DIR}/shared/logs" present owner "$APP_USER" group "$APP_USER" mode '0755'
directory "${APP_DIR}/shared/config" present owner "$APP_USER" group "$APP_USER" mode '0750'

# ── Environment Configuration ─────────────────────────────────────────────────

file_content "${APP_DIR}/shared/config/.env" owner "$APP_USER" mode '0600' <<EOF
NODE_ENV=production
PORT=${APP_PORT}
LOG_LEVEL=info
DB_HOST=db-primary.internal
DB_PORT=5432
DB_NAME=${APP_NAME}_production
REDIS_URL=redis://cache.internal:6379
EOF

# ── Systemd Service Unit ──────────────────────────────────────────────────────

file_content '/etc/systemd/system/myapp.service' owner 'root' mode '0644' <<EOF
[Unit]
Description=MyApp Node.js Application
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}/current
EnvironmentFile=${APP_DIR}/shared/config/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10
StandardOutput=append:${APP_DIR}/shared/logs/app.log
StandardError=append:${APP_DIR}/shared/logs/error.log

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${APP_DIR}/shared/logs

[Install]
WantedBy=multi-user.target
EOF

# ── Log Rotation ──────────────────────────────────────────────────────────────

file_content '/etc/logrotate.d/myapp' owner 'root' mode '0644' <<EOF
${APP_DIR}/shared/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# ── Hosts for Internal Services ───────────────────────────────────────────────

host_entry '10.0.1.20' present hostname 'db-primary.internal'
host_entry '10.0.1.30' present hostname 'cache.internal'

# ── Service ───────────────────────────────────────────────────────────────────

service "$APP_NAME" running enabled

# ── Report ────────────────────────────────────────────────────────────────────

report_compliance

# Ship full report to an S3 audit lake (optional):
#   get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/${APP_NAME}/$(hostname)-$(date +%s).json"
