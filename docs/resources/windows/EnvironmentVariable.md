# `EnvironmentVariable`

Manage a persistent Machine, User, or Process-scoped environment variable.

## Syntax

```powershell
EnvironmentVariable '<Name>' <State> [-Value <string>] [-Target <Machine|User|Process>] [-Path]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Ensure the variable exists with the given value. |
| `Absent` | Remove the variable. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Variable name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Value` | - | The value to set. Required for `Present`. |
| `-Target` | `Machine` | Scope: `Machine`, `User`, or `Process`. |
| `-Path` | *off* | Treat as a PATH-style list. `Value` is appended to the current variable if not already present (dedup via string match). |

## Examples

System-wide JAVA_HOME:

```powershell
EnvironmentVariable 'JAVA_HOME' Present `
    -Value  'C:\Program Files\Java\jdk-17' `
    -Target Machine
```

Append to PATH without obliterating existing entries:

```powershell
EnvironmentVariable 'PATH' Present `
    -Value  'C:\Tools;C:\Program Files\Custom' `
    -Target Machine `
    -Path
```

Remove a deprecated variable:

```powershell
EnvironmentVariable 'LEGACY_VAR' Absent
```

## Destroy mode

`Present` flips to `Absent`.

## Notes

- `Machine` target requires admin privileges (the SSM Agent runs as SYSTEM so this is fine under SSM).
- `Process` changes are visible to the current configuration run only — not persisted.
- PATH appending uses `;` as separator (Windows convention). Deduplication is string-exact, so `C:\Tools` and `C:\Tools\` are different.
- Changes take effect for new processes. Existing sessions won't see the new value until they respawn.
