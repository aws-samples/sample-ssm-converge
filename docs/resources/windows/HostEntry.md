# `HostEntry`

Manage an entry in `C:\Windows\System32\drivers\etc\hosts`.

## Syntax

```powershell
HostEntry '<IpAddress>' <State> [-Hostname '<name>'] [-HostsFile <path>]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Ensure the line `<ip> <hostname>` is in the file. |
| `Absent` | Remove any line starting with this IP. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-IpAddress` | *(positional 0)* | The IP address. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Hostname` | - | Hostname or space-separated aliases. Required for `Present`. |
| `-HostsFile` | `$env:SystemRoot\System32\drivers\etc\hosts` | Override for testing. |

## Examples

```powershell
HostEntry '10.0.1.5'  Present -Hostname 'myapp.internal'
HostEntry '10.0.1.5'  Present -Hostname 'myapp.internal myapp app-primary'
HostEntry '10.0.1.5'  Absent
```

For cluster pre-resolution:

```powershell
HostEntry '10.0.1.11' Present -Hostname 'SQL01-A SQL01-A.corp.example.com'
HostEntry '10.0.1.12' Present -Hostname 'SQL01-B SQL01-B.corp.example.com'
```

## Destroy mode

`Present` flips to `Absent`.

## Notes

- Entries are written with a tab separating IP and hostname, matching Windows's `hosts` convention.
- If the same IP appears more than once, the resource normalises to a single line on enforce. Other IPs are untouched.
- Writes the file as ASCII (required by Windows DNS client).
