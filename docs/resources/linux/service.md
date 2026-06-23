# `service`

Manage a service's running state and its boot-time enablement. Abstracts over systemd, OpenRC, sysvinit, FreeBSD rc.d, Solaris SMF, and macOS launchd.

## Syntax

```bash
service '<name>' <state> [enabled|disabled] [key value ...]
```

The third positional argument (optional) sets boot-time state.

## Actions

| State | Effect |
|-------|--------|
| `running` | Start the service if it isn't active. |
| `stopped` | Stop the service if it is active. |
| `restarted` | Always restart the service (applies every run in enforce/destroy mode). |

## Enablement (third positional, optional)

| Value | Effect |
|-------|--------|
| `enabled` | Enable the service for boot. |
| `disabled` | Disable the service. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `notify` | - | Handler name to fire when this service changes. |

## Examples

Most common form:

```bash
service 'nginx' running enabled
service 'postfix' stopped disabled
```

Start but don't touch boot-time state:

```bash
service 'nginx' running
```

Always restart on every run (useful after a config file change via `notify`):

```bash
service 'nginx' restarted
```

Driven by a handler:

```bash
file '/etc/nginx/nginx.conf' present source 's3://cfg/nginx.conf' notify 'reload-nginx'
handler 'reload-nginx' systemctl reload nginx
```

## Init system detection

| Platform | Detected | Command family |
|----------|----------|----------------|
| Linux (modern) | `systemctl --version` succeeds | `systemctl start/stop/restart/enable/disable` |
| Alpine / Gentoo | `rc-service` present | `rc-service` + `rc-update` |
| FreeBSD | `/etc/rc.d` exists | `service` + edits to `/etc/rc.conf` |
| Solaris / illumos | `svcs` + `svcadm` present | SMF |
| macOS | `Darwin` uname | `launchctl` + plist discovery |
| Legacy Linux / fallback | `service` command | sysvinit + `chkconfig` or `update-rc.d` |

## Destroy mode

`running` flips to `stopped` and `enabled` flips to `disabled`. The service stays installed — only its runtime state is flipped. Use [`package`](package.md) with destroy mode to uninstall the binary itself.

## Errors

- `no init system` - none of the detected init systems is available.
- `apply failed` - after start/stop, the service is not in the desired state. This can happen when a misconfigured unit file prevents startup.

## Notes

- `restarted` *always* counts as a change; it's useful for configs that explicitly want to bounce a service every run.
- For `enabled` on FreeBSD, the resource edits `/etc/rc.conf` (`${name}_enable="YES"`).
- On macOS, plists are searched under `/Library/LaunchDaemons`, `/Library/LaunchAgents`, `~/Library/LaunchAgents`, and the Homebrew plist locations.
