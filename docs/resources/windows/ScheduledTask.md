# `ScheduledTask`

Manage a Windows Scheduled Task. This is the Windows analogue of the Linux [`cron`](../linux/cron.md) resource.

Tasks managed by SSM Converge are tagged with a marker in their Description (`[managed by ssm-converge]`), so unrelated tasks are left alone.

## Syntax

```powershell
ScheduledTask '<Name>' <State> `
  [-Execute <path>] [-Argument <string>] `
  [-Daily <HH:mm> | -IntervalMinutes <N>] `
  [-RunAsUser <SYSTEM|user>] `
  [-Path <taskpath>]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Create/update the task with the specified schedule + action. |
| `Absent` | Unregister the task. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Task name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Execute` | - | Executable to run. Required for `Present`. |
| `-Argument` | - | Command-line arguments. |
| `-Daily` | - | Time in `HH:mm` for a daily trigger. |
| `-IntervalMinutes` | - | Numeric interval for a repeating trigger. |
| `-RunAsUser` | `SYSTEM` | Principal to run the task as. |
| `-Path` | `\` | Task Scheduler folder path. |

Exactly one of `-Daily` or `-IntervalMinutes` must be provided for `Present`.

## Examples

Daily cleanup at 02:00 as SYSTEM:

```powershell
ScheduledTask 'Nightly-Cleanup' Present `
    -Execute  'powershell.exe' `
    -Argument '-NoProfile -File C:\scripts\cleanup.ps1' `
    -Daily    '02:00' `
    -RunAsUser 'SYSTEM'
```

Every 15 minutes:

```powershell
ScheduledTask 'Health-Check' Present `
    -Execute         'C:\scripts\health.ps1' `
    -IntervalMinutes 15 `
    -RunAsUser       'SYSTEM'
```

Remove a stale task:

```powershell
ScheduledTask 'OldBackup' Absent
```

## Destroy mode

`Present` flips to `Absent`.

## Notes

- The marker lives in the task Description; tasks you created by hand (without the marker) are left alone.
- On change, the task is unregistered and re-registered atomically. Triggers and actions are fully replaced.
- For running as a domain user, pass `-RunAsUser 'CORP\serviceuser'`. You'll need to pre-install a credential via a separate mechanism (e.g. `DscResource` with `PSDscResources.xScheduledTask` for richer credential handling).
