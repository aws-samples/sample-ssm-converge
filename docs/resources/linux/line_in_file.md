# `line_in_file`

Ensure a specific line exists, or is absent, in a text file. Similar to Ansible's `lineinfile` module.

## Syntax

```bash
line_in_file '<path>' <state> [key value ...]
```

## Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the exact line is in the file; if a `match` regex is given, replace or insert such that no stale line matches the regex. |
| `absent` | Remove matching line(s). |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `line` | - | The exact line to ensure. Required for `present`; optional for `absent` (use `match` instead). |
| `match` | - | Regex identifying the "slot" being managed. When set, the resource also deletes any other lines that match the regex but differ from `line`. |
| `notify` | - | Handler name to fire when the file changes. |

## Compliance rule (important)

When `match` is provided, the resource is compliant only when **exactly one** line in the file:

- matches the `match` regex, **AND**
- equals the `line` string.

Any other matching-but-different line is considered stale and will be removed on enforce. This is stronger than the Ansible default and makes `line_in_file` truly idempotent when the file has e.g. a commented-out placeholder and a value set.

## Examples

SSH hardening (replace whatever's there):

```bash
line_in_file '/etc/ssh/sshd_config' present \
  line 'PermitRootLogin no' \
  match '^#?PermitRootLogin' \
  notify 'restart-sshd'

line_in_file '/etc/ssh/sshd_config' present \
  line 'PasswordAuthentication no' \
  match '^#?PasswordAuthentication' \
  notify 'restart-sshd'
```

Append without match:

```bash
line_in_file '/etc/hosts' present line '10.0.1.5 myapp.internal'
```

Delete matching lines:

```bash
line_in_file '/etc/crontab' absent match '^.*old-script\.sh'
```

## Destroy mode

`present` flips to `absent` — the line is removed.

## Notes

- If the file doesn't exist on `present`, it is created with the single desired line.
- In-place edits use GNU sed on Linux and BSD sed on macOS automatically (the resource detects `sed --version | grep GNU`).
- When both `match` and `line` are given and multiple matching lines exist, the first match is replaced in place and subsequent matches are deleted — preserving the original line's position in the file.
- For managing multiple lines in the same file, use multiple `line_in_file` calls with different `match` patterns.
