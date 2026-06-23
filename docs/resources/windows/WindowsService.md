# `WindowsService`

Manage a Windows service's running state and startup type. Wraps `Get-Service`, `Start-Service`, `Stop-Service`, `Set-Service`, and `Restart-Service`.

## Syntax

```powershell
WindowsService '<Name>' <State> [-StartupType <type>] [-Notify <handler>]
```

## State

| State | Effect |
|-------|--------|
| `Running` | Start the service if stopped. |
| `Stopped` | Stop the service if running. |
| `Restarted` | Always restart (counts as a change every run). |

## Startup type (optional)

| Value | Effect |
|-------|--------|
| `Automatic` | Start at boot. |
| `Manual` | Require explicit start. |
| `Disabled` | Prevent starting. |
| `AutomaticDelayedStart` | Start at boot after a short delay. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Service short name (as reported by `Get-Service`). |
| `-State` | *(positional 1)* | Running, Stopped, or Restarted. |
| `-StartupType` | *(no change)* | Automatic / Manual / Disabled / AutomaticDelayedStart. |
| `-Notify` | - | Handler to fire on change. |

## Examples

```powershell
WindowsService 'W3SVC'   Running   -StartupType Automatic
WindowsService 'Spooler' Stopped   -StartupType Disabled
WindowsService 'W3SVC'   Restarted                              # fires every run
```

Driven by a handler:

```powershell
File 'C:\inetpub\wwwroot\web.config' Present `
     -Source 's3://cfg/web.config' `
     -Notify 'restart-iis'

Handler 'restart-iis' Restart-Service W3SVC
```

## Destroy mode

`Running` flips to `Stopped`; `Automatic` flips to `Disabled`; `Disabled` flips to `Manual`.

## Errors

- `service not found on this host` - `Get-Service -Name` returned nothing. The service isn't installed. Use [`Package`](Package.md) / [`WindowsFeature`](WindowsFeature.md) / `DscResource` to install the software that provides the service first.
- `apply failed` - post-apply state check didn't match the desired state. Usually indicates a failed startup; check the service's event log.

## Notes

- Startup-type drift is checked by reading `Win32_Service.StartMode` via CIM and normalising `Auto` - `Automatic` for comparison.
- `Restarted` is treated as "always changed." If you want to restart only when a config changes, use a handler instead.
