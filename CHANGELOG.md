# Changelog

All notable changes to SSM Converge.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-05-13

New `execute` resource on both platforms and major upgrade to `file` (HTTPS, authentication, checksum verification). Together they unlock the canonical "download artifact + run silent installer" pattern for vendor MSIs, EXEs, .deb / .rpm packages, and tarballs - without leaving the DSL.

### Added

**`execute` / `Execute` resource** (Linux + Windows)
- Run an arbitrary shell command, idempotently. Idempotency comes from one of three guards: `creates` (skip if path exists), `not_if` (skip if shell test passes), `only_if` (run only if shell test passes)
- Optional `user`, `cwd`, `env`, `timeout`, `notify`. Windows adds `-Interpreter` (`powershell` | `pwsh` | `cmd`) for native installers like `msiexec`
- Audit mode reports `non_compliant: would run` without actually running. Destroy mode is a no-op (no implicit "undo")
- Failed-command stdout/stderr captured to the debug log (first 2000 chars)

**`file` / `File` enhancements** (Linux + Windows)
- New `source` schemes: `https://`, `http://`, `file://`, and bare absolute path (in addition to existing `s3://`)
- New `checksum` / `-Checksum` property: SHA-256 expected hash. Verifies the downloaded file and detects drift on subsequent runs
- New auth knobs for HTTPS sources: `auth_bearer` / `-AuthBearer`, `auth_basic` / `-AuthBasic`, `header` (repeatable on Linux) / `-Headers` (hashtable on Windows)
- Linux: HTTP fetcher uses curl preferred (with `-K` config-file pattern to keep tokens out of `ps`), falls back to wget. Windows: `Invoke-WebRequest` with TLS 1.2 forced

**Examples**
- `examples/linux/install-vendor-package.sh` - public HTTPS, authenticated HTTPS, and S3 download patterns, all paired with `execute` and a `creates`/`not_if` guard
- `examples/windows/install-vendor-msi.ps1` - same three scenarios for MSIs, plus a fourth showing InnoSetup/NSIS-style EXE installers

**Documentation**
- New per-resource pages: `docs/resources/linux/execute.md`, `docs/resources/windows/Execute.md`
- `docs/resources/linux/file.md` and `docs/resources/windows/File.md` rewritten with the new HTTPS / auth / checksum properties, security notes, and idempotency model table
- `docs/resources/README.md` index updated; `build-usage.sh` regenerates `USAGE.md` with the new resources
- New `docs/deployment.md` - end-to-end guide for deploying configurations via SSM: documents (generic runner + baked-in), targeting (instance IDs, tags, Resource Groups), scheduling with State Manager, org-wide rollout (Quick Setup / StackSets / cross-account), and an operational checklist

**Tests**
- `tests/linux/test_execute_and_download.sh` - 14 assertions covering: `creates` first-pass run, `creates` second-pass skip, `not_if` skip, `only_if` run, failure -> `error`, checksum mismatch -> `error`, checksum match -> `compliant`, HTTPS download (network-permitting)

## [0.1.1] - 2026-05-08

Windows port, repo reorganisation into per-OS trees, four new Windows examples, and real-world bug fixes found during end-to-end validation.

### Added

**Windows library** (`src/windows/lib.ps1`)
- Full PowerShell port of the core engine: modes (enforce / audit / destroy / comply), handlers, local compliance reporting, `Get-ReportJson`, IMDSv2-aware instance metadata
- Reboot tracking: resources can call `Request-Reboot` and configurations check `Test-RebootRequired` at the end
- Same CLI surface via `cli/ssm-converge.ps1`: `run`, `check`, `destroy`, `comply`, `status`, `history`, `drift`, `export`, `version` (`--version` / `-v`), `help` (`--help` / `-h`)

**Windows resource providers** (14)
- `File`, `File-Content`, `Directory`, `Package`, `WindowsService`, `RegistryKey`
- `WindowsFeature` (ServerManager), `PowerShellModule` (Install-Module + silent NuGet bootstrap), `Certificate` (Import-PfxCertificate / Import-Certificate)
- `LocalUser`, `LocalGroup`, `HostEntry`, `EnvironmentVariable`, `ScheduledTask`
- **`DscResource`** — generic wrapper around `Invoke-DscResource` that brings any existing DSC resource (FailoverClusterDsc, ComputerManagementDsc, ActiveDirectoryDsc, SqlServerDsc, PSDscResources, CertificateDsc, NetworkingDsc, ...) through SSM Converge's check / apply / report pipeline

**Windows examples** (`examples/windows/`)
- `iis-webserver.ps1` — IIS from bare Windows, fully testable with primitives only
- `wsfc-cluster.ps1` — Failover Cluster node prep + cluster create via `DscResource -Module FailoverClusterDsc`
- `mssql-server.ps1` — Standalone SQL Server via `DscResource -Module SqlServerDsc` with primitives for prerequisites
- `mssql-fci-baseline.ps1` — MSSQL FCI node baseline demonstrating how to port existing DSC-based configurations

**Repo reorganisation**
- `src/` split into `src/linux/` + `src/windows/` with parallel `resources/` and (for Linux) `reporters/` layout
- `examples/` split into `examples/linux/` + `examples/windows/`, with `linux/reference/` for untested starting points
- `tests/` split into `tests/linux/` + `tests/windows/`
- `cli/` keeps both CLIs at the top level (same short install path on each OS)
- `distributor/build-package.sh` now produces a **cross-platform** SSM Distributor package: one manifest, Linux amd64/arm64 zips, and a Windows amd64 zip
- `distributor/install.ps1` and `distributor/uninstall.ps1` - Windows hooks for `AWS-ConfigureAWSPackage`. Install copies lib.ps1, resources, and CLI into `C:\ProgramData\ssm-converge\`; uninstall removes library files but preserves compliance history (`latest.json`, `history\`, `drift.log`, `ssm-converge.log`)

**Documentation**
- README rewritten for cross-platform: side-by-side Quick Start, Windows resource table, `DscResource` highlighted, Windows install paths documented
- `docs/one-pager.md` earlier added for leadership review
- This CHANGELOG entry
- `examples/README.md` and `examples/linux/reference/README.md` refreshed with the new layout

### Fixed during EC2 validation (v0.1.1 session)

- **`WindowsFeature` reported `InstallPending` as error**. On Windows Server, features that need a reboot finish install into the `InstallPending` state, not `Installed`. The resource now treats `InstallPending` as installed for idempotency and records a reboot request.
- **`PowerShellModule` failed in SSM's non-interactive PowerShell**. `Install-Module` prompts to bootstrap the NuGet package provider on first use, which fails under `AWS-RunPowerShellScript`. The resource now pre-installs the provider with `Install-PackageProvider -Force -Scope AllUsers` before any module install.
- **`lib.ps1` parse failure on Windows PowerShell 5.1** caused by UTF-8 box-drawing / em-dash characters in string literals. PowerShell 5.1 reads files as Windows-1252 by default and garbled the multi-byte sequences. All `.ps1` files are now pure ASCII (boxes drawn with `=` and `-`). Subsequent linting sweeps should re-check this — the library can regress easily if a typographic character is pasted in.
- **CLI `-v` short flag printed help text** instead of the version. Fixed by adding `-v` and `--version` as explicit cases in the command switch.

### Validated end-to-end on Windows Server 2022

| Example | Audit | Enforce | Notes |
|---|---|---|---|
| `iis-webserver.ps1` | 14 checks / 13 drift / 1 error (W3SVC not installed yet) | 14/14 ok, 5 changed; second run 0 changed | HTTP GET / returns 200 |
| `wsfc-cluster.ps1` prereqs | 8 checks / 7 drift / 1 error (DSC module absent) | 7/7 ok, 2 changed; Failover-Clustering installed, FailoverClusterDsc v2.2.0, ClusterAdmins group present | Cluster create requires second node + domain, not attempted on single-node test |
| `mssql-server.ps1` | 12 checks / 7 drift / 3 error (SqlServerDsc absent, SQL services absent, D:\ missing) | Not attempted — SQL Server installer media staging is out of scope for the test instance | Audit correctly catalogs the full gap |
| Resource sweep (all 14 resources + DscResource wrapper) | 8/8 resources loaded, drift detected correctly on 7, `DscResource` against PSDesiredStateConfiguration reports `[OK]` | — | Generic DSC wrapper proven |
| **Windows Distributor install/uninstall/reinstall via `AWS-ConfigureAWSPackage`** | — | Install -> 14 resources placed, CLI reports v0.1.0, smoke config 6/6 ok 5 changed, second run 6/6 ok 0 changed; Uninstall -> library removed, compliance history preserved (19 history entries); Reinstall -> clean | Cross-platform Distributor package now covers both Linux and Windows targets |

### Known limitations (Windows)

- **SQL Server install** needs the installer media staged in S3 and a service account with network access — the `mssql-server.ps1` example documents the shape but install was not run end-to-end on the test instance
- **Cluster creation** needs two nodes in the same AD domain — the `wsfc-cluster.ps1` example runs prerequisites fully but actual cluster creation was not attempted
- **Non-ASCII characters in `.ps1` files** will cause parse errors on Windows PowerShell 5.1. Contributors should keep library files pure ASCII; the linter sweep is part of the pre-push checklist

---

## [0.1.0] - 2026-05-08

Initial release. Linux bash library + CLI + SSM Distributor package, validated end-to-end on Amazon Linux 2023.

### Added

**Core library** (`src/lib.sh`)
- Declarative resource DSL with check/apply pattern
- Four execution modes: `enforce` (default), `audit`, `destroy`, and `comply`
- Handler system — resources notify handlers that run at the end of convergence
- Local compliance reporting: `/var/lib/ssm-converge/latest.json`, `history/`, `drift.log`
- `get_report_json()` — returns the full run as a JSON string for customer-owned delivery
- IMDSv2-aware instance metadata lookup
- Debug log at `/var/log/ssm-converge.log` (falls back to `/tmp` when not writable)

**Linux resource providers** (14)
- `package` — apt, dnf, yum, zypper, apk, brew, pkg (FreeBSD), pkgin, pkg_add
- `file`, `file_content`, `directory` — content, owner, group, mode, S3 source
- `service` — systemd, openrc, sysvinit, rc.d (FreeBSD), SMF (Solaris), launchctl (macOS)
- `user`, `group` — with shell, home, groups, uid, gid, members
- `sysctl` — with optional persistence to `/etc/sysctl.d/`
- `cron` — with SSM Converge marker for idempotent updates
- `line_in_file` — with `match` regex support
- `mount_fs` — with fstab persistence
- `timezone`, `locale`, `host_entry`

**CLI** (`cli/ssm-converge`)
- `run <config>`, `check <config>`, `destroy <config>`, `comply <config>`
- `status`, `history [n]`, `drift`, `export` (InSpec-compatible JSON)
- `version` / `--version` / `-v`
- `help` / `--help` / `-h`

**Distribution**
- `SSMConverge-Install` SSM document — installs the library from S3
- `SSMConverge-Run` SSM document — runs an inline base64-encoded configuration
- `distributor/` — SSM Distributor package with build script, install/uninstall hooks, and manifest. Installs via `AWS-ConfigureAWSPackage`

**Sample reporters** (`src/reporters/`)
- `ssm_compliance.sh` — pushes items to the SSM Compliance API (validated end-to-end)
- `s3.sh` — writes partitioned JSON to an S3 audit lake
- `eventbridge.sh` — emits drift events on non-compliant runs

**Examples (Linux)**
- Validated: `nginx-webserver.sh`, `webserver-apache.sh`, `os-post-build.sh`, `security-hardening.sh`
- Reference (needs adaptation): `webserver-baseline.sh`, `apache-tomcat.sh`, `postgresql-server.sh`, `app-deploy.sh`
- Two SSM Documents demonstrating fleet run + audit patterns

**Tests**
- `test_local.sh` — broad smoke test with 11 resources
- `test_idempotent.sh` — asserts second-run produces 0 changes
- `test_destroy.sh` — asserts destroy mode flips and removes resources
- `test_lif_idempotency.sh` — regression test for line_in_file multi-run
- `test_sysctl_idempotency.sh` — regression test for space-separated values

### Fixed during v0.1 EC2 validation

- **IMDSv2 support** — metadata lookup now uses a cached session token. Previously returned `unknown` for account_id / region / instance_id on all modern AMIs (HttpTokens=required).
- **`sysctl` whitespace handling** — space-separated values like `net.ipv4.ip_local_port_range = 32768 60999` now compare correctly. Previously stripped all whitespace and collapsed `32768 60999` into `3276860999`, reporting perpetual drift.
- **`line_in_file` idempotency** — reworked compliance rule to "exact line present AND no other line matches the regex." Previously re-fired `sed` every run even when the file was already correct. Also fixed GNU vs BSD `sed -i` portability.
- **File / directory mode `0000`** — `stat -c %a` returns `0` for mode 0000; normalizer now zero-pads to 4-digit octal so `0000` vs `0600` is compared correctly.
- **SSM Compliance reporter** — fixed the Items schema (flat `Details`), Id sanitization (alphanumerics and underscores only), and compliance type naming (no hyphens, no underscores because `Foo_bar` is parsed as type + subtype).
- **`SSMConverge-Run` document** — switched from `StringList` parameter to base64-encoded String to sidestep SSM's StringList interpolation issues with embedded heredocs.
- **sysctl recursion** — the resource called the shell function recursively instead of the system `sysctl` binary, causing the SSM Agent to hang. Resolved with cached `_SYSCTL_BIN` path lookup.

### Known limitations

- **`cron` resource** — marker-based entry detection is idempotent, but `os-post-build.sh` showed "created" on repeat runs in one scenario. Investigating.
- **`/etc/motd` and `/etc/issue.net` on AL2023** — some base AMIs rewrite these back to `0777` via tmpfiles, causing a harmless "converged" on every run.
- **PostgreSQL example** — needs >= 2 GB RAM; initdb handler is fragile across distros. Moved to `examples/reference/`.
- **`reporters/s3.sh` and `reporters/eventbridge.sh`** — logic verified with canned payloads but not end-to-end against live AWS endpoints.

### Platform support (v0.1.0)

Validated end-to-end on Amazon Linux 2023 via SSM Run Command. Written to work on:

- **Linux:** Amazon Linux 2023, Amazon Linux 2, RHEL 8+, Ubuntu 20.04+, Debian 11+, Alpine
- **Unix:** FreeBSD, OpenBSD, Solaris / illumos
- **macOS:** for local development / testing
