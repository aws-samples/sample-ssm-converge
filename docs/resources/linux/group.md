# `group`

Create or remove a local group. On create, you can seed the group's initial membership.

## Syntax

```bash
group '<name>' <state> [key value ...]
```

## Actions

| State | Effect |
|-------|--------|
| `present` | Create the group if missing. |
| `absent` | Remove the group (`groupdel`). |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `gid` | *(auto)* | Force a specific GID on creation. Only honoured on create. |
| `members` | *(none)* | Comma-separated list of users to add to the group at creation time. |

## Examples

```bash
group 'www-data' present

group 'developers' present members 'alice,bob,charlie'

group 'oldgroup' absent
```

## Destroy mode

`present` flips to `absent`.

## Notes

- `members` is only applied on **create**. To modify membership on an existing group, use [`user`](user.md) with the `groups` property on the individual users, or manage the group with a [`line_in_file`](line_in_file.md) on `/etc/group` for surgical edits.
- `absent` fails if the group is the primary group of any user. Remove those users first.
