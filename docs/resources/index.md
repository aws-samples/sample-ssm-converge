# Resources

The vocabulary of the DSL. Every built-in resource shipped with SSM Converge has its own page below — syntax, properties, examples, destroy-mode behaviour, notes.

> **Prefer one big file?** A unified [one-page reference](USAGE.md) is generated from these per-resource pages, with a full table of contents, stable anchors, and every resource on one page.

Resources are platform-specific. Linux configurations source `lib.sh` and get bash functions with lowercase-underscore names (`package`, `file`, `line_in_file`). Windows configurations dot-source `lib.ps1` and get PowerShell functions with PascalCase names (`Package`, `File`, `WindowsService`).

Every resource shares the same contract — see [Concepts › Resources & the DSL](../concepts/resources.md) for the design rationale.

<div class="grid cards" markdown>

- ### :material-linux: Linux (15 primitives)
    `package`, `file`, `file_content`, `execute`, `directory`, `service`, `user`, `group`, `sysctl`, `cron`, `line_in_file`, `mount_fs`, `timezone`, `locale`, `host_entry`

- ### :material-microsoft-windows: Windows (15 primitives)
    `File`, `Directory`, `Package`, `Execute`, `WindowsService`, `RegistryKey`, `WindowsFeature`, `PowerShellModule`, `Certificate`, `LocalUser`, `LocalGroup`, `HostEntry`, `EnvironmentVariable`, `ScheduledTask`, **`DscResource`** (generic wrapper for any installed PSDSC module)

</div>

## Linux index

| Resource | One-liner |
|----------|-----------|
| [`package`](linux/package.md) | Install, upgrade, or remove software via the distro's package manager |
| [`file`](linux/file.md) | Manage a single file: content, ownership, mode, optional remote source (S3 / HTTPS with auth + checksum) |
| [`file_content`](linux/file_content.md) | Heredoc-friendly sibling of `file` for inline multi-line content |
| [`execute`](linux/execute.md) | Run an arbitrary shell command, idempotently (guards: `creates`, `only_if`, `not_if`) |
| [`directory`](linux/directory.md) | Create, remove, or enforce ownership/mode on a directory |
| [`service`](linux/service.md) | Start/stop/restart a service and manage its boot-time state |
| [`user`](linux/user.md) | Create or remove a local user account; enforce shell/home/groups |
| [`group`](linux/group.md) | Create or remove a local group; manage its membership |
| [`sysctl`](linux/sysctl.md) | Set (and persist) a kernel parameter |
| [`cron`](linux/cron.md) | Create, update, or remove a cron entry for a given user |
| [`line_in_file`](linux/line_in_file.md) | Ensure a line exists or is absent in a text file |
| [`mount_fs`](linux/mount_fs.md) | Mount a filesystem, optionally persisting the entry to fstab |
| [`timezone`](linux/timezone.md) | Set the system timezone |
| [`locale`](linux/locale.md) | Set the system LANG locale |
| [`host_entry`](linux/host_entry.md) | Manage entries in /etc/hosts |

## Windows index

| Resource | One-liner |
|----------|-----------|
| [`File` / `File-Content`](windows/File.md) | Manage a single file, with optional remote source (S3 / HTTPS with auth + checksum) or inline content |
| [`Directory`](windows/Directory.md) | Create or remove a directory |
| [`Package`](windows/Package.md) | Install/uninstall software via winget, Chocolatey, or Get-Package |
| [`Execute`](windows/Execute.md) | Run an arbitrary command, idempotently (guards: `-Creates`, `-OnlyIf`, `-NotIf`) |
| [`WindowsService`](windows/WindowsService.md) | Manage service state (Running / Stopped / Restarted) and startup type |
| [`RegistryKey`](windows/RegistryKey.md) | Manage registry keys and values |
| [`WindowsFeature`](windows/WindowsFeature.md) | Install/uninstall Windows Server roles and features |
| [`PowerShellModule`](windows/PowerShellModule.md) | Install/uninstall PowerShell modules (PSGallery or custom repo) |
| [`Certificate`](windows/Certificate.md) | Import / remove certificates in a cert store |
| [`LocalUser`](windows/LocalUser.md) | Manage local Windows users |
| [`LocalGroup`](windows/LocalGroup.md) | Manage local Windows groups and membership |
| [`HostEntry`](windows/HostEntry.md) | Manage entries in `C:\Windows\System32\drivers\etc\hosts` |
| [`EnvironmentVariable`](windows/EnvironmentVariable.md) | Manage Machine/User/Process env vars |
| [`ScheduledTask`](windows/ScheduledTask.md) | Manage Windows Scheduled Tasks |
| [`DscResource`](windows/DscResource.md) | **Generic wrapper** for any existing DSC resource (FailoverClusterDsc, ActiveDirectoryDsc, SqlServerDsc, ...) |

## Common conventions

### States

Linux resources take a bare desired state as the second positional argument:

```bash
package 'nginx' installed
file    '/etc/motd' present
service 'nginx' running enabled
```

Windows resources take an explicit `State` parameter:

```powershell
Package        'nginx' Installed
File           'C:\motd' Present
WindowsService 'nginx' Running -StartupType Automatic
```

Both accept a state-neutral `present`/`absent` pair as an alias for resource-specific names.

### Destroy mode

When the library is invoked with `DSC_MODE=destroy`, most resources flip their desired state. See [Concepts › Modes](../concepts/modes.md#destroy-mode-what-gets-flipped) for the flip table.

### Handler notification

Resources that change state can `notify` a handler. The handler runs once at the end of the configuration. See [Concepts › Handlers & Notifications](../concepts/handlers.md).

### Compliance status

Three values in the report: `compliant`, `non_compliant`, `error`. See [Concepts › Compliance Reporting](../concepts/reporting.md#statuses).
