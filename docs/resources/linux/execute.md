# `execute`

Run an arbitrary shell command, idempotently. Idempotency comes from a guard (`creates`, `only_if`, or `not_if`) that the resource consults before executing - if the guard says "already done," the command is skipped and the run reports `compliant, changed=false`.

This is the escape hatch for installers, build steps, one-shot bootstraps, and other operations that don't fit a more specific resource. Keep configurations as declarative as possible; reach for `execute` when there's no purpose-built resource.

## Syntax

```bash
execute '<name>' [run] command '<shell-command>' [guard ...] [option ...]
```

The `name` is a logical identifier - it appears in the report and in log output but doesn't have to match anything on disk.

## Actions

| State | Effect |
|-------|--------|
| `run` *(default)* | Execute the command if no guard skips it. |

There is no `absent` for `execute`. To "undo" something installed via `execute`, declare a separate `execute` for the uninstall command, with its own guard.

## Guards (idempotency)

At least one is recommended. If multiple are supplied, all must agree the command needs to run.

| Property | Skip when |
|----------|-----------|
| `creates` | Path exists. Most natural for "install something that creates a binary or sentinel file." |
| `only_if`  | The shell test returns non-zero. Run only if the test succeeds. |
| `not_if`   | The shell test returns zero. Skip if the test succeeds. |

## Options

| Property | Default | Description |
|----------|---------|-------------|
| `command` | - | The shell command to run. **Required.** Can include shell features (pipes, redirects, env vars). |
| `user` | current | Run the command as this user (uses `sudo -u`). |
| `cwd` | - | `cd` here before running. |
| `env` | - | Repeatable. Set an env var as `KEY=VALUE` before running. |
| `timeout` | unlimited | Wall-clock seconds; uses `timeout(1)` if available. |
| `notify` | - | Handler name to fire when the command runs. |

## Examples

### Install a vendor `.deb` already on disk

```bash
file '/tmp/cw-agent.deb' present source 's3://my-bucket/agents/cw-agent.deb' mode '0644'

execute 'install-cw-agent' \
  command 'dpkg -i /tmp/cw-agent.deb' \
  creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'
```

The first run downloads and installs. The second run skips the `execute` because the binary already exists.

### Install an `.rpm` from an authenticated HTTPS source

```bash
file '/tmp/vendor-agent.rpm' present \
  source      'https://artifactory.corp/repos/agents/vendor-agent.rpm' \
  auth_bearer "$ARTIFACTORY_TOKEN" \
  checksum    'sha256:abc...'

execute 'install-vendor-agent' \
  command 'rpm -i /tmp/vendor-agent.rpm' \
  not_if  'rpm -q vendor-agent'
```

### One-shot first-boot initialisation

```bash
execute 'initialize-app' \
  command '/opt/app/bin/initialize.sh && touch /var/lib/app/.initialized' \
  not_if  'test -f /var/lib/app/.initialized'
```

### Run a script as a specific user with custom env

```bash
execute 'rebuild-cache' \
  command './bin/rebuild-cache' \
  cwd     '/opt/myapp' \
  user    'myapp' \
  env     'CACHE_DIR=/var/cache/myapp' \
  env     'WORKERS=4' \
  not_if  'test -f /var/cache/myapp/.fresh'
```

### Time-bounded operation

```bash
execute 'long-import' \
  command '/opt/app/bin/import.sh' \
  timeout 300 \
  creates '/var/lib/app/import-complete'
```

## Reporting

| Outcome | Status | `changed` |
|---------|--------|-----------|
| Guard says skip | `compliant` | `false` |
| Command ran, exit 0 | `compliant` | `true` |
| Command ran, non-zero exit | `error` | `true` |
| Audit mode, command would have run | `non_compliant` | `false` |
| Destroy mode | `compliant` | `false` (skipped) |

Failed-command stdout/stderr are captured to the debug log (first 2000 chars) so you can diagnose without re-running.

## Destroy mode

`execute` is **skipped** in destroy mode. Most installer commands have no one-line undo; if you need to uninstall something, declare a separate `execute` for the uninstall (or use `package <name> uninstalled` when the package manager is involved).

## Audit mode

In audit mode, `execute` reports `non_compliant: would run` when its guard says the command would execute. It never actually runs.

## Pitfalls

- **Always pair with a guard.** A guardless `execute` runs every pass, which defeats the point of idempotent configuration management. The configuration will still work, but `changed` will be `true` forever and the compliance signal becomes meaningless.
- **`only_if` and `not_if` shell expressions are `eval`'d.** Treat them as code, not data. Don't interpolate untrusted input.
- **Don't echo secrets in `command`.** They show up in the debug log on failure. Pull secrets into the script side via Secrets Manager / SSM Parameter Store.

## Notes

- Stdout and stderr are not streamed to the user - they're captured and only logged on failure. If you need real-time output for debugging, run the command outside `execute`.
- The command runs through `bash -c`, so shell features (pipes, `&&`, redirects, parameter expansion) are available.
- If `user` is set and is not the current user, the command runs through `sudo -u <user> -E bash -c ...` (existing env preserved with `-E`).
- See also [`file`](file.md) for downloading the artifact you want to install, [`package`](package.md) for distro-managed packages, and [`service`](service.md) for managing services after install.
