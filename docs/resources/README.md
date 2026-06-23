# SSM Converge - Resource Reference

Complete reference for every built-in resource shipped with SSM Converge.

> **Prefer one big file?** A unified [`USAGE.md`](USAGE.md) is generated from these per-resource pages, with a full table of contents, stable anchors, and every resource on one page. Regenerate with `bash docs/resources/build-usage.sh`.

Resources are the vocabulary of the DSL. Each resource declares *what* you want the system to look like; SSM Converge figures out *how* to get there, idempotently, and records the result.

Every resource shares the same contract:

- **Check** the current state on the host.
- **Apply** the change only when the state differs (skipped in `audit` mode).
- **Record** the outcome (`compliant` / `non_compliant` / `error`) for the compliance report.
- **Notify** handlers if the resource changed and specified a handler.

Resources are platform-specific. Linux configurations source `lib.sh` and get bash functions with lowercase-underscore names (`package`, `file`, `line_in_file`). Windows configurations dot-source `lib.ps1` and get PowerShell functions with PascalCase names (`Package`, `File`, `WindowsService`).

## Index

### Linux (`src/linux/resources/`)

| Resource | One-liner | Page |
|----------|-----------|------|
| `package` | Install, upgrade, or remove software via the distro's package manager | [linux/package.md](linux/package.md) |
| `file` | Manage a single file: content, ownership, mode, optional remote source (S3 or HTTPS with auth + checksum) | [linux/file.md](linux/file.md) |
| `file_content` | Heredoc-friendly sibling of `file` for inline multi-line content | [linux/file_content.md](linux/file_content.md) |
| `execute` | Run an arbitrary shell command, idempotently (guards: `creates`, `only_if`, `not_if`) | [linux/execute.md](linux/execute.md) |
| `directory` | Create, remove, or enforce ownership/mode on a directory | [linux/directory.md](linux/directory.md) |
| `service` | Start/stop/restart a service and manage its boot-time state | [linux/service.md](linux/service.md) |
| `user` | Create or remove a local user account; enforce shell/home/groups | [linux/user.md](linux/user.md) |
| `group` | Create or remove a local group; manage its membership | [linux/group.md](linux/group.md) |
| `sysctl` | Set (and persist) a kernel parameter | [linux/sysctl.md](linux/sysctl.md) |
| `cron` | Create, update, or remove a cron entry for a given user | [linux/cron.md](linux/cron.md) |
| `line_in_file` | Ensure a line exists or is absent in a text file | [linux/line_in_file.md](linux/line_in_file.md) |
| `mount_fs` | Mount a filesystem, optionally persisting the entry to fstab | [linux/mount_fs.md](linux/mount_fs.md) |
| `timezone` | Set the system timezone | [linux/timezone.md](linux/timezone.md) |
| `locale` | Set the system LANG locale | [linux/locale.md](linux/locale.md) |
| `host_entry` | Manage entries in /etc/hosts | [linux/host_entry.md](linux/host_entry.md) |

### Windows (`src/windows/resources/`)

| Resource | One-liner | Page |
|----------|-----------|------|
| `File` / `File-Content` | Manage a single file, with optional remote source (S3 or HTTPS with auth + checksum) or inline content | [windows/File.md](windows/File.md) |
| `Directory` | Create or remove a directory | [windows/Directory.md](windows/Directory.md) |
| `Package` | Install/uninstall software via winget, Chocolatey, or Get-Package | [windows/Package.md](windows/Package.md) |
| `Execute` | Run an arbitrary command, idempotently (guards: `-Creates`, `-OnlyIf`, `-NotIf`) | [windows/Execute.md](windows/Execute.md) |
| `WindowsService` | Manage service state (Running/Stopped/Restarted) and startup type | [windows/WindowsService.md](windows/WindowsService.md) |
| `RegistryKey` | Manage registry keys and values | [windows/RegistryKey.md](windows/RegistryKey.md) |
| `WindowsFeature` | Install/uninstall Windows Server roles and features | [windows/WindowsFeature.md](windows/WindowsFeature.md) |
| `PowerShellModule` | Install/uninstall PowerShell modules (PSGallery or custom repo) | [windows/PowerShellModule.md](windows/PowerShellModule.md) |
| `Certificate` | Import / remove certificates in a cert store | [windows/Certificate.md](windows/Certificate.md) |
| `LocalUser` | Manage local Windows users | [windows/LocalUser.md](windows/LocalUser.md) |
| `LocalGroup` | Manage local Windows groups and membership | [windows/LocalGroup.md](windows/LocalGroup.md) |
| `HostEntry` | Manage entries in `C:\Windows\System32\drivers\etc\hosts` | [windows/HostEntry.md](windows/HostEntry.md) |
| `EnvironmentVariable` | Manage Machine/User/Process env vars | [windows/EnvironmentVariable.md](windows/EnvironmentVariable.md) |
| `ScheduledTask` | Manage Windows Scheduled Tasks | [windows/ScheduledTask.md](windows/ScheduledTask.md) |
| `DscResource` | **Generic wrapper** for any existing DSC resource (FailoverClusterDsc, ActiveDirectoryDsc, SqlServerDsc, ...) | [windows/DscResource.md](windows/DscResource.md) |

## Common conventions

### States

Linux resources take a bare desired state as the second positional argument:

```bash
package 'nginx' installed
file    '/etc/motd' present
service 'nginx' running enabled
```

Windows resources take an explicit `State` parameter, matching the PowerShell convention:

```powershell
Package        'nginx' Installed
File           'C:\motd' Present
WindowsService 'nginx' Running -StartupType Automatic
```

Both accept a state-neutral `present`/`absent` pair as an alias for resource-specific names (`installed`/`uninstalled`, `running`/`stopped`).

### Destroy mode

When the library is invoked with `DSC_MODE=destroy`, most resources flip their desired state:

| Declared | Destroy-mode effective |
|----------|------------------------|
| `present` / `installed` / `mounted` | `absent` |
| `absent` / `uninstalled` / `removed` | `present` |
| `running` | `stopped` |
| `enabled` | `disabled` |

Resources that have no safe inverse (`sysctl`, `timezone`, `locale`) are skipped in destroy mode and logged as such.

### Handler notification

Resources that change state can `notify` a handler. The handler runs exactly once at the end of the configuration, regardless of how many resources triggered it:

```bash
file '/etc/nginx/nginx.conf' present \
  source 's3://cfg/nginx.conf' \
  notify 'reload-nginx'

service 'nginx' running enabled

handler 'reload-nginx' systemctl reload nginx
```

```powershell
File 'C:\inetpub\wwwroot\web.config' Present `
     -Source 's3://cfg/web.config' `
     -Notify 'restart-iis'

WindowsService 'W3SVC' Running -StartupType Automatic

Handler 'restart-iis' Restart-Service W3SVC
```

### Return codes and compliance status

Every resource records one of three statuses in the run's compliance report:

| Status | When |
|--------|------|
| `compliant` | Current state matches desired state (may or may not have been fixed this run) |
| `non_compliant` | Drift detected in `audit` mode, OR apply attempted and could not converge |
| `error` | Check or apply failed (missing binary, permission denied, invalid argument) |

The overall run exits:

- `0` - success (no errors, no drift-in-audit)
- `1` - one or more resources reported `error`
- `2` - `audit` mode detected drift (`non_compliant` > 0)

### Property types

Most resource attributes are plain strings. Exceptions are noted on each resource's page:

- Integers: `uid`, `gid`, `dump`, `pass`, `value_data` (DWord/QWord registry values)
- Booleans: `persist`, `system`, `recursive`
- Arrays/lists: `members` (comma-separated on Linux, native array on Windows), `Members` / `MembersToInclude` / `MembersToExclude` on `LocalGroup`
- SecureString: `Password` on `LocalUser` and `Certificate`

### Debug logging

All resource activity is written to:

- Linux: `/var/log/ssm-converge.log` (or `/tmp/ssm-converge.log` when not writable)
- Windows: `C:\ProgramData\ssm-converge\ssm-converge.log` (or `%TEMP%\ssm-converge.log`)

Each line is timestamped and tagged `OK` / `CHANGED` / `DRIFT` / `ERROR` / `REBOOT`.
