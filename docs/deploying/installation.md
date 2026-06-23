# Installation

Three valid paths. Pick the one that fits your delivery model.

## Option 1 — SSM Distributor package (recommended)

A single cross-platform Distributor package - one manifest, Linux amd64/arm64 zips, Windows amd64 zip. Installs and uninstalls via `AWS-ConfigureAWSPackage`, the document AWS uses for its own agent shipping.

### One-time package registration

```bash
# Build the package locally.
bash distributor/build-package.sh

# Stage the artefacts in S3.
aws s3 sync distributor/dist/ s3://<your-bucket>/distributor/ --quiet

# Register with SSM (once per region, once per version).
aws ssm create-document \
  --name ssm-converge \
  --document-type Package \
  --document-format JSON \
  --content file://distributor/dist/manifest.json \
  --attachments "Key=SourceUrl,Values=s3://<your-bucket>/distributor" \
  --version-name 0.1.2
```

### Install on tagged instances

```bash
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "Key=tag:Managed,Values=ssm-converge" \
  --parameters 'action=Install,name=ssm-converge,version=0.1.2'
```

### Update or uninstall

```bash
# Upgrade (new version registered as the same package name)
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "..." \
  --parameters 'action=Install,name=ssm-converge,version=0.1.3'

# Uninstall - preserves compliance history (latest.json, history/, drift.log)
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "..." \
  --parameters 'action=Uninstall,name=ssm-converge'
```

## Option 2 — Inline SSMConverge-Install (no Distributor)

When you don't want to register a Distributor package — say, in a small POC or a sandbox account.

```bash
# Stage the library in S3 (one-time).
aws s3 sync src/linux/ s3://<your-bucket>/ssm-converge/src/linux/ --quiet
aws s3 cp   cli/ssm-converge s3://<your-bucket>/ssm-converge/cli/ssm-converge --quiet

# Register the install document (one-time per region).
aws ssm create-document \
  --name SSMConverge-Install \
  --document-type Command \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Install.json

# Pull onto instances.
aws ssm send-command \
  --document-name SSMConverge-Install \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters 'S3Bucket=<your-bucket>,S3Prefix=ssm-converge'
```

The bundled document is **Linux-only**. For Windows, use Distributor (Option 1) or bake it in (Option 3).

## Option 3 — Bake into AMI

Add the install step to your Image Builder pipeline / Packer build. The library is small:

- Linux: a single `lib.sh` plus `resources/*.sh` directory plus the `ssm-converge` CLI script.
- Windows: a single `lib.ps1` plus `resources/*.ps1` directory plus the `ssm-converge.ps1` CLI script.

Sample EC2 Image Builder component:

```yaml
name: install-ssm-converge
description: Install SSM Converge library
schemaVersion: 1.0
phases:
  - name: build
    steps:
      - name: install-library
        action: ExecuteBash
        inputs:
          commands:
            - aws s3 sync s3://my-bucket/ssm-converge/src/linux/ /opt/ssm-converge/
            - aws s3 cp   s3://my-bucket/ssm-converge/cli/ssm-converge /usr/local/bin/ssm-converge
            - chmod +x /usr/local/bin/ssm-converge
            - mkdir -p /var/lib/ssm-converge/history
```

## Verifying the install

```bash
# Linux
which ssm-converge && ssm-converge version
ls -la /opt/ssm-converge/

# Windows
& C:\ProgramData\ssm-converge\ssm-converge.ps1 version
Get-ChildItem C:\ProgramData\ssm-converge\
```

Expected version on a fresh install:

```
ssm-converge v0.1.2
```

## CLI details

The CLI is a thin wrapper around the library that adds a few subcommands beyond direct configuration execution:

```text
ssm-converge run     <config.sh>     # enforce mode
ssm-converge check   <config.sh>     # audit mode
ssm-converge destroy <config.sh>     # destroy mode
ssm-converge comply  <config.sh>     # audit + full report
ssm-converge status                  # show last run summary
ssm-converge history                 # list saved runs
ssm-converge drift                   # show drift log
ssm-converge export                  # JSON of the latest run
ssm-converge version                 # print version
ssm-converge help                    # --help / -h
```

The CLI is optional — configurations work fine when invoked directly with `bash my-config.sh` (Linux) or `. my-config.ps1` (Windows). It exists to standardise the operator experience: the same `ssm-converge run myconfig.sh` works on every supported OS.

## What the install actually places

=== "Linux"

    | Path | Purpose |
    |------|---------|
    | `/opt/ssm-converge/lib.sh` | Core engine |
    | `/opt/ssm-converge/resources/*.sh` | The 15 resource providers |
    | `/opt/ssm-converge/reporters/*.sh` | Optional reporter samples (S3, EventBridge, SSM Compliance) |
    | `/usr/local/bin/ssm-converge` | CLI |
    | `/var/lib/ssm-converge/` | Local state (latest.json, history/, drift.log) |
    | `/var/log/ssm-converge.log` | Debug log |

=== "Windows"

    | Path | Purpose |
    |------|---------|
    | `C:\ProgramData\ssm-converge\lib.ps1` | Core engine |
    | `C:\ProgramData\ssm-converge\resources\*.ps1` | The 15 resource providers |
    | `C:\ProgramData\ssm-converge\ssm-converge.ps1` | CLI |
    | `C:\ProgramData\ssm-converge\` (same folder) | Local state (latest.json, history\, drift.log) |
    | `C:\ProgramData\ssm-converge\ssm-converge.log` | Debug log |

## Permissions required

The instance role needs `AmazonSSMManagedInstanceCore` so SSM can target it, plus whatever permissions your configurations require:

- `s3:GetObject` on configuration / artefact buckets if you `file source 's3://...'`.
- `ssm:PutComplianceItems` if you ship reports to SSM Compliance.
- `events:PutEvents` if you ship to EventBridge.

The library itself doesn't elevate or assume roles — it runs with whatever the SSM Agent inherits.
