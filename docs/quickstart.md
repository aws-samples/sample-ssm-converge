# Quick Start

Five minutes from "I cloned the repo" to "I have a configuration running through SSM."

## 1. Install the library

You only do this once per instance. Pick the path that fits your delivery model:

=== "Distributor (recommended)"

    ```bash
    # One-time package registration in your AWS account.
    aws ssm create-document \
      --name ssm-converge \
      --document-type Package \
      --document-format JSON \
      --content file://distributor/dist/manifest.json \
      --attachments "Key=SourceUrl,Values=s3://<your-bucket>/distributor" \
      --version-name 0.1.2

    # Install on tagged instances.
    aws ssm send-command \
      --document-name AWS-ConfigureAWSPackage \
      --targets "Key=tag:Managed,Values=ssm-converge" \
      --parameters 'action=Install,name=ssm-converge,version=0.1.2'
    ```

    Cross-platform package: works on Amazon Linux, Ubuntu, Debian, RHEL, and Windows Server.

=== "Inline (no Distributor)"

    ```bash
    # Stage the library in S3.
    aws s3 sync src/ s3://<your-bucket>/ssm-converge/src/
    aws s3 cp   cli/ssm-converge s3://<your-bucket>/ssm-converge/cli/ssm-converge

    # Register the install document.
    aws ssm create-document \
      --name SSMConverge-Install \
      --document-type Command \
      --content file://ssm-documents/SSMConverge-Install.json

    # Pull onto instances.
    aws ssm send-command \
      --document-name SSMConverge-Install \
      --targets "Key=tag:Role,Values=WebServer" \
      --parameters 'S3Bucket=<your-bucket>,S3Prefix=ssm-converge'
    ```

    Linux today; for Windows use Distributor or bake the library into your AMI.

=== "Bake into AMI"

    Add the install step to your Image Builder pipeline / Packer build. The library is a single bash file plus a directory of resource scripts on Linux, or a single PowerShell file plus a resources directory on Windows.

See [Deploying › Installation](deploying/installation.md) for full details.

## 2. Write your first configuration

A configuration is a `.sh` (Linux) or `.ps1` (Windows) file that sources the library and declares resources.

=== "Linux"

    ```bash
    # webserver.sh
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

    report_compliance
    ```

=== "Windows"

    ```powershell
    # webserver.ps1
    . C:\ProgramData\ssm-converge\lib.ps1

    WindowsFeature 'Web-Server' Installed -IncludeManagementTools
    Directory      'C:\inetpub\example.com' Present
    File-Content   -Path 'C:\inetpub\example.com\index.html' -Content '<h1>Hello</h1>'

    RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
        -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord

    WindowsService 'W3SVC' Running -StartupType Automatic

    Report-Compliance
    ```

The DSL is intentionally narrow. The `package`, `file`, `service`, `directory`, `user`, `group`, `cron`, `line_in_file`, ... primitives cover the everyday surface. For installers without a package manager, [`execute`](resources/linux/execute.md) provides idempotent shell-out with `creates` / `only_if` / `not_if` guards.

## 3. Run it locally first

Test the configuration on one instance before pushing it to a fleet.

=== "Linux"

    ```bash
    # Audit-only - read state, never change anything.
    sudo DSC_MODE=audit DSC_PROFILE=webserver bash webserver.sh

    # Enforce - converge to the desired state.
    sudo DSC_MODE=enforce DSC_PROFILE=webserver bash webserver.sh
    ```

=== "Windows"

    ```powershell
    $env:DSC_MODE    = 'audit'
    $env:DSC_PROFILE = 'webserver'
    . C:\ProgramData\ssm-converge\lib.ps1
    . .\webserver.ps1
    ```

The output is a one-line summary by default; `DSC_REPORT=full` prints the per-resource detail table. The local report goes to `/var/lib/ssm-converge/latest.json` (Linux) or `C:\ProgramData\ssm-converge\latest.json` (Windows).

## 4. Run it through SSM

```bash
# Register the bundled runner document once per region.
aws ssm create-document \
  --name SSMConverge-Run \
  --document-type Command \
  --content file://ssm-documents/SSMConverge-Run.json

# Encode the configuration and ship it.
CFG_B64=$(base64 < webserver.sh)

aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

`SSMConverge-Run` decodes the base64 config, runs it under the requested mode, and surfaces the report through SSM's `StandardOutputContent`. See [Deploying › Running Configurations](deploying/running.md) for tag targeting, instance-ID targeting, Resource Groups, and rollout safety knobs.

## 5. Schedule continuous enforcement

Make it stick:

```bash
aws ssm create-association \
  --association-name webserver-baseline \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(30 minutes)" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

Now every 30 minutes, every WebServer-tagged instance re-checks its state and self-heals. Drift detection and remediation, no agent.

See [Deploying › Scheduled Enforcement](deploying/scheduling.md) for cron expressions, audit-mode dashboards, and `--compliance-severity` integration.

## What next

- Browse the [Resources](resources/index.md) reference - 30 primitives in depth.
- Read [Concepts › Modes](concepts/modes.md) to understand the four execution modes.
- Pick a starting point from the [Examples](examples/index.md).
- For an org-wide rollout, head to [Deploying › Organization-wide](deploying/organization.md).
