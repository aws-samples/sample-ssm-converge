---
title: SSM Converge
hide:
  - navigation
  - toc
---

# SSM Converge

**An AWS-native, agentless DSC framework for declarative configuration management on EC2.** One DSL for Linux and Windows. Runs through SSM. Reports compliance back to AWS.

<div class="grid cards" markdown>

- ### :material-cloud-check: AWS-native
    No agent to install. No control plane to operate. Configurations ship through SSM Run Command, drift is detected by State Manager, evidence flows into your compliance lake. The runtime is a single bash file (Linux) or PowerShell file (Windows) that lives at `/opt/ssm-converge/lib.sh` or `C:\ProgramData\ssm-converge\lib.ps1`.

- ### :material-language-typescript: One DSL, two platforms
    The same `package`, `file`, `service`, `execute`, `directory`, `user`, `group`, ... vocabulary on both. 30 built-in resources cover the everyday configuration management surface. The Windows side adds a `DscResource` wrapper that calls `Invoke-DscResource` for any installed PSDSC module — keep your existing FailoverClusterDsc, SqlServerDsc, ActiveDirectoryDsc investment.

- ### :material-shield-check: Audit-first by design
    Four modes from one configuration: `audit` (read-only check), `enforce` (fix drift), `destroy` (tear down), `comply` (audit + full evidence). Every resource records `compliant` / `non_compliant` / `error` with timing data. Pipe `get_report_json` anywhere — S3, SSM Compliance, your SIEM.

</div>

## See it in action

=== "Linux"

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

=== "Windows"

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

## Where to go next

<div class="grid cards" markdown>

- ### :material-sitemap: [Concepts](concepts/index.md)
    The "why" — design tenets, value proposition, the AWS-native moat — plus deep-dives into modes, resources, handlers, and reporting. Start here if you're evaluating.

- ### :material-rocket-launch: [Quick Start](quickstart.md)
    Install the library, write your first configuration, run it via SSM. Five minutes.

- ### :material-book-open-variant: [Resources](resources/index.md)
    The reference manual. 15 Linux + 15 Windows primitives plus the generic `DscResource` wrapper. Each page has syntax, properties, examples, destroy-mode behaviour.

- ### :material-truck-delivery: [Deploying](deploying/index.md)
    Push configurations through SSM — by instance ID, by tag, via Resource Group, scheduled with State Manager, or org-wide with Quick Setup / StackSets.

- ### :material-folder-multiple: [Examples](examples/index.md)
    NGINX, Apache, IIS, MSSQL, WSFC, post-build hardening, vendor-installer download-and-install. All EC2-validated.

- ### :material-text-box-multiple: [Reference](reference/cli.md)
    CLI commands, the report JSON schema, and the changelog.

</div>

## License & contributing

[Apache 2.0](https://github.com/aws-samples/sample-ssm-converge/blob/main/LICENSE). Issues and PRs welcome on [GitHub](https://github.com/aws-samples/sample-ssm-converge).
