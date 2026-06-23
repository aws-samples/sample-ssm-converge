# `PowerShellModule`

Install or uninstall a PowerShell module via `Install-Module` (PowerShellGet).

## Syntax

```powershell
PowerShellModule '<Name>' <State> `
  [-Version <version>] `
  [-Repository <name>] `
  [-Scope <CurrentUser|AllUsers>]
```

## State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Install the module. |
| `Uninstalled` | `Absent` | Uninstall all installed versions. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Module name (e.g. `FailoverClusterDsc`, `SqlServerDsc`). |
| `-State` | *(positional 1)* | `Installed`, `Uninstalled`, `Present`, or `Absent`. |
| `-Version` | *(any)* | Pin a specific `RequiredVersion`. Drift is reported if a different version is installed. |
| `-Repository` | `PSGallery` | Source repo. |
| `-Scope` | `AllUsers` | `AllUsers` or `CurrentUser`. |

## Examples

Install the DSC modules commonly used for cluster / SQL configurations:

```powershell
PowerShellModule 'PSDscResources'        Installed
PowerShellModule 'FailoverClusterDsc'    Installed
PowerShellModule 'ComputerManagementDsc' Installed
PowerShellModule 'ActiveDirectoryDsc'    Installed
PowerShellModule 'CertificateDsc'        Installed
PowerShellModule 'SqlServerDsc'          Installed
```

Pin a specific version:

```powershell
PowerShellModule 'FailoverClusterDsc' Installed -Version '2.2.0'
```

Remove an old module:

```powershell
PowerShellModule 'AzureRM' Uninstalled
```

Install from a private repo:

```powershell
PowerShellModule 'MyInternalModule' Installed -Repository 'MyCorpRepo' -Scope AllUsers
```

## Destroy mode

`Installed` flips to `Uninstalled`.

## NuGet bootstrap

On a fresh Windows PowerShell 5.1, the first call to `Install-Module` prompts to install the NuGet provider interactively, which fails under SSM's non-interactive PowerShell. The resource silently pre-installs the NuGet provider (`Install-PackageProvider -Name NuGet -Force -Scope AllUsers`) before the first module install, so this is handled for you.

## Notes

- Uninstall removes *all* installed versions of the module.
- The `PSGallery` repository is auto-set to `Trusted` to avoid the confirmation prompt.
- Module installs go to `C:\Program Files\WindowsPowerShell\Modules\` (for `AllUsers` scope) by default.
