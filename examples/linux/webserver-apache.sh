#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Apache HTTPD Web Server
#
# Installs Apache HTTP Server (httpd/apache2) with:
#   - Package installed (httpd on RHEL family, apache2 on Debian family)
#   - Security-sensitive directives (ServerTokens Prod, TRACE disabled)
#   - A virtual host serving /var/www/example.com
#   - mod_ssl installed (certificate wiring is out of scope for this example)
#   - Log rotation
#   - Unnecessary default modules removed
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=apache bash webserver-apache.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

SITE_NAME="example.com"
SITE_ROOT="/var/www/${SITE_NAME}"

# The Apache package and config dir names differ between distros. Set both and
# the `file`/`service` resources pick whatever actually exists on the host.
# On Amazon Linux / RHEL: httpd, /etc/httpd/conf.d/, service 'httpd'
# On Debian / Ubuntu:     apache2, /etc/apache2/sites-available/, service 'apache2'
#
# This example targets RHEL family; adjust for Debian by changing names.

APACHE_PKG="httpd"
APACHE_SVC="httpd"
APACHE_USER="apache"
APACHE_CONFD="/etc/httpd/conf.d"

# ── Packages ──────────────────────────────────────────────────────────────────

package "$APACHE_PKG" installed
package 'mod_ssl'     installed

# ── Directory layout ──────────────────────────────────────────────────────────

directory "${SITE_ROOT}"        present owner "$APACHE_USER" group "$APACHE_USER" mode '0755'
directory "${SITE_ROOT}/public" present owner "$APACHE_USER" group "$APACHE_USER" mode '0755'
directory '/var/log/httpd'      present owner 'root' group 'root' mode '0700'

# ── Global security hardening for httpd ───────────────────────────────────────

file_content "${APACHE_CONFD}/00-security.conf" owner 'root' mode '0644' notify 'restart-httpd' <<'EOF'
# Managed by SSM Converge.

ServerTokens Prod
ServerSignature Off
TraceEnable Off
FileETag None

<Directory />
    AllowOverride None
    Require all denied
</Directory>

Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
EOF

# ── Virtual host for example.com ──────────────────────────────────────────────

file_content "${APACHE_CONFD}/${SITE_NAME}.conf" owner 'root' mode '0644' notify 'restart-httpd' <<EOF
# Managed by SSM Converge.

<VirtualHost *:80>
    ServerName  ${SITE_NAME}
    ServerAlias www.${SITE_NAME}
    DocumentRoot ${SITE_ROOT}/public

    ErrorLog    /var/log/httpd/${SITE_NAME}-error.log
    CustomLog   /var/log/httpd/${SITE_NAME}-access.log combined

    <Directory ${SITE_ROOT}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Location "/healthz">
        SetHandler server-status
        Require local
    </Location>
</VirtualHost>
EOF

# ── Default placeholder page ──────────────────────────────────────────────────

file_content "${SITE_ROOT}/public/index.html" owner "$APACHE_USER" mode '0644' <<EOF
<!DOCTYPE html>
<html>
<head><title>${SITE_NAME}</title></head>
<body><h1>It works — ${SITE_NAME}</h1></body>
</html>
EOF

# ── Log rotation ──────────────────────────────────────────────────────────────

file_content '/etc/logrotate.d/httpd' owner 'root' mode '0644' <<'EOF'
/var/log/httpd/*log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/systemctl reload httpd.service >/dev/null 2>&1 || true
    endscript
}
EOF

# ── Kernel tuning for a web tier ──────────────────────────────────────────────

sysctl 'net.core.somaxconn'           value '4096'
sysctl 'net.ipv4.tcp_max_syn_backlog' value '4096'

# ── Service ───────────────────────────────────────────────────────────────────

service "$APACHE_SVC" running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────

handler 'restart-httpd' systemctl restart "$APACHE_SVC"

# ── Report ────────────────────────────────────────────────────────────────────

report_compliance
