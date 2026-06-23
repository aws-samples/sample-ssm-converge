# `WindowsFeature`

Install or uninstall Windows Server roles and features via the `ServerManager` module.

Replaces the `PSDscResources.WindowsFeature` and `xPSDesiredStateConfiguration.xWindowsFeature` DSC resources.

## Syntax

```powershell
WindowsFeature '<Name>' <State> [-IncludeManagementTools] [-IncludeAllSubFeature] [-Source <sxs-path>]

# Or bulk:
WindowsFeature @('Web-Server','Web-Common-Http') Installed -IncludeManagementTools
```

## State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Install the feature. |
| `Uninstalled` | `Absent` | Uninstall the feature. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0, accepts array)* | Feature name(s) from `Get-WindowsFeature`. |
| `-State` | *(positional 1)* | `Installed`, `Uninstalled`, `Present`, or `Absent`. |
| `-IncludeManagementTools` | *off* | Pass `-IncludeManagementTools` to `Install-WindowsFeature`. |
| `-IncludeAllSubFeature` | *off* | Install all nested sub-features. |
| `-Source` | - | SxS (side-by-side) source path for offline installs. |

## Examples

IIS with management tools:

```powershell
WindowsFeature 'Web-Server' Installed -IncludeManagementTools
```

Failover clustering bundle:

```powershell
WindowsFeature 'Failover-Clustering' Installed -IncludeManagementTools
WindowsFeature 'RSAT-Clustering'     Installed
WindowsFeature 'RSAT-AD-PowerShell'  Installed
```

Multiple at once:

```powershell
WindowsFeature @(
    'Web-Server','Web-Common-Http','Web-Default-Doc',
    'Web-Static-Content','Web-Http-Logging'
) Installed -IncludeManagementTools
```

Remove a legacy feature:

```powershell
WindowsFeature 'FS-SMB1' Uninstalled
```

## Destroy mode

`Installed` flips to `Uninstalled`.

## Reboot handling

Many Windows features need a reboot to finish installation. The resource treats `Get-WindowsFeature` returning `InstallState = InstallPending` as *installed with reboot required*, calls `Request-Reboot`, and records the reboot intent. At the end of your configuration check `Test-RebootRequired`:

```powershell
WindowsFeature 'Failover-Clustering' Installed -IncludeManagementTools
Report-Compliance

if (Test-RebootRequired) {
    Write-Host "Reboot required. Restart via `aws ssm send-command -DocumentName AWS-RestartEC2Instance` and re-run."
}
```

## Errors

- `ServerManager module not available` - this isn't a Windows Server host (desktop Windows doesn't ship `ServerManager`).
- `unknown feature` - the name isn't recognised by `Get-WindowsFeature`.
- `did not converge` - post-install state is something other than `Installed` / `InstallPending`.

## Notes

- Multiple names are handled by iterating; if one fails the others still run.
- For Windows Optional Features (client-side `Enable-WindowsOptionalFeature`), use a `DscResource` wrapper around `PSDesiredStateConfiguration.WindowsOptionalFeature`.
