# SSM Converge — Requirements

## 1. Problem Statement

AWS Systems Manager Documents are procedural — they execute steps in order without built-in concepts of desired state, idempotency, or compliance reporting. Operations teams familiar with Chef, Ansible, or InSpec must install and manage additional tooling on instances to achieve declarative configuration management.

SSM Converge bridges this gap by providing a bash library that brings desired-state semantics directly into SSM Documents, leveraging the existing SSM Agent with zero additional dependencies.

## 2. Goals

1. **Desired State Management** — Operators declare the target state; the library determines and executes the minimal actions to converge.
2. **Idempotency** — Running the same configuration multiple times produces the same result with no unintended side effects.
3. **Tri-Mode Execution** — A single configuration supports `enforce` (remediate drift), `audit` (report only), and `destroy` (tear down) modes.
4. **Local Compliance Reporting** — On-instance queryable compliance state (like InSpec local reports).
5. **Customer-Owned Central Reporting** — Library provides `get_report_json()`; customer decides where the JSON goes (S3, SSM Compliance, EventBridge, custom API). Sample reporters are shipped as examples.
6. **Zero Additional Dependencies** — Runs on any instance with SSM Agent; no Ruby, Python runtimes, or agent installations required beyond what SSM provides.
7. **Familiar Syntax** — DSL reads like Chef/Ansible resources, lowering the learning curve for ops teams.
8. **Cross-Platform** — Support Linux (bash) and Windows (PowerShell) with equivalent resource providers.

## 3. Non-Goals (v1)

- Full dependency graph resolution between resources (linear execution is acceptable for v1)
- GUI/web console for authoring configurations
- Replacement for AWS Config Rules (complementary, not competitive)
- Support for container/Kubernetes workloads

## 4. Functional Requirements

### 4.1 Core Library (`lib.sh` / `lib.ps1`)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Library is sourceable via `source /opt/ssm-converge/lib.sh` in any SSM runShellScript step | P0 |
| FR-02 | Each resource function follows the pattern: `resource_type 'name' desired_state [key value...]` | P0 |
| FR-03 | Each resource internally performs CHECK (current state) then conditionally APPLY (converge) | P0 |
| FR-04 | `DSC_MODE=audit` skips all APPLY phases, only reports | P0 |
| FR-05 | `DSC_MODE=enforce` performs CHECK + APPLY when drifted | P0 |
| FR-05b | `DSC_MODE=destroy` flips desired state and converges (teardown) | P0 |
| FR-06 | All resource executions are recorded for compliance reporting | P0 |
| FR-07 | Handler mechanism: resources can notify handlers that run at end of convergence | P1 |
| FR-08 | Exit codes: 0 = success, 1 = errors present, 2 = drift in audit mode (compatible with SSM step handling) | P0 |

### 4.2 Resource Providers

| ID | Resource | States | Platform | Status |
|----|----------|--------|----------|--------|
| FR-10 | `package` | installed, uninstalled, version-pinned | Linux/Unix/macOS | ✅ |
| FR-11 | `file` | present, absent; attributes: source, owner, group, mode, content | Linux/Unix/macOS | ✅ |
| FR-11b | `file_content` | heredoc helper for multi-line content | Linux/Unix/macOS | ✅ |
| FR-12 | `directory` | present, absent; attributes: owner, group, mode, recursive | Linux/Unix/macOS | ✅ |
| FR-13 | `service` | running, stopped, restarted; enabled, disabled | Linux/Unix/macOS | ✅ |
| FR-14 | `user` | present, absent; attributes: groups, shell, home, uid, system | Linux | ✅ |
| FR-15 | `group` | present, absent; attributes: members, gid | Linux | ✅ |
| FR-16 | `cron` | present, absent; attributes: schedule, command, user | Linux | ✅ |
| FR-17 | `sysctl` | value set; attributes: key, value, persist | Linux | ✅ |
| FR-18 | `line_in_file` | present, absent; attributes: line, match | Linux/Unix/macOS | ✅ |
| FR-19 | `mount_fs` | present, absent; attributes: device, fstype, options, persist | Linux | ✅ |
| FR-20 | `timezone` | set timezone value | Linux/macOS/FreeBSD | ✅ |
| FR-21 | `locale` | set system locale | Linux | ✅ |
| FR-22 | `host_entry` | present, absent; attributes: hostname, hosts_file | Linux/Unix/macOS | ✅ |
| FR-23 | `registry_key` | present, absent; attributes: path, value_name, value_data, value_type | Windows | ✅ |
| FR-24 | `windows_feature` | installed, uninstalled; attributes: IncludeManagementTools, Source | Windows | ✅ |
| FR-25 | `windows_service` | running, stopped, restarted; startup type | Windows | ✅ |
| FR-26 | `powershell_module` | installed, uninstalled; version, repository, scope | Windows | ✅ |
| FR-27 | `certificate` | present, absent; store, thumbprint, password, exportable | Windows | ✅ |
| FR-28 | `local_user` | present, absent; password, full_name, description, disabled | Windows | ✅ |
| FR-29 | `local_group` | present, absent; members, description | Windows | ✅ |
| FR-29a | `host_entry` (windows) | present, absent; hostname | Windows | ✅ |
| FR-29b | `environment_variable` | present, absent; value, target, path | Windows | ✅ |
| FR-29c | `scheduled_task` | present, absent; execute, schedule, run_as_user | Windows | ✅ |
| FR-29d | **`dsc_resource`** | generic wrapper for `Invoke-DscResource` — enables reuse of any existing DSC resource module | Windows | ✅ |

### 4.3 Local Compliance Reporting

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-30 | Write latest compliance report to `/var/lib/ssm-converge/latest.json` | P0 |
| FR-31 | Maintain history in `/var/lib/ssm-converge/history/` with timestamp-based filenames | P0 |
| FR-32 | Maintain append-only drift log at `/var/lib/ssm-converge/drift.log` | P0 |
| FR-33 | Auto-rotate history (configurable, default: keep last 100 runs) | P1 |
| FR-34 | CLI tool `ssm-converge status` shows latest compliance state | P0 |
| FR-35 | CLI tool `ssm-converge history [n]` shows last N runs | P0 |
| FR-36 | CLI tool `ssm-converge drift` shows recent drift events | P0 |
| FR-37 | CLI tool `ssm-converge export` outputs InSpec-compatible JSON | P1 |

### 4.4 Central Compliance Reporting

The library provides `get_report_json()` as the primary integration point. The
customer pipes the JSON wherever it needs to go. Sample reporters under
`src/linux/reporters/` illustrate common destinations but are opt-in.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-40 | `get_report_json` returns the full report as a JSON string | P0 |
| FR-41 | Sample reporter: SSM Compliance API via `put-compliance-items` | P1 |
| FR-42 | Sample reporter: S3 (partitioned by account/region/instance/date) | P1 |
| FR-43 | Sample reporter: EventBridge drift events | P2 |
| FR-44 | Sample reporter: POST to a custom API endpoint | P2 |
| FR-45 | Each report includes: instance ID, account ID, region, profile name, run ID, timestamp | P0 |

### 4.5 SSM Document Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-50 | Library can be pre-installed in AMI at `/opt/ssm-converge/` | P0 |
| FR-51 | Library can be downloaded at runtime from S3 as first SSM step | P0 |
| FR-52 | Library can be distributed via SSM Distributor package | P1 |
| FR-53 | Generated SSM Documents are valid schema 2.2 documents | P0 |
| FR-54 | Compatible with SSM State Manager associations for scheduled execution | P0 |

## 5. Non-Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| NF-01 | Library execution adds < 5 seconds overhead beyond actual resource operations | P0 |
| NF-02 | No network calls during CHECK phase (except for S3 source hash comparison) | P1 |
| NF-03 | Graceful degradation: if central reporting fails, local report still written | P0 |
| NF-04 | All operations logged to stdout for SSM execution capture | P0 |
| NF-05 | Library size < 50KB (single file, no compilation) | P0 |
| NF-06 | Support Amazon Linux 2/2023, Ubuntu 20.04+, RHEL 8+, Windows Server 2019+ | P0 |

## 6. Report Schema

```json
{
  "schema": "ssm-converge/report/v1",
  "run_id": "string",
  "timestamp": "ISO-8601",
  "instance_id": "string",
  "account_id": "string",
  "region": "string",
  "profile": "string",
  "mode": "enforce|audit|destroy",
  "summary": {
    "total": "int",
    "compliant": "int",
    "non_compliant": "int",
    "errors": "int",
    "changed": "int",
    "compliance_pct": "float"
  },
  "resources": [
    {
      "resource": "type/name",
      "status": "compliant|non_compliant|error",
      "changed": "bool",
      "detail": "string",
      "timestamp": "ISO-8601",
      "run_id": "string",
      "check_duration_ms": "int",
      "apply_duration_ms": "int"
    }
  ]
}
```

## 7. Comparison with Existing Tools

| Capability | Chef | Ansible | InSpec | SSM Converge |
|-----------|------|---------|--------|--------------|
| Agent required | Chef client | SSH/WinRM | InSpec gem | SSM Agent (pre-installed) |
| Language | Ruby DSL | YAML + Jinja | Ruby DSL | Bash/PowerShell |
| Desired state | ✓ | ✓ | Audit only | ✓ |
| Idempotent | ✓ | ✓ | N/A | ✓ |
| Remediation | ✓ | ✓ | ✗ | ✓ (enforce mode) |
| Audit only | ✓ (why-run) | ✓ (check) | ✓ | ✓ (audit mode) |
| AWS native compliance | ✗ | ✗ | ✗ | ✓ (SSM Compliance) |
| Cross-account | Complex | Complex | Complex | Native (SSM) |
| Scheduling | Chef server | AWX/Tower | External | State Manager |
| Local reporting | Chef cache | ✗ | ✓ | ✓ |
| Central reporting | Chef Automate | AWX | Automate/custom | SSM + S3 + EventBridge |

## 8. Milestones

### v0.1.0 - Linux Core Library ✅ SHIPPED 2026-05-08
- [x] `lib.sh` with engine (check/apply pattern, mode handling, handlers)
- [x] 14 Linux resource providers: package, file, file_content, service, directory, user, group, sysctl, cron, line_in_file, mount, timezone, locale, host_entry
- [x] Local compliance reporting (latest.json, history, drift.log)
- [x] CLI tool: `ssm-converge status`, `history`, `drift`, `export`, `run`, `check`, `comply`, `destroy`
- [x] `destroy` mode (Chef-style teardown)
- [x] `comply` mode (full detailed compliance report)
- [x] `get_report_json()` - customer-owned report delivery
- [x] Debug logging
- [x] Per-resource error detection
- [x] Cross-platform Linux/Unix/macOS support (9 package managers, 6 init systems)
- [x] End-to-end testing on Amazon Linux 2023 via SSM Run Command
- [x] Sample reporters: SSM Compliance API (live-validated), S3, EventBridge
- [x] SSM Documents: `SSMConverge-Install`, `SSMConverge-Run`
- [x] SSM Distributor package (install/uninstall lifecycle validated)

### v0.1.1 - Windows Port + Reorganisation ✅ SHIPPED 2026-05-08
- [x] `lib.ps1` PowerShell core library with full mode + handler + reporting parity
- [x] 14 Windows resource providers: File / File-Content, Directory, Package (winget/choco/Get-Package), WindowsService, RegistryKey, WindowsFeature, PowerShellModule, Certificate, LocalUser, LocalGroup, HostEntry, EnvironmentVariable, ScheduledTask
- [x] **Generic `DscResource` wrapper** - invoke any existing DSC resource through the SSM Converge pipeline
- [x] PowerShell CLI (`ssm-converge.ps1`) with same command surface
- [x] End-to-end testing on Windows Server 2022 via SSM Run Command
- [x] Windows examples: IIS, WSFC prereqs, MSSQL standalone, MSSQL FCI baseline
- [x] Repo reorganisation: parallel `linux/` + `windows/` trees under `src/`, `examples/`, `tests/`
- [x] Cross-platform Distributor build script (Linux + Windows zips from one manifest)

### v0.2 - Production Hardening (planned)
- [ ] Windows `install.ps1` / `uninstall.ps1` for Distributor cross-platform install
- [ ] SQL Server end-to-end install validation (with installer media in S3)
- [ ] Two-node WSFC cluster creation validation
- [ ] Unit test suite for resource providers (bash + PowerShell)
- [ ] More Windows resources: IIS site, ActiveDirectory helpers, BitLocker, FirewallRule
- [ ] Performance benchmarks on fleets
- [ ] Blog post + internal socialisation

### v1.0 - General Availability
- [ ] Security review
- [ ] Documentation site
- [ ] CI / CD pipeline
- [ ] Versioned release process
- [ ] Optional: engine spin-out as a generic OSS library
