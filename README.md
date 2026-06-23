# SSM Converge

**Desired state configuration through AWS Systems Manager, for Linux and Windows.**

*Declare. Converge. Comply.*

📘 **Full documentation: [https://github.com/awslabs/ssm-converge](https://github.com/awslabs/ssm-converge)**

SSM Converge is a library that brings Chef/Ansible-style declarative configuration management to AWS Systems Manager. It runs through the existing SSM Agent with no extra runtimes — no Ruby, no Python agents, no third-party tooling. Same DSL on Linux (bash) and Windows (PowerShell).

## ⚠️ Important

This project is provided as **sample code** for educational and reference purposes. It is **not** intended for direct production deployment without additional security review, testing, and hardening appropriate to your environment. See [SECURITY.md](SECURITY.md) for production hardening recommendations.

## Why

| Problem | What SSM Converge does |
|---|---|
| SSM Documents are procedural scripts | Declarative resource DSL with idempotent check/apply primitives |
| No built-in desired state management | Each resource checks current state and only acts when it differs |
| Chef/Ansible require an extra agent | Runs on the SSM Agent you already have |
| Compliance reporting is an afterthought | Every run produces a structured JSON report you ship anywhere |
| InSpec is audit-only | The same configuration audits *or* enforces *or* tears down |
| Existing DSC investment shouldn't be thrown away | `DscResource` primitive wraps any existing DSC resource (FailoverClusterDsc, ActiveDirectoryDsc, SqlServerDsc, ...) |

## Quick Start

### Linux

```bash
#!/bin/bash
source /opt/ssm-converge/lib.sh

package 'nginx' installed
package 'telnet' uninstalled

file '/etc/nginx/nginx.conf' present \
  source 's3://DOC-EXAMPLE-BUCKET/nginx.conf' \
  owner 'root' mode '0644' \
  notify 'reload-nginx'

service 'nginx' running enabled

handler 'reload-nginx' systemctl reload nginx

# Writes /var/lib/ssm-converge/latest.json, prints a one-line summary.
report_compliance
```

### Windows

```powershell
. C:\ProgramData\ssm-converge\lib.ps1

WindowsFeature 'Web-Server' Installed -IncludeManagementTools

Directory 'C:\inetpub\example.com' Present

File-Content -Path 'C:\inetpub\example.com\index.html' -Content '<h1>Hello</h1>'

RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
    -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord

WindowsService 'W3SVC' Running -StartupType Automatic

# Writes C:\ProgramData\ssm-converge\latest.json, prints a one-line summary.
Report-Compliance
```

### Ship the report anywhere

```bash
# Linux
get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname).json"
```

```powershell
# Windows
Get-ReportJson | Out-File C:\Windows\Temp\r.json -Encoding ascii
Write-S3Object -BucketName DOC-EXAMPLE-BUCKET -Key "$(hostname).json" -File C:\Windows\Temp\r.json
```

### Download a vendor installer and install it unattended

The same pattern works on both platforms: `file` fetches the artifact (S3, public HTTPS, or authenticated HTTPS with bearer / basic / custom-header auth), and `execute` runs the silent installer with a guard that makes it idempotent.

```bash
# Linux — Amazon CloudWatch Agent .deb pulled from public HTTPS, installed via dpkg.
file '/tmp/cw-agent.deb' present \
  source   'https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb' \
  checksum 'sha256:...' \
  mode '0644'

execute 'install-cloudwatch-agent' \
  command 'dpkg -i /tmp/cw-agent.deb' \
  creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'
```

```powershell
# Windows — same pattern with an MSI; `cmd` interpreter for msiexec parsing.
File 'C:\temp\cw-agent.msi' Present `
     -Source   'https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi' `
     -Checksum 'sha256:...'

Execute 'install-cloudwatch-agent' `
        -Command     'msiexec /i C:\temp\cw-agent.msi /qn /norestart' `
        -Creates     'C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1' `
        -Interpreter 'cmd'
```

For private artifact repos, add `auth_bearer "$TOKEN"` or `auth_basic 'user:pass'` (Linux) / `-AuthBearer`, `-AuthBasic`, `-Headers` (Windows). Full examples in `examples/linux/install-vendor-package.sh` and `examples/windows/install-vendor-msi.ps1`.

## Modes

A single configuration supports four modes, selected via `DSC_MODE` / `DSC_REPORT`:

| Mode | Behaviour |
|---|---|
| `enforce` (default) | Check state, fix drift, write report |
| `audit` | Check state only, never change anything |
| `destroy` | Flip desired state (`present`→`absent`, `running`→`stopped`) and converge — like `chef client --teardown` |
| `comply` | Audit mode + full detailed pass/fail report (for compliance evidence) |

```bash
DSC_MODE=audit   bash webserver.sh
DSC_MODE=enforce bash webserver.sh
DSC_MODE=destroy bash webserver.sh
ssm-converge comply webserver.sh             # audit + full detailed report
```

## Resources

Full reference manual for every built-in resource: [docs/resources/README.md](docs/resources/README.md) — Chef-style index with one dedicated page per resource (syntax, properties, examples, destroy-mode behaviour, notes).

One-file version: [docs/resources/USAGE.md](docs/resources/USAGE.md) — all 30 resources in a single, searchable, printable document. Regenerated from the per-resource pages with `bash docs/resources/build-usage.sh`.

### Linux (15 primitives)

| Resource | States | Key Attributes |
|---|---|---|
| `package` | installed, uninstalled | version |
| `file` | present, absent | source (S3 / HTTPS / file://), content, checksum, auth_bearer, auth_basic, header, owner, group, mode, notify |
| `file_content` | (heredoc helper for inline content) | owner, group, mode, notify |
| `execute` | run | command, creates, only_if, not_if, user, cwd, env, timeout, notify |
| `directory` | present, absent | owner, group, mode, recursive |
| `service` | running, stopped, restarted | enabled, disabled, notify |
| `user` | present, absent | shell, groups, home, uid, system |
| `group` | present, absent | members, gid |
| `sysctl` | value set | persist |
| `cron` | present, absent | schedule, command, user |
| `line_in_file` | present, absent | line, match, notify |
| `mount_fs` | present, absent | device, fstype, options, persist |
| `timezone` | set | — |
| `locale` | set | — |
| `host_entry` | present, absent | hostname, hosts_file |

`sysctl`, `timezone`, `locale`, and `execute` are skipped in `destroy` mode — there is no safe inverse for kernel parameters or arbitrary commands.

### Windows (15 primitives)

| Resource | States | Key Attributes |
|---|---|---|
| `File` / `File-Content` | Present, Absent | Source (S3 / HTTPS / file://), Content, Checksum, AuthBearer, AuthBasic, Headers, Notify |
| `Directory` | Present, Absent | Recursive |
| `Package` | Installed, Uninstalled | via winget / Chocolatey / Get-Package |
| `Execute` | Run | Command, Creates, OnlyIf, NotIf, Cwd, EnvVars, TimeoutSec, Interpreter, Notify |
| `WindowsService` | Running, Stopped, Restarted | StartupType, Notify |
| `RegistryKey` | Present, Absent | ValueName, ValueData, ValueType |
| `WindowsFeature` | Installed, Uninstalled | IncludeManagementTools, Source |
| `PowerShellModule` | Installed, Uninstalled | Version, Repository, Scope |
| `Certificate` | Present, Absent | Store, Password, Thumbprint |
| `LocalUser` | Present, Absent | Password, FullName, PasswordNeverExpires |
| `LocalGroup` | Present, Absent | Members, MembersToInclude, MembersToExclude |
| `HostEntry` | Present, Absent | Hostname |
| `EnvironmentVariable` | Present, Absent | Value, Target, Path |
| `ScheduledTask` | Present, Absent | Execute, Argument, Daily, IntervalMinutes, RunAsUser |
| **`DscResource`** | — | **Generic wrapper: invoke any existing DSC resource through SSM Converge's pipeline** |

The `DscResource` primitive lets you keep your existing DSC investment. You pass `-Module` and `-Properties` and the library calls `Invoke-DscResource` behind the check/apply/report pipeline. Works with PSDscResources, FailoverClusterDsc, ComputerManagementDsc, CertificateDsc, ActiveDirectoryDsc, SqlServerDsc, NetworkingDsc, and any other DSC module installed on the host.

## Platform Support

| Layer | Linux | Windows |
|---|---|---|
| Package managers | apt, dnf, yum, zypper, apk, brew, pkg (FreeBSD), pkgin, pkg_add | winget, Chocolatey, Get-Package / MSI |
| Init systems | systemd, openrc, sysvinit, rc.d, SMF (Solaris), launchctl (macOS) | Services Control Manager |
| File operations | GNU coreutils (Linux), BSD (macOS/FreeBSD/OpenBSD) | .NET / Win32 |

Validated end-to-end on Amazon Linux 2023 and Windows Server 2022. See [CHANGELOG.md](CHANGELOG.md) for the detailed test matrix.

## Compliance Reporting

SSM Converge separates *converging* from *reporting*. Every run produces a structured JSON report. The library writes a local copy and gives you the full document via `get_report_json()` / `Get-ReportJson`; you decide where it goes next.

```
report_compliance / Report-Compliance
  ├─ writes  latest.json            (/var/lib/ssm-converge/ or C:\ProgramData\ssm-converge\)
  ├─ appends drift.log              (non-compliant events)
  ├─ keeps   history/               (rotating snapshots)
  └─ prints  one-line summary       (or full detailed report in comply mode)

get_report_json / Get-ReportJson    ->  stdout JSON  ->  you pipe anywhere
```

Status values are minimal — no warnings:

| Status | Meaning |
|---|---|
| `compliant` | Current state matches desired state (may have been fixed this run) |
| `non_compliant` | Drift detected (audit mode) or could not be fixed |
| `error` | Check or apply failed — missing tool, permission denied, invalid key |

### Full compliance report

Use the `comply` command (or `DSC_REPORT=full`) when you want a detailed pass/fail listing:

```
$ ssm-converge comply /opt/configs/webserver.sh

===================================================
  SSM Converge - Compliance Report
  Profile: webserver | Mode: audit
===================================================

  --- Detailed Results -----------------------------
  [PASS ] package/nginx
  [PASS ] package/jq
  [FAIL ] file/etc/nginx/nginx.conf (content drift)
  [PASS ] service/nginx
  [ERROR] sysctl/net.ipv4.bogus (sysctl -w failed)

  --- Summary --------------------------------------
  Total Checks:   5
  Compliant:      3
  Non-Compliant:  1
  Errors:         1
===================================================
```

### Sample reporters (Linux)

`src/linux/reporters/` contains small wrappers you can source if you want to push to common destinations: `ssm_compliance.sh` (validated end-to-end against the live SSM Compliance API), `s3.sh`, `eventbridge.sh`. They are examples, not the primary path — most users just pipe `get_report_json`.

## CLI

Same command surface on both platforms:

```
ssm-converge run <config>      # enforce mode
ssm-converge check <config>    # audit mode (no changes)
ssm-converge destroy <config>  # tear down
ssm-converge comply <config>   # audit + full detailed report
ssm-converge status            # latest compliance state
ssm-converge history [n]       # last N runs (default 10)
ssm-converge drift             # recent drift events
ssm-converge export            # InSpec-compatible JSON
ssm-converge version           # also --version / -v
ssm-converge help              # also --help / -h
```

- **Linux:** installed at `/usr/local/bin/ssm-converge`
- **Windows:** installed at `C:\ProgramData\ssm-converge\ssm-converge.ps1` (add that path to `PATH` if you want bare `ssm-converge` invocation)

## Installation

### Option 1 — SSM Distributor package (recommended)

Package once, install across the fleet via the AWS-managed `AWS-ConfigureAWSPackage` document. Version management, upgrades, and uninstalls all come built-in. The Distributor package picks the right zip (Linux or Windows) based on the target's platform automatically.

**Build and publish** (once per release):

```bash
bash distributor/build-package.sh
# Produces Linux + Windows zips + manifest.json under distributor/dist/.

aws s3 sync distributor/dist/ s3://<your-bucket>/distributor/ --quiet

aws ssm create-document \
  --name ssm-converge \
  --document-type Package \
  --document-format JSON \
  --content file://distributor/dist/manifest.json \
  --attachments "Key=SourceUrl,Values=s3://<your-bucket>/distributor" \
  --version-name 0.1.2
```

**Install on the fleet:**

```bash
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "Key=tag:Managed,Values=ssm-converge" \
  --parameters 'action=Install,name=ssm-converge,version=0.1.2'
```

**Uninstall** (library + CLI removed; history is preserved):

```bash
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "..." \
  --parameters 'action=Uninstall,name=ssm-converge'
```

**Upgrade** — publish a new version of the document and `action=Install,version=<new>` — existing install is replaced atomically.

### Option 2 — Bake into the AMI

```bash
# Linux
sudo mkdir -p /opt/ssm-converge
sudo cp -r src/linux/* /opt/ssm-converge/
sudo install -m 755 cli/ssm-converge /usr/local/bin/ssm-converge
```

```powershell
# Windows
New-Item -ItemType Directory -Force C:\ProgramData\ssm-converge | Out-Null
Copy-Item -Recurse src\windows\* C:\ProgramData\ssm-converge\
Copy-Item cli\ssm-converge.ps1 C:\ProgramData\ssm-converge\ssm-converge.ps1
```

Fine for golden AMIs where you control the bake step. Downside: no in-place updates — you have to re-bake and re-deploy the AMI.

### Option 3 — Install from S3 via the bundled SSM Document

Useful when you don't want to register a Distributor package but still want SSM to drive the install:

```bash
aws s3 sync . s3://<your-bucket>/ssm-converge/ \
  --exclude "*" --include "src/linux/*" --include "cli/ssm-converge"

aws ssm create-document \
  --name SSMConverge-Install \
  --document-type Command \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Install.json

aws ssm send-command \
  --document-name SSMConverge-Install \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters 'S3Bucket=<your-bucket>,S3Prefix=ssm-converge'
```

The bundled document is Linux-only. For Windows, use Distributor (Option 1) or bake it in (Option 2).

## Running via SSM

### Ad-hoc with Run Command

Configuration is passed base64-encoded so you don't fight SSM's StringList escape rules:

```bash
CFG_B64=$(base64 < my-config.sh)

aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

### Scheduled drift detection with State Manager

```bash
aws ssm create-association \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(30 minutes)" \
  --parameters "Mode=audit,Profile=webserver,Report=full,Config=$CFG_B64"
```

### Full deployment guide

The complete guide for getting configurations onto instances at any scale lives at [docs/deployment.md](docs/deployment.md). It walks through:

- Creating an SSM document (generic runner vs. baked-in patterns)
- Running against specific instance IDs, tagged fleets, or Resource Groups
- Scheduling continuous enforcement with State Manager
- Deploying across an entire AWS Organization (Quick Setup, CloudFormation StackSets, cross-account loop)
- An operational checklist for safe rollouts and a triage playbook

## Project Structure

```
ssm-converge/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── mkdocs.yml                    # Docs site config (MkDocs Material, AWS theme)
├── .github/workflows/docs.yml    # Build & publish docs on push to main
├── docs/                         # Documentation site source
│   ├── index.md                  # Landing page
│   ├── architecture.md           # The "why" - leadership view
│   ├── quickstart.md             # Five-minute walkthrough
│   ├── one-pager.md              # Original one-pager (kept for offline use)
│   ├── requirements.md           # Detailed requirements & milestones
│   ├── deployment.md             # Original deployment guide (kept for offline use)
│   ├── assets/                   # Logo, favicon
│   ├── stylesheets/              # AWS theme CSS overrides
│   ├── concepts/                 # Modes, resources/DSL, handlers, reporting
│   ├── resources/                # Per-resource reference (15 Linux + 15 Windows)
│   │   ├── README.md             # Index for the on-disk reading path
│   │   ├── USAGE.md              # All resources in one printable page
│   │   ├── linux/
│   │   └── windows/
│   ├── deploying/                # Installation, running, scheduling, organization
│   ├── examples/                 # Per-platform examples index
│   └── reference/                # CLI, report schema, changelog
├── src/
│   ├── linux/
│   │   ├── lib.sh                # Core engine (bash)
│   │   ├── resources/            # 15 Linux resource providers (incl. execute)
│   │   └── reporters/            # Sample reporters (SSM Compliance, S3, EventBridge)
│   └── windows/
│       ├── lib.ps1               # Core engine (PowerShell)
│       └── resources/            # 15 Windows resource providers including DscResource wrapper
├── cli/
│   ├── ssm-converge              # Linux CLI
│   └── ssm-converge.ps1          # Windows CLI
├── distributor/
│   ├── build-package.sh          # Builds cross-platform SSM Distributor package
│   ├── install.sh                # Linux install hook for AWS-ConfigureAWSPackage
│   ├── uninstall.sh
│   ├── install.ps1               # Windows install hook for AWS-ConfigureAWSPackage
│   └── uninstall.ps1             # Windows uninstall hook (preserves compliance history)
├── ssm-documents/
│   ├── SSMConverge-Install.json  # Install the library from S3 (Linux)
│   └── SSMConverge-Run.json      # Run an inline base64-encoded configuration
├── examples/
│   ├── linux/
│   │   ├── nginx-webserver.sh
│   │   ├── webserver-apache.sh
│   │   ├── os-post-build.sh
│   │   ├── security-hardening.sh
│   │   ├── install-vendor-package.sh   # Download + unattended install (HTTPS / S3 / authenticated)
│   │   ├── ssm-doc-*.json
│   │   └── reference/            # Starting points that need environment adaptation
│   └── windows/
│       ├── iis-webserver.ps1           # IIS from bare Windows
│       ├── wsfc-cluster.ps1            # Failover Cluster node (uses DscResource)
│       ├── mssql-server.ps1            # Standalone SQL Server (uses DscResource)
│       ├── mssql-fci-baseline.ps1      # MSSQL FCI node primer
│       └── install-vendor-msi.ps1      # Download + unattended MSI/EXE install
└── tests/
    ├── linux/                    # test_local, test_idempotent, test_destroy, ...
    └── windows/                  # test_local, test_windows_modes, test_windows_resources
```

## How It Works

Each resource follows the same three-phase pattern:

1. **CHECK** — Is the current state already the desired state?
2. **APPLY** (`enforce` / `destroy` only) — If not, converge.
3. **RECORD** — Push the result onto the results array for the report.

```
┌────────────────────────────────────────────────────────────┐
│  Configuration — bash or PowerShell script                 │
├────────────────────────────────────────────────────────────┤
│  lib.sh / lib.ps1 — engine: modes, handlers, reporting     │
├────────────────────────────────────────────────────────────┤
│  Resource providers — idempotent check + apply per type    │
├────────────────────────────────────────────────────────────┤
│  SSM Agent — executes the document on the instance         │
├────────────────────────────────────────────────────────────┤
│  You — pipe get_report_json wherever it needs to go        │
└────────────────────────────────────────────────────────────┘
```

## Error Handling

Resources treat failures as first-class results rather than silent passes:

**Linux:**
- `file` verifies `aws s3 cp` return code; reports `error` on download failure
- `service` verifies the service is actually active after start; reports `error` if not
- `sysctl` verifies `sysctl -w` return code; reports `error` on invalid keys
- `package` verifies the package is installed after `install`; reports `error` on failure

**Windows:**
- `WindowsFeature` verifies the post-install state; treats `InstallPending` as installed with reboot request
- `WindowsService` verifies the service is actually in the desired state
- `Package` falls back across winget → choco → Get-Package and reports which manager succeeded
- `PowerShellModule` auto-bootstraps the NuGet provider silently (fixes the common "non-interactive" prompt failure)
- `DscResource` surfaces the underlying DSC engine's error message verbatim

Every `error` counts toward the run's exit code and the JSON report.

## Debug Logging

SSM Converge writes a timestamped trace to a debug log:
- **Linux:** `/var/log/ssm-converge.log` (configurable via `DSC_LOG_FILE`, falls back to `/tmp` if not writable)
- **Windows:** `C:\ProgramData\ssm-converge\ssm-converge.log` (falls back to `%TEMP%`)

The log records banner, resource sourcing, every check/change/drift/error event, and the final report call. Handy when an SSM Run Command times out and you need to know which resource was executing.

## Comparison

|  | Chef | Ansible | InSpec | SSM Converge |
|---|---|---|---|---|
| Agent | Chef client | SSH / WinRM | InSpec gem | SSM Agent (pre-installed) |
| Language | Ruby DSL | YAML | Ruby DSL | Bash + PowerShell |
| Desired state | ✓ | ✓ | audit only | ✓ |
| Remediation | ✓ | ✓ | ✗ | ✓ (`enforce`) |
| Audit mode | ✓ (why-run) | ✓ (check) | ✓ | ✓ (`audit`) |
| Teardown | ✓ | ✗ | ✗ | ✓ (`destroy`) |
| Cross-account | complex | complex | complex | native (SSM) |
| Reuses existing DSC resources | ✗ | ✗ | ✗ | ✓ (`DscResource` primitive) |
| Zero extra dependencies | ✗ | ✗ | ✗ | ✓ |

## License

Apache 2.0
