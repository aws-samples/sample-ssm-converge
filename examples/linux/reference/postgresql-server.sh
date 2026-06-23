#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: PostgreSQL 15 Server
#
# Installs PostgreSQL 15 and brings the server to a known state:
#   - Package install via distro package manager
#   - Data directory at /var/lib/pgsql/15/data (or distro equivalent)
#   - postgresql.conf tuned for a small/medium workload
#   - pg_hba.conf restricted to the VPC CIDR
#   - listen_addresses = '*' with firewalling expected upstream
#   - Enabled and running service
#
# Works on Amazon Linux 2023 (postgresql15-server), RHEL 9 (postgresql-server),
# Ubuntu (postgresql-15). Tweak the package name per distro.
#
# Run:
#   sudo DSC_MODE=enforce DSC_PROFILE=postgres bash postgresql-server.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

PG_VERSION="15"
PG_DATA="/var/lib/pgsql/${PG_VERSION}/data"
PG_USER="postgres"
VPC_CIDR="10.0.0.0/16"

# ── Packages ──────────────────────────────────────────────────────────────────
# The package name varies by distro; pick the one that matches your base AMI.
#   Amazon Linux 2023:  postgresql15-server, postgresql15-contrib
#   RHEL 9:             postgresql-server, postgresql-contrib (via PGDG repo)
#   Debian/Ubuntu:      postgresql-15, postgresql-contrib-15

package 'postgresql15-server'  installed
package 'postgresql15-contrib' installed

# ── User & data directory ─────────────────────────────────────────────────────
# The postgres user is created by the package; we just assert the data dir.

directory "$PG_DATA" present owner "$PG_USER" group "$PG_USER" mode '0700'

# ── Initialize the cluster if it hasn't been yet ──────────────────────────────
# We use a stamp file under /var/lib/ssm-converge as a sentinel. When the stamp
# is absent, the notify fires the 'initdb' handler, which itself is idempotent
# (postgresql-setup --initdb bails cleanly on an already-initialized cluster).

file '/var/lib/ssm-converge/.postgres-initialized' present \
  content "postgres-${PG_VERSION}-initialized" \
  owner 'root' mode '0600' \
  notify 'initdb'

# ── postgresql.conf ───────────────────────────────────────────────────────────

file_content "${PG_DATA}/postgresql.conf" owner "$PG_USER" group "$PG_USER" mode '0600' notify 'restart-postgres' <<'EOF'
# Managed by SSM Converge.

listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 512MB
effective_cache_size = 1536MB
work_mem = 8MB
maintenance_work_mem = 128MB
wal_level = replica
max_wal_size = 2GB
min_wal_size = 80MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200

log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%m [%p] %q%u@%d '
log_min_duration_statement = 1000
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on

shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
EOF

# ── pg_hba.conf ───────────────────────────────────────────────────────────────

file_content "${PG_DATA}/pg_hba.conf" owner "$PG_USER" group "$PG_USER" mode '0600' notify 'reload-postgres' <<EOF
# Managed by SSM Converge.
# TYPE   DATABASE  USER          ADDRESS        METHOD

local    all       all                          peer
host     all       all           127.0.0.1/32   scram-sha-256
host     all       all           ::1/128        scram-sha-256
host     all       all           ${VPC_CIDR}    scram-sha-256
EOF

# ── Kernel tuning for PostgreSQL ──────────────────────────────────────────────

sysctl 'kernel.shmmax' value '17179869184'
sysctl 'vm.overcommit_memory' value '2'
sysctl 'vm.swappiness' value '1'
sysctl 'vm.dirty_ratio' value '15'
sysctl 'vm.dirty_background_ratio' value '5'

# ── Service ───────────────────────────────────────────────────────────────────

service "postgresql-${PG_VERSION}" running enabled

# ── Handlers ──────────────────────────────────────────────────────────────────

# Initialize the cluster. Safe to rerun — postgresql-setup skips if initialized.
handler 'initdb' bash -c "command -v postgresql-setup >/dev/null && postgresql-setup --initdb --unit postgresql-${PG_VERSION} 2>/dev/null || /usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup initdb 2>/dev/null || su - ${PG_USER} -c '/usr/pgsql-${PG_VERSION}/bin/initdb -D ${PG_DATA}'"
handler 'reload-postgres' systemctl reload "postgresql-${PG_VERSION}"
handler 'restart-postgres' systemctl restart "postgresql-${PG_VERSION}"

# ── Report ────────────────────────────────────────────────────────────────────

report_compliance
