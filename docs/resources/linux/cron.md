# `cron`

Create, update, or remove a cron entry for a given user. Entries are tagged with an SSM Converge marker comment so unrelated crontab lines aren't touched.

## Syntax

```bash
cron '<name>' <state> [key value ...]
```

The `name` is the logical identifier; it appears in the marker comment but not in the actual cron schedule.

## Actions

| State | Effect |
|-------|--------|
| `present` | Ensure a crontab entry tagged with this name exists with the given schedule and command. |
| `absent` | Remove any entry tagged with this name. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `schedule` | - | Standard cron schedule: `min hour dom month dow`. Required for `present`. |
| `command` | - | The command to run. Required for `present`. |
| `user` | `root` | Whose crontab to modify. |

## Examples

Nightly database backup:

```bash
cron 'backup-db' present \
  schedule '0 2 * * *' \
  command '/usr/local/bin/backup.sh' \
  user 'root'
```

Every-5-minutes health check as a non-root user:

```bash
cron 'app-health' present \
  schedule '*/5 * * * *' \
  command '/opt/app/bin/healthcheck' \
  user 'appuser'
```

Remove a cron job:

```bash
cron 'old-nightly-sync' absent user 'root'
```

## Destroy mode

`present` flips to `absent`.

## The marker comment

Each managed entry looks like:

```
0 2 * * * /usr/local/bin/backup.sh # SSM-CONVERGE: backup-db
```

The resource finds and edits/removes entries by grepping for the `# SSM-CONVERGE: <name>` marker. Hand-written crontab entries without the marker are left alone.

## Notes

- Changing `schedule` or `command` on an existing entry is handled: the resource replaces the line in place (idempotent on subsequent runs).
- If the user has no crontab yet, a new one is created.
- The resource uses `crontab -u <user>`, which requires root privileges.
