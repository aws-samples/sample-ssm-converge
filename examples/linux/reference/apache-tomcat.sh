#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Apache Tomcat 9
#
# Installs Apache Tomcat 9 from the Apache archive (no distro package), sets up:
#   - Dedicated 'tomcat' user and group, non-login
#   - JDK 17 (Amazon Corretto / default OpenJDK)
#   - CATALINA_HOME at /opt/tomcat, CATALINA_BASE the same
#   - setenv.sh with JVM sizing and Java options
#   - systemd service unit
#   - Host entries for a backend DB
#
# This is a self-contained installation, not the distro package. Adjust
# TOMCAT_VERSION as new versions come out.
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=tomcat bash apache-tomcat.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

TOMCAT_VERSION="9.0.87"
TOMCAT_HOME="/opt/tomcat"
TOMCAT_USER="tomcat"

# ── Java runtime ──────────────────────────────────────────────────────────────
# Pick whichever JDK package your distro provides. java-17-amazon-corretto
# on Amazon Linux 2023, openjdk-17-jdk on Debian/Ubuntu.

package 'java-17-amazon-corretto-headless' installed

# ── User & group ──────────────────────────────────────────────────────────────

group "$TOMCAT_USER" present
user  "$TOMCAT_USER" present \
  shell '/usr/sbin/nologin' \
  home  "$TOMCAT_HOME" \
  system true

# ── Directory layout ──────────────────────────────────────────────────────────

directory "$TOMCAT_HOME"         present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0755'
directory "${TOMCAT_HOME}/logs"  present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0750'
directory "${TOMCAT_HOME}/temp"  present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0750'
directory "${TOMCAT_HOME}/work"  present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0750'
directory "${TOMCAT_HOME}/webapps" present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0755'

# ── Tomcat distribution tarball ──────────────────────────────────────────────
# We drop a pre-downloaded tarball in S3 and pull it with the `file` resource.
# Adjust the S3 path to your environment. This keeps the config idempotent:
# the tarball is only re-downloaded when the hash changes.

file "${TOMCAT_HOME}/apache-tomcat-${TOMCAT_VERSION}.tar.gz" present \
  source "s3://DOC-EXAMPLE-BUCKET/tomcat/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
  owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0644' \
  notify 'extract-tomcat'

# ── JVM environment ──────────────────────────────────────────────────────────

directory "${TOMCAT_HOME}/bin" present owner "$TOMCAT_USER" group "$TOMCAT_USER" mode '0755'

file_content "${TOMCAT_HOME}/bin/setenv.sh" owner "$TOMCAT_USER" mode '0750' notify 'restart-tomcat' <<'EOF'
#!/bin/bash
# Tomcat JVM options — managed by SSM Converge.

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-amazon-corretto}"
export CATALINA_OPTS="-server \
  -Xms1g -Xmx2g \
  -XX:+UseG1GC -XX:MaxGCPauseMillis=200 \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/opt/tomcat/logs \
  -Djava.awt.headless=true \
  -Djava.net.preferIPv4Stack=true \
  -Dfile.encoding=UTF-8"
export UMASK=0027
EOF

# ── systemd unit ──────────────────────────────────────────────────────────────

file_content '/etc/systemd/system/tomcat.service' owner 'root' mode '0644' notify 'reload-systemd' <<EOF
[Unit]
Description=Apache Tomcat 9
After=network.target

[Service]
Type=forking
User=${TOMCAT_USER}
Group=${TOMCAT_USER}
UMask=0027

Environment="JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto"
Environment="CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid"
Environment="CATALINA_HOME=${TOMCAT_HOME}"
Environment="CATALINA_BASE=${TOMCAT_HOME}"

ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh

Restart=on-failure
RestartSec=10

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${TOMCAT_HOME}/logs ${TOMCAT_HOME}/temp ${TOMCAT_HOME}/work ${TOMCAT_HOME}/webapps

[Install]
WantedBy=multi-user.target
EOF

# ── Backend host entries (example) ────────────────────────────────────────────

host_entry '10.0.1.20' present hostname 'db-primary.internal'
host_entry '10.0.1.21' present hostname 'db-replica.internal'

# ── Log rotation ──────────────────────────────────────────────────────────────

file_content '/etc/logrotate.d/tomcat' owner 'root' mode '0644' <<EOF
${TOMCAT_HOME}/logs/*.log ${TOMCAT_HOME}/logs/*.out {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
    create 0640 ${TOMCAT_USER} ${TOMCAT_USER}
}
EOF

# ── Service ───────────────────────────────────────────────────────────────────

service 'tomcat' running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────
# The 'extract-tomcat' handler unpacks the tarball into CATALINA_HOME if the
# bin/ dir doesn't exist yet. Safe to run repeatedly: tar overwrites with
# --same-owner and we strip the top-level directory.

handler 'extract-tomcat' bash -c "test -x ${TOMCAT_HOME}/bin/catalina.sh || tar -xzf ${TOMCAT_HOME}/apache-tomcat-${TOMCAT_VERSION}.tar.gz -C ${TOMCAT_HOME} --strip-components=1 && chown -R ${TOMCAT_USER}:${TOMCAT_USER} ${TOMCAT_HOME}"
handler 'reload-systemd' systemctl daemon-reload
handler 'restart-tomcat' systemctl restart tomcat

# ── Report ────────────────────────────────────────────────────────────────────

report_compliance
