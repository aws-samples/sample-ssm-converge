# `host_entry`

Manage a single entry in `/etc/hosts` (or any other hosts-format file).

## Syntax

```bash
host_entry '<ip>' <state> [key value ...]
```

The identity of the entry is the IP address. Only one hostname line per IP is managed.

## Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the line `<ip> <hostname>` is in the file. If an entry for `<ip>` already exists with a different hostname, it's updated. |
| `absent` | Remove any line starting with `<ip>` followed by whitespace. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `hostname` | - | Hostname or space-separated list of aliases. Required for `present`. |
| `hosts_file` | `/etc/hosts` | Alternative hosts file. Useful for tests. |

## Examples

Single hostname:

```bash
host_entry '10.0.1.5' present hostname 'myapp.internal'
```

Multiple aliases on one IP:

```bash
host_entry '10.0.1.5' present hostname 'myapp.internal myapp app-primary'
```

Remove an entry:

```bash
host_entry '10.0.1.5' absent
```

## Destroy mode

`present` flips to `absent`.

## Notes

- If the same IP appears more than once in `/etc/hosts`, the resource updates the **first** occurrence to match and leaves the rest alone. Consider using `line_in_file` for truly surgical edits.
- The Windows equivalent is `HostEntry` — same semantics, different capitalization, operates on `C:\Windows\System32\drivers\etc\hosts` by default.
