# SSM Converge

**Declarative desired-state configuration for every instance your SSM Agent already touches - Linux and Windows.**
*Declare. Converge. Comply.*

---

## The gap

AWS fleets have SSM Agent on every instance - and it runs procedural shell scripts. To move up to **desired-state configuration** (declare what the box should look like, let the system figure out how to get there), teams reach for Chef, Ansible, Puppet, or InSpec. Each brings its own agent, runtime, credential model, and fleet-management surface. For an AWS-native fleet, that's a lot of machinery for a job the SSM Agent is already positioned to do.

**SSM Converge closes that gap.** It's a small library that turns any `aws:runShellScript` or `aws:runPowerShellScript` SSM step into a declarative, idempotent, auditable configuration run - with zero additional agents, runtimes, or credentials.

---

## What the DSL looks like

A real Linux configuration, top to bottom:

```bash
source /opt/ssm-converge/lib.sh

package      'nginx' installed
package      'telnet' uninstalled
user         'www-deploy' present shell '/bin/bash' groups 'www-data'
directory    '/var/www/app' present owner 'www-deploy' mode '0755'
file         '/etc/nginx/nginx.conf' present \
               source 's3://configs/nginx.conf' owner 'root' mode '0644' \
               notify 'reload-nginx'
line_in_file '/etc/ssh/sshd_config' present line 'PermitRootLogin no' match '^#?PermitRootLogin'
sysctl       'net.core.somaxconn' value '65535'
service      'nginx' running enabled
handler      'reload-nginx' systemctl reload nginx
report_compliance
get_report_json | aws s3 cp - "s3://audit-lake/$(hostname).json"
```

Same DSL shape on Windows:

```powershell
. C:\ProgramData\ssm-converge\lib.ps1

WindowsFeature 'Web-Server' Installed -IncludeManagementTools
LocalGroup     'AppOperators' Present -Members 'CORP\deployer'
Directory      'C:\inetpub\example.com' Present
File-Content   -Path 'C:\inetpub\example.com\index.html' -Content '<h1>Hello</h1>'
RegistryKey    'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
                 -ValueName DisableServerHeader -ValueData 1 -ValueType DWord

# Reuse any existing DSC resource you already depend on:
DscResource    -Name Cluster -Module FailoverClusterDsc -Properties @{
                   Name = 'SQLCluster01'; StaticIPAddress = '10.0.1.100/24'; Ensure = 'Present'
               }

WindowsService 'W3SVC' Running -StartupType Automatic
Report-Compliance
```

Same configuration runs four ways - just flip an environment variable:

| Mode | Behaviour | Customer value |
|---|---|---|
| `enforce` | Check state, fix drift, write report | Chef/Ansible parity - remediation |
| `audit` | Check state, never change anything | InSpec parity - compliance scanning |
| `destroy` | Flip desired state and tear down | Clean uninstall on decommission |
| `comply` | Audit + full detailed pass/fail report | Board-ready compliance evidence |

---

## Why it wins

| | Chef | Ansible | InSpec | **SSM Converge** |
|---|---|---|---|---|
| Extra agent on the instance | Chef Client | SSH / WinRM daemon | InSpec gem | **None - reuses SSM Agent** |
| Runtime dependency | Ruby | Python | Ruby | **None - bash on Linux, PowerShell on Windows** |
| Declarative + idempotent | Yes | Yes | Audit only | Yes |
| Remediates drift | Yes | Yes | No | Yes |
| Windows + Linux from one package | Via separate agents | Via separate playbooks | Yes | **Yes - one SSM Distributor package, auto-routed by platform** |
| Reports compliance | Chef Automate add-on | Tower add-on | Native | **Native + customer-owned JSON delivery** |
| Cross-account fleet runs | Complex | Complex | Complex | **Native - same SSM primitives** |
| Tear-down mode | Yes (chef-client --teardown) | No | No | Yes (`destroy`) |
| Reuses existing DSC resources | No | No | No | **Yes - `DscResource` primitive wraps any DSC module** |
| Authoring surface | Ruby DSL | YAML + Jinja2 | Ruby DSL | **Bash on Linux, PowerShell on Windows** |

---

## The advantages that matter to leadership

**1. Zero adoption friction.** Any team with EC2 + SSM Agent can try it in 5 minutes. There's nothing to install on the instance beyond the library itself - a ~35 KB zip delivered via SSM Distributor.

**2. AWS-native from day one.** Fleet installs go through `AWS-ConfigureAWSPackage`. Scheduled drift detection goes through State Manager. Compliance results publish to the SSM Compliance API and show up in the Systems Manager console without a second tool. One IAM model, one audit trail, one console.

**3. Nothing to host.** No Chef server, no Ansible Tower, no InSpec controller. S3 holds the library; SSM runs it; CloudWatch collects the logs. The blast radius of the whole system is one bucket and one IAM role.

**4. Composable compliance reporting.** The library produces a standard JSON report (`get_report_json` / `Get-ReportJson`) and leaves delivery to the customer. Ship it to SSM Compliance for operators, to an S3 audit lake for auditors, to an internal GRC API for security - all from the same run, no forks in the library.

**5. Reuses existing DSC investment on Windows.** The `DscResource` primitive wraps `Invoke-DscResource` - so your existing FailoverClusterDsc, ActiveDirectoryDsc, SqlServerDsc, ComputerManagementDsc configurations drop in without a rewrite. You get SSM Converge's audit mode, destroy mode, drift reporting, and SSM-native fleet-wide execution on top of the DSC resources your team already knows.

**6. Reads like the tool it replaces.** Ops teams coming from Chef or Ansible read our examples and understand them without a tutorial. The DSL is deliberately boring.

**7. Honest about limits.** The library doesn't do dependency resolution. It's a surgical tool, not a kitchen sink. That means it's auditable, debuggable, and won't grow into a Kubernetes-scale operator by accident.

---

## What's in the box (v0.1.1)

- **Core engine** - Same pattern in bash (`lib.sh`) and PowerShell (`lib.ps1`). Check / apply / record, four modes, handler graph, compliance reporting, IMDSv2-aware metadata.
- **28 resource primitives** - 14 on Linux (package, file, directory, service, user, group, sysctl, cron, line_in_file, mount_fs, timezone, locale, host_entry, file_content), 14 on Windows (File, Directory, Package, WindowsService, RegistryKey, WindowsFeature, PowerShellModule, Certificate, LocalUser, LocalGroup, HostEntry, EnvironmentVariable, ScheduledTask, plus the generic DscResource wrapper).
- **CLI** - `ssm-converge run | check | destroy | comply | status | history | drift | export` on both platforms.
- **Delivery** - SSM Distributor package with `AWS-ConfigureAWSPackage` (one manifest, two zips, auto-routed by platform), SSM Run Command documents for inline configurations, AMI-baked install for golden images.
- **Reporters** - SSM Compliance API (live-validated, items visible in the SSM console), S3 audit lake, EventBridge drift events.
- **Examples that actually run** - Linux: nginx, Apache httpd, CIS security hardening, post-build OS baseline. Windows: IIS (fully tested), WSFC node prep (tested to DSC-module-ready), MSSQL standalone + FCI baselines (tested to pre-install).
- **Tested end-to-end** - Amazon Linux 2023 and Windows Server 2022 via SSM Run Command. All four modes, install/uninstall/reinstall lifecycle via Distributor, compliance items landing in the live SSM Compliance API, DSC wrapper proven against a live DSC resource.

---

## The customer story in one sentence

*"If your instances have SSM Agent, you already have desired-state configuration - just turn it on."*

## The three asks for leadership

1. **Bless it for internal use** - we have field SAs who could ship this to customers today as a proof-point for SSM's extensibility. Particularly compelling for customers who have existing DSC configurations they don't want to rewrite.
2. **Open-source in Q3** - alongside a blog post. Positions AWS as investing in the same space Chef and Ansible occupy, without fighting those tools directly.
3. **Fund v0.2 production hardening** - Windows Distributor hooks, full SQL Server install validation, two-node cluster create, unit test suite, CI pipeline. 1-2 engineer-weeks.

---

**Code:** `[internal]/ssm-converge`  |  **Status:** v0.1.1 - Linux + Windows, EC2-validated  |  **Contact:** `platform-team@`
