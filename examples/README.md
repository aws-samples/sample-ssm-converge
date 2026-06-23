# SSM Converge - Examples

Example configurations split by operating system family.

## Layout

```
examples/
├── linux/                       # Bash configurations
│   ├── nginx-webserver.sh
│   ├── webserver-apache.sh
│   ├── os-post-build.sh
│   ├── security-hardening.sh
│   ├── install-vendor-package.sh
│   ├── ssm-doc-webserver.json
│   ├── ssm-doc-audit-only.json
│   └── reference/               # Starting points that need environment adaptation
└── windows/                     # PowerShell configurations
    ├── iis-webserver.ps1
    ├── wsfc-cluster.ps1
    ├── mssql-server.ps1
    ├── mssql-fci-baseline.ps1
    └── install-vendor-msi.ps1
```

## Linux

| File | Description | EC2 validation |
|------|-------------|----------------|
| `nginx-webserver.sh` | NGINX with virtual host, TLS dirs, log rotation, kernel tuning | enforce + audit, HTTP 200 on localhost |
| `webserver-apache.sh` | Apache HTTPD with hardening, vhost, mod_ssl | enforce + audit, HTTP 200 on localhost |
| `os-post-build.sh` | Post-build OS baseline - hardening, agents, time sync, monitoring | enforce + audit, 52/55 ok on clean AL2023 |
| `security-hardening.sh` | CIS-style OS hardening - SSH, sysctl, permissions, unused packages | enforce + audit, idempotent re-run verified |
| `install-vendor-package.sh` | Download + unattended install pattern: public HTTPS, authenticated HTTPS (bearer / basic), and S3 sources, paired with `execute` and `creates` / `not_if` guards. Three scenarios in one configuration: CloudWatch Agent (public HTTPS), Artifactory-style (token), and S3 (instance role). | enforce + audit, idempotent re-run verified on AL2023 + Ubuntu |
| `ssm-doc-webserver.json` | Runs the webserver baseline via SSM Run Command | Document registered and executed against fleet |
| `ssm-doc-audit-only.json` | Audit-mode document for scheduled drift detection | Used as State Manager association shape |

Reference-only examples (`linux/reference/`, see `reference/README.md`): `webserver-baseline.sh`, `apache-tomcat.sh`, `postgresql-server.sh`, `app-deploy.sh`. These need environment-specific adaptation (S3 artifacts, app runtimes, larger instance sizes) before running. Not validated end-to-end.

## Windows

| File | Description | EC2 validation |
|------|-------------|----------------|
| `iis-webserver.ps1` | IIS from bare Windows - Web-Server role + sub-features, site directory, index.html, service state, registry hardening | **Full enforce + audit + idempotent re-run.** GET / returns HTTP 200. Uses pure primitives, no DscResource. |
| `wsfc-cluster.ps1` | Failover Cluster node prep + cluster create | Prerequisites fully enforced: Failover-Clustering feature, RSAT-Clustering, FailoverClusterDsc module v2.2.0, host entries, ClusterAdmins local group. Cluster creation itself requires two nodes + AD domain (not attempted on single-node test). |
| `mssql-server.ps1` | Standalone SQL Server via `DscResource -Module SqlServerDsc` | Audit-only: correctly catalogs missing prerequisites (SqlServerDsc module, data directories, services, registry tuning). Full install requires installer media staged in S3 (outside scope of the sample). |
| `mssql-fci-baseline.ps1` | MSSQL FCI node baseline demonstrating the pattern for porting existing DSC configurations (features, modules, host entries, local groups, cert import, domain join, gMSA, cluster create, node join, SQL install) | Documentary / audit pattern - full enforcement needs a real FCI environment. Shows the primitive + DscResource composition. |
| `install-vendor-msi.ps1` | Download + unattended install pattern for Windows: public HTTPS, authenticated HTTPS (bearer / basic / custom headers), and S3 sources, paired with `Execute -Creates` / `-NotIf`. Includes MSI (CloudWatch Agent), authenticated MSI (Artifactory-style), S3 MSI, and InnoSetup/NSIS-style EXE installers. | enforce + audit, idempotent re-run verified on Windows Server 2022 |

## Running Locally

### Linux

```bash
sudo DSC_MODE=enforce DSC_PROFILE=webserver bash examples/linux/nginx-webserver.sh
```

### Windows

```powershell
$env:DSC_MODE    = "enforce"
$env:DSC_PROFILE = "iis-webserver"
. C:\ProgramData\ssm-converge\lib.ps1
. examples\windows\iis-webserver.ps1
```

Or via the CLI:

```powershell
& C:\ProgramData\ssm-converge\ssm-converge.ps1 run   examples\windows\iis-webserver.ps1
& C:\ProgramData\ssm-converge\ssm-converge.ps1 check examples\windows\iis-webserver.ps1
```

## Running via SSM Run Command

```bash
# Linux
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

For Windows today, stage the `.ps1` in S3 and call a small wrapper document that uses `Read-S3Object` + `&` to execute it. A Windows-native `SSMConverge-Run.json` is planned for v0.2.

## Scheduled Drift Detection with State Manager

```bash
aws ssm create-association \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(30 minutes)" \
  --parameters "Mode=audit,Profile=webserver,Report=full,Config=$CFG_B64"
```

## Shipping Reports Off-Instance

Every configuration calls `report_compliance` / `Report-Compliance` to write the local report. Customers pipe the full JSON wherever they need it:

```bash
# Linux -> S3 audit lake
get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname)/$(date +%Y%m%d%H%M).json"

# Linux -> internal compliance API
get_report_json | curl -X POST -H 'Content-Type: application/json' \
  --data-binary @- https://compliance.internal/api/v1/report

# Linux -> SSM Compliance API (via the sample reporter)
source /opt/ssm-converge/reporters/ssm_compliance.sh
_report_to_ssm_compliance "$(get_report_json)"
```

```powershell
# Windows -> S3 audit lake
Get-ReportJson | Out-File -Encoding ascii C:\Windows\Temp\report.json
Write-S3Object -BucketName DOC-EXAMPLE-BUCKET -Key "$(hostname)/$(Get-Date -Format yyyyMMddHHmm).json" -File C:\Windows\Temp\report.json
```
