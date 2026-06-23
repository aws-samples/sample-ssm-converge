# `user`

Create or remove a local user account; enforce the login shell, home directory, and supplementary groups.

## Syntax

```bash
user '<name>' <state> [key value ...]
```

## Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the user exists; optionally enforce attributes on an existing user. |
| `absent` | Remove the user (`userdel -r`, which also removes the home directory). |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `shell` | distro default | Login shell (`/bin/bash`, `/usr/sbin/nologin`, ...). |
| `groups` | *(none)* | Comma-separated list of supplementary groups (passed as `-G`). |
| `home` | `/home/<name>` | Home directory. |
| `system` | `false` | When `true`, create as a system user (`useradd -r`). |
| `uid` | *(auto)* | Force a specific UID. Only honoured on create, not on modify. |

## Examples

Service account with no login:

```bash
user 'myapp' present shell '/usr/sbin/nologin' home '/opt/myapp' system true
```

Deploy user with sudo:

```bash
group 'deploy' present
user  'deploy' present shell '/bin/bash' groups 'deploy,wheel' home '/home/deploy'
```

Tear down an old account:

```bash
user 'olduser' absent
```

## Destroy mode

`present` flips to `absent`. Both the user and the home directory are removed.

## Errors

- `creation failed` - `useradd` returned non-zero.

## Notes

- Attribute enforcement on an existing user currently checks **shell only**. Changes to `groups` and `home` on an already-existing account are applied but not independently drift-checked.
- `user` calls `useradd`, so on distros with `adduser` (e.g. Debian) the behaviour differs slightly: `useradd` doesn't create a default group named after the user. Declare a matching [`group`](group.md) if you want that.
- `absent` uses `-r` so the home directory and mail spool are removed too.
