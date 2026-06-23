# Linux Examples

| File | Description | EC2 validation |
|------|-------------|----------------|
| [`nginx-webserver.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/nginx-webserver.sh) | NGINX with virtual host, TLS dirs, log rotation, kernel tuning | enforce + audit, HTTP 200 on localhost |
| [`webserver-apache.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/webserver-apache.sh) | Apache HTTPD with hardening, vhost, mod_ssl | enforce + audit, HTTP 200 on localhost |
| [`os-post-build.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/os-post-build.sh) | Post-build OS baseline — hardening, agents, time sync, monitoring | enforce + audit, 52/55 ok on clean AL2023 |
| [`security-hardening.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/security-hardening.sh) | CIS-style OS hardening — SSH, sysctl, permissions, unused packages | enforce + audit, idempotent re-run verified |
| [`install-vendor-package.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/install-vendor-package.sh) | Download + unattended install pattern: public HTTPS, authenticated HTTPS (bearer / basic), and S3 sources, paired with `execute` and `creates` / `not_if` guards. Three scenarios in one configuration: CloudWatch Agent (public HTTPS), Artifactory-style (token), and S3 (instance role). | enforce + audit, idempotent re-run verified on AL2023 + Ubuntu |
| [`ssm-doc-webserver.json`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/ssm-doc-webserver.json) | Runs the webserver baseline via SSM Run Command | Document registered and executed against fleet |
| [`ssm-doc-audit-only.json`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/ssm-doc-audit-only.json) | Audit-mode document for scheduled drift detection | Used as State Manager association shape |

## Reference-only examples

Under [`linux/reference/`](https://github.com/aws-samples/sample-ssm-converge/tree/main/examples/linux/reference): `webserver-baseline.sh`, `apache-tomcat.sh`, `postgresql-server.sh`, `app-deploy.sh`. These need environment-specific adaptation (S3 artifacts, app runtimes, larger instance sizes) before running. Not validated end-to-end.

## NGINX example anatomy

A typical Linux configuration looks like this. The pattern: kernel tuning, packages, directories, files, services, handler, report.

```bash
#!/bin/bash
source /opt/ssm-converge/lib.sh

# Kernel tuning for a web tier
sysctl 'net.core.somaxconn'           value '65535'
sysctl 'net.ipv4.tcp_max_syn_backlog' value '65535'

# Package
package 'nginx' installed

# Directory layout
directory '/etc/nginx/sites-available' present owner 'root' group 'root' mode '0755'
directory '/var/www/example.com'       present owner 'nginx' group 'nginx' mode '0755'

# Main config
file_content '/etc/nginx/nginx.conf' owner 'root' mode '0644' notify 'reload-nginx' <<'EOF'
user nginx;
worker_processes auto;
events { worker_connections 8192; }
http {
    include /etc/nginx/sites-enabled/*.conf;
}
EOF

# Service
service 'nginx' running enabled

# Handler — runs once at end if any file with 'notify reload-nginx' changed
handler 'reload-nginx' systemctl reload nginx

# Report
report_compliance
```

Full file: [`examples/linux/nginx-webserver.sh`](https://github.com/aws-samples/sample-ssm-converge/blob/main/examples/linux/nginx-webserver.sh).

## Download-and-install pattern

The newest example demonstrates the canonical "fetch a vendor installer and install it unattended" pattern:

```bash
# Download Amazon CloudWatch Agent .deb from public HTTPS with checksum verification.
file '/tmp/amazon-cloudwatch-agent.deb' present \
  source   'https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb' \
  checksum 'sha256:...' \
  mode '0644'

# Install with idempotency guard - second pass becomes a no-op.
execute 'install-cloudwatch-agent' \
  command 'dpkg -i /tmp/amazon-cloudwatch-agent.deb' \
  creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'
```

For private artifact repos with bearer-token or basic-auth, see the [`file`](../resources/linux/file.md) and [`execute`](../resources/linux/execute.md) resource pages.

## Modes for any example

```bash
sudo DSC_MODE=audit   bash examples/linux/nginx-webserver.sh   # check, never modify
sudo DSC_MODE=enforce bash examples/linux/nginx-webserver.sh   # converge to declared state
sudo DSC_MODE=destroy bash examples/linux/nginx-webserver.sh   # tear down
```

See [Concepts › Modes](../concepts/modes.md) for the full mode semantics.
