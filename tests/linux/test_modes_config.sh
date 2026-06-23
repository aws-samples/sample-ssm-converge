#!/bin/bash
# Test configuration used to exercise all four SSM Converge modes on EC2.
# Self-contained: no external artifacts, no handlers that hit the network.

source /opt/ssm-converge/lib.sh

# Packages
package 'jq'     installed
package 'telnet' uninstalled

# Directories
directory '/opt/modes-test'         present owner root mode 0755
directory '/opt/modes-test/config'  present owner root mode 0755
directory '/opt/modes-test/data'    present owner root mode 0700

# Inline file content
file_content '/opt/modes-test/config/app.conf' owner root mode 0644 <<EOF
# managed by ssm-converge
app.name=modes-test
app.version=0.1.0
app.port=8080
EOF

# Hosts
host_entry '10.88.0.5' present hostname 'api.modes-test.internal'
host_entry '10.88.0.6' present hostname 'db.modes-test.internal'

# Kernel parameter (enforce only; skipped in destroy)
sysctl 'net.core.somaxconn' value '4096'

report_compliance
