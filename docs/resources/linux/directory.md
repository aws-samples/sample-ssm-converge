# `directory`

Create, remove, or enforce ownership/mode on a directory.

## Syntax

```bash
directory '<path>' <state> [key value ...]
```

## Actions

| State | Effect |
|-------|--------|
| `present` | Create the directory (with parents) if missing; enforce attributes. |
| `absent` | Recursively remove the directory if it exists. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `owner` | - | User name that should own the directory. |
| `group` | - | Group name. |
| `mode` | - | Octal mode, e.g. `'0755'`, `'0700'`. |
| `recursive` | `false` | When `true`, apply owner/group/mode to the directory *and* its contents using `-R`. |

## Examples

Simple creation:

```bash
directory '/var/www/app' present owner 'deploy' group 'www-data' mode '0755'
```

Directory tree with recursive ownership:

```bash
directory '/opt/myapp' present \
  owner 'myapp' group 'myapp' mode '0755' \
  recursive true
```

Remove a directory and everything under it:

```bash
directory '/tmp/old-cache' absent
```

## Destroy mode

`present` flips to `absent`: `rm -rf` removes the directory and any children. Use carefully.

## Notes

- `mkdir -p` is used, so missing parent directories are created too.
- `absent` uses `rm -rf` - children are removed with the directory.
- Mode comparison is 4-digit-octal aware (`0700` compares correctly against `stat -c %a = 700`).
