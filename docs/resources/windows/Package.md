# `Package`

Install or uninstall software on Windows. Falls back across winget, Chocolatey, and the PowerShellGet `Package` provider (MSI).

## Syntax

```powershell
Package '<Name>' <State>
```

## State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Ensure the package is installed. |
| `Uninstalled` | `Absent` | Ensure the package is not installed. |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-Name` | *(positional 0)* The package identifier. Format depends on the detected manager (see below). |
| `-State` | *(positional 1)* One of `Installed`, `Uninstalled`, `Present`, `Absent`. |

## Detected managers

In order; the first one that's available wins:

1. **winget** - IDs are Microsoft-curated (e.g. `7zip.7zip`, `Notepad++.Notepad++`).
2. **Chocolatey** (`choco`) - IDs from community.chocolatey.org (e.g. `notepadplusplus`).
3. **Get-Package / Install-Package** (built-in) - fallback, works with MSIs.

The manager that succeeded is recorded in the compliance report's detail field.

## Examples

```powershell
Package '7zip.7zip'            Installed       # winget ID
Package 'notepadplusplus'      Installed       # choco ID
Package 'Legacy-Tool'          Uninstalled
```

## Destroy mode

`Installed` flips to `Uninstalled` and vice versa.

## Errors

- `install failed via <manager>` - the selected manager returned non-zero, or the package is still in the wrong state after the command.

## Notes

- `winget` and `choco` both need to be in the system `PATH` or the fallback kicks in.
- If winget is installed but returns "not found" for your ID, the fallback to choco is **not** automatic - we commit to the first available manager. Make sure the package ID matches the chosen manager.
- For PowerShell module installs (like DSC modules), use [`PowerShellModule`](PowerShellModule.md), not `Package`.
