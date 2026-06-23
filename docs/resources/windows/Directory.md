# `Directory`

Create or remove a directory.

## Syntax

```powershell
Directory '<Path>' <State> [-Recursive]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Create the directory (with parents) if missing. |
| `Absent` | Remove the directory, recursively. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | Full path to the directory. |
| `-Recursive` | *off* | Reserved for future attribute-recursion. Has no effect on creation (always recursive). |

## Examples

```powershell
Directory 'C:\inetpub\wwwroot\myapp' Present
Directory 'C:\temp\old-cache' Absent
```

## Destroy mode

`Present` flips to `Absent` - the directory and its contents are deleted.

## Notes

- `Present` uses `New-Item -ItemType Directory -Force`, so intermediate parents are created.
- `Absent` uses `Remove-Item -Recurse -Force`. Contents go with the directory.
- No owner / mode enforcement; Windows ACLs are managed through `DscResource` wrapping `PSDscResources.NTFSAccessEntry` or similar if needed.
