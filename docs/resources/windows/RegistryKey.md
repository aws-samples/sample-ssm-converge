# `RegistryKey`

Manage a registry key or a value under it.

## Syntax

```powershell
RegistryKey '<Path>' <State> `
  [-ValueName <name>] `
  [-ValueData <data>] `
  [-ValueType <String|DWord|QWord|Binary|MultiString|ExpandString>]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Ensure the key exists; if a `-ValueName` is given, ensure the value is set to `-ValueData` of the given type. |
| `Absent` | Remove the value (if `-ValueName` is given) or the whole key. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | PowerShell-style registry path (`HKLM:\SOFTWARE\MyApp`). |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-ValueName` | - | Name of the value under the key. Omit to manage just the key. |
| `-ValueData` | - | The data to set. Required when `-ValueName` is given on `Present`. |
| `-ValueType` | `String` | `String`, `DWord`, `QWord`, `Binary`, `MultiString`, `ExpandString`. |

## Examples

Create a key with a DWORD value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\MyApp' Present `
    -ValueName 'Version' -ValueData '1.2.3' -ValueType String

RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
    -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord
```

Just create the key, no value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany' Present
```

Remove a single value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\MyApp' Absent -ValueName 'LegacyFlag'
```

Remove the whole key (and all values under it):

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\LegacyApp' Absent
```

## Destroy mode

`Present` flips to `Absent`. If the resource was managing just a value, only that value is removed; if it was managing a whole key, the key is removed recursively.

## Notes

- `-Path` uses the PowerShell drive-style (`HKLM:\...`, `HKCU:\...`). Native registry paths like `HKEY_LOCAL_MACHINE\SOFTWARE\...` are not accepted directly.
- Data comparison is done with string coercion. For multi-value / binary types, drift is detected on any change in the string representation.
- When removing an entire key, subkeys go with it (`Remove-Item -Recurse -Force`).
