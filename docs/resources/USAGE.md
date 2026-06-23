# SSM Converge - Unified Resource Reference

*Generated from the per-resource pages in `docs/resources/linux/` and `docs/resources/windows/`. Run `bash docs/resources/build-usage.sh` to regenerate.*

This document stitches together the complete reference for every built-in resource shipped with SSM Converge. For editing or deep-linking, prefer the per-resource pages in the same directory - they're the source of truth.

## How resources work

Resources are the vocabulary of the DSL. Each resource declares *what* you want the system to look like; SSM Converge figures out *how* to get there, idempotently, and records the result.

Every resource shares the same contract:

- **Check** the current state on the host.
- **Apply** the change only when the state differs (skipped in `audit` mode).
- **Record** the outcome (`compliant` / `non_compliant` / `error`) for the compliance report.
- **Notify** handlers if the resource changed and specified a handler.

Resources are platform-specific. Linux configurations source `lib.sh` and get bash functions with lowercase-underscore names (`package`, `file`, `line_in_file`). Windows configurations dot-source `lib.ps1` and get PowerShell functions with PascalCase names (`Package`, `File`, `WindowsService`).

## Common conventions

### States

Linux resources take a bare desired state as the second positional argument:

```bash
package 'nginx' installed
file    '/etc/motd' present
service 'nginx' running enabled
```

Windows resources take an explicit `State` parameter:

```powershell
Package        'nginx' Installed
File           'C:\motd' Present
WindowsService 'nginx' Running -StartupType Automatic
```

Both accept a state-neutral `present`/`absent` pair as an alias for resource-specific names (`installed`/`uninstalled`, `running`/`stopped`).

### Destroy mode

When the library is invoked with `DSC_MODE=destroy`, most resources flip their desired state:

| Declared | Destroy-mode effective |
|----------|------------------------|
| `present` / `installed` / `mounted` | `absent` |
| `absent` / `uninstalled` / `removed` | `present` |
| `running` | `stopped` |
| `enabled` | `disabled` |

Resources with no safe inverse (`sysctl`, `timezone`, `locale`) are skipped in destroy mode.

### Handler notification

Resources that change state can `notify` a handler. The handler runs once at the end of the configuration, no matter how many resources triggered it.

### Return codes and compliance status

| Status | When |
|--------|------|
| `compliant` | Current state matches desired state (may or may not have been fixed this run) |
| `non_compliant` | Drift detected in `audit` mode, or apply could not converge |
| `error` | Check or apply failed (missing binary, permission denied, invalid argument) |

The run exits:

- `0` - success
- `1` - one or more resources reported `error`
- `2` - `audit` mode detected drift

### Table of contents

**Linux resources:** [package](#package) - [file](#file) - [file_content](#file_content) - [execute](#execute) - [directory](#directory) - [service](#service) - [user](#user) - [group](#group) - [sysctl](#sysctl) - [cron](#cron) - [line_in_file](#line_in_file) - [mount_fs](#mount_fs) - [timezone](#timezone) - [locale](#locale) - [host_entry](#host_entry)

**Windows resources:** [File](#File-windows) - [Directory](#Directory-windows) - [Package](#Package-windows) - [Execute](#Execute) - [WindowsService](#WindowsService) - [RegistryKey](#RegistryKey) - [WindowsFeature](#WindowsFeature) - [PowerShellModule](#PowerShellModule) - [Certificate](#Certificate) - [LocalUser](#LocalUser) - [LocalGroup](#LocalGroup) - [HostEntry](#HostEntry) - [EnvironmentVariable](#EnvironmentVariable) - [ScheduledTask](#ScheduledTask) - [DscResource](#DscResource)

---

# Linux Resources

## `package` { #package }

Install, upgrade, or remove software using whichever package manager the host provides.

### Syntax

```bash
package '<name>' <state> [key value ...]
```

### Actions (desired state)

| State | Aliases | Effect |
|-------|---------|--------|
| `installed` | `present` | Ensure the package is installed. Optionally matches a version prefix. |
| `uninstalled` | `removed`, `absent` | Ensure the package is not installed. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `version` | *(any)* | Match this version prefix. On install, picks the matching version; on check, drift is reported if installed version doesn't start with this string. |

### Supported package managers

Detected automatically, first match wins:

| Platform | Manager | Underlying command |
|----------|---------|--------------------|
| Debian / Ubuntu | `apt` | `apt-get install -y -qq` |
| Fedora / RHEL 8+ / Amazon Linux 2023 | `dnf` | `dnf install -y -q` |
| RHEL 7 / CentOS 7 / Amazon Linux 2 | `yum` | `yum install -y -q` |
| openSUSE / SLES | `zypper` | `zypper install -y --quiet` |
| Alpine | `apk` | `apk add --quiet` |
| macOS | `brew` | `brew install` |
| FreeBSD | `pkg` | `pkg install -y` |
| NetBSD / SmartOS | `pkgin` | `pkgin -y install` |
| OpenBSD | `pkg_add` | `pkg_add` |

### Examples

Minimum:

```bash
package 'nginx' installed
package 'telnet' uninstalled
```

Version-pinned install:

```bash
package 'nginx' installed version '1.24'
```

Audit a whole fleet for forbidden software:

```bash
package 'telnet' uninstalled
package 'ftp'    uninstalled
package 'rsh'    uninstalled
package 'talk'   uninstalled
```

### Destroy mode

`installed` flips to `uninstalled` and vice versa. Useful for `ssm-converge destroy mybaseline.sh` to remove everything the configuration added.

### Errors

- `no package manager` - none of the detected managers is available on this host.
- `install failed` / `remove failed` - the underlying manager returned non-zero or the package is still in the wrong state after the command.

### Notes

- The resource calls `apt-get update` before installs on Debian/Ubuntu.
- Version match uses a prefix comparison (`1.24` matches `1.24.0`, `1.24.1-ubuntu3`).
- Removing a package on Debian uses `apt-get remove`, not `purge`. Config files are retained.

---

## `file` { #file }

Manage a single file: its content, ownership, and permissions. Content can come from an inline string, an S3 object, an HTTPS URL (with optional authentication and checksum verification), or a local file.

### Syntax

```bash
file '<path>' <state> [key value ...]
```

### Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the file exists with the specified content and attributes. |
| `absent` | Remove the file if it exists. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `source` | - | Where the content comes from. Accepts: `s3://bucket/key`, `https://...`, `http://...`, `file:///abs/path`, or a bare absolute path. |
| `content` | - | Inline string that becomes the file's content. SHA-256 used for drift detection. |
| `checksum` | - | Expected SHA-256 of the downloaded content, e.g. `'sha256:abc123...'`. Used both for drift detection and to verify the download after fetching. **Recommended for any HTTPS source.** |
| `auth_bearer` | - | Bearer token for HTTPS sources. Sent as `Authorization: Bearer <token>`. Token is passed via curl config file (not the command line) to keep it out of `ps`. |
| `auth_basic` | - | HTTP basic auth, format `'user:pass'`. Sent through curl's `user` config (or wget's `--user`/`--password`). |
| `header` | - | Additional HTTP header, format `'Name: value'`. Repeatable - specify once per header. |
| `owner` | - | User name (not UID) that should own the file. |
| `group` | - | Group name (not GID) that should own the file. |
| `mode` | - | Octal mode, e.g. `'0644'`, `'0600'`. Zero-padding-insensitive. |
| `notify` | - | Handler name to fire when this file changes. |

Use either `source` or `content`, not both. Neither is required if the file just needs to exist with specific attributes.

### Examples

#### File from S3

```bash
file '/etc/nginx/nginx.conf' present \
  source 's3://DOC-EXAMPLE-BUCKET/nginx.conf' \
  owner 'root' group 'root' mode '0644' \
  notify 'reload-nginx'
```

#### File from a public HTTPS URL with checksum verification

```bash
file '/tmp/amazon-cloudwatch-agent.deb' present \
  source   'https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb' \
  checksum 'sha256:9f4c1d3a...e8b2'   \
  mode '0644'
```

The next run hashes the local file and compares to the expected checksum. If they match, no download happens. Drift is detected if the file is replaced or corrupted.

#### Authenticated download from a private artifact repo

```bash
# GitHub release asset (requires Accept header for the binary, plus a token).
file '/tmp/release.tgz' present \
  source      'https://api.github.com/repos/my-org/my-app/releases/assets/123456' \
  auth_bearer "$GITHUB_TOKEN" \
  header      'Accept: application/octet-stream' \
  checksum    "sha256:$RELEASE_SHA256"
```

```bash
# Nexus or JFrog with HTTP basic auth.
file '/tmp/lib.jar' present \
  source     'https://nexus.corp/private/lib.jar' \
  auth_basic 'svc-deploy:S3cret' \
  checksum   'sha256:abcdef...'
```

```bash
# Vendor API with an X-Api-Key header.
file '/tmp/blob' present \
  source 'https://api.vendor.com/download/v2/blob' \
  header 'X-Api-Key: abc123' \
  header 'X-Tenant: prod'
```

#### Inline content

```bash
file '/etc/motd' present content 'Welcome to production'
```

#### Enforce permissions on an existing file (no content change)

```bash
file '/etc/shadow' present owner 'root' group 'root' mode '0600'
```

#### Remove a file

```bash
file '/tmp/debug.log' absent
```

### Idempotency model

| Source kind | Drift detection without `checksum` | Drift detection with `checksum` |
|-------------|------------------------------------|---------------------------------|
| Inline `content` | SHA-256 of `content` vs file | (n/a; `content` already implies its own hash) |
| `s3://...` | Hashes a fresh download against the local file | Compare local SHA-256 to expected hash |
| `https://`, `http://` | Presence-only (cheap; no re-download) | Compare local SHA-256 to expected hash |
| `file://`, bare path | Presence-only | Compare local SHA-256 to expected hash |

Pinning a `checksum` is recommended for any non-S3 source: it both detects drift and verifies the download integrity.

### Destroy mode

`present` flips to `absent`: the configuration's files are deleted.

### Errors

- `download failed` - the configured fetcher (curl, wget, aws s3 cp, or local cp) returned non-zero. Check the URL, network reachability, IAM role, or credentials.
- `checksum mismatch` - the file was downloaded but its SHA-256 did not match the expected value. The downloaded file is removed so the next run starts clean.

### Security notes

- Authentication tokens go through curl's config file (`-K`), not the command line, so they don't appear in `ps`. The config file is created with mode 0600, written to `/dev/shm` when available (RAM-backed), and removed immediately after the fetch.
- Prefer `auth_bearer` with a short-lived token from Secrets Manager / SSM Parameter Store over `auth_basic`. Keep the configuration loading the token into a shell var just before calling `file`.
- For S3 sources, prefer instance role credentials over baking access keys into the configuration.

### Notes

- Parent directory is created automatically when writing content.
- The HTTP fetcher prefers `curl` and falls back to `wget` if curl is missing.
- TLS protocol negotiation follows the system's curl/wget defaults; both honour the OS trust store.
- For heredoc-style multi-line content, use [`file_content`](#file_content) instead.
- See [`execute`](#execute) for the typical "download then run installer" pattern.

---

## `file_content` { #file_content }

Heredoc-friendly sibling of [`file`](#file). Reads the file's content from stdin, so multi-line strings don't have to be escaped into a single argument.

### Syntax

```bash
file_content '<path>' [key value ...] <<'EOF'
...file contents...
EOF
```

### Properties

Same as [`file`](#file): `owner`, `group`, `mode`, `notify`. The `content` comes from the heredoc itself — you don't (and can't) pass it as a keyword argument.

`file_content` always applies `present` — there's no `absent` form; use `file '<path>' absent` for that.

### Examples

Multi-line systemd unit:

```bash
file_content '/etc/systemd/system/myapp.service' owner 'root' mode '0644' <<'EOF'
[Unit]
Description=My app
After=network.target

[Service]
ExecStart=/usr/local/bin/myapp
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

Sysctl config snippet:

```bash
file_content '/etc/sysctl.d/99-custom.conf' owner 'root' mode '0644' <<'EOF'
net.ipv4.ip_forward = 1
vm.swappiness = 10
EOF
```

Variable interpolation with unquoted heredoc:

```bash
APP=myapp
file_content "/etc/cron.d/${APP}-cleanup" owner 'root' mode '0644' <<EOF
# Managed by SSM Converge
0 2 * * * root /usr/local/bin/${APP}-cleanup
EOF
```

### Notes

- Uses `'EOF'` (single-quoted) to disable variable expansion, or unquoted `EOF` to enable it - standard bash heredoc semantics.
- Internally just delegates to [`file`](#file) `present content ...` so all the drift detection, handlers, and destroy-mode behaviour are identical.

---

## `execute` { #execute }

Run an arbitrary shell command, idempotently. Idempotency comes from a guard (`creates`, `only_if`, or `not_if`) that the resource consults before executing - if the guard says "already done," the command is skipped and the run reports `compliant, changed=false`.

This is the escape hatch for installers, build steps, one-shot bootstraps, and other operations that don't fit a more specific resource. Keep configurations as declarative as possible; reach for `execute` when there's no purpose-built resource.

### Syntax

```bash
execute '<name>' [run] command '<shell-command>' [guard ...] [option ...]
```

The `name` is a logical identifier - it appears in the report and in log output but doesn't have to match anything on disk.

### Actions

| State | Effect |
|-------|--------|
| `run` *(default)* | Execute the command if no guard skips it. |

There is no `absent` for `execute`. To "undo" something installed via `execute`, declare a separate `execute` for the uninstall command, with its own guard.

### Guards (idempotency)

At least one is recommended. If multiple are supplied, all must agree the command needs to run.

| Property | Skip when |
|----------|-----------|
| `creates` | Path exists. Most natural for "install something that creates a binary or sentinel file." |
| `only_if`  | The shell test returns non-zero. Run only if the test succeeds. |
| `not_if`   | The shell test returns zero. Skip if the test succeeds. |

### Options

| Property | Default | Description |
|----------|---------|-------------|
| `command` | - | The shell command to run. **Required.** Can include shell features (pipes, redirects, env vars). |
| `user` | current | Run the command as this user (uses `sudo -u`). |
| `cwd` | - | `cd` here before running. |
| `env` | - | Repeatable. Set an env var as `KEY=VALUE` before running. |
| `timeout` | unlimited | Wall-clock seconds; uses `timeout(1)` if available. |
| `notify` | - | Handler name to fire when the command runs. |

### Examples

#### Install a vendor `.deb` already on disk

```bash
file '/tmp/cw-agent.deb' present source 's3://my-bucket/agents/cw-agent.deb' mode '0644'

execute 'install-cw-agent' \
  command 'dpkg -i /tmp/cw-agent.deb' \
  creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'
```

The first run downloads and installs. The second run skips the `execute` because the binary already exists.

#### Install an `.rpm` from an authenticated HTTPS source

```bash
file '/tmp/vendor-agent.rpm' present \
  source      'https://artifactory.corp/repos/agents/vendor-agent.rpm' \
  auth_bearer "$ARTIFACTORY_TOKEN" \
  checksum    'sha256:abc...'

execute 'install-vendor-agent' \
  command 'rpm -i /tmp/vendor-agent.rpm' \
  not_if  'rpm -q vendor-agent'
```

#### One-shot first-boot initialisation

```bash
execute 'initialize-app' \
  command '/opt/app/bin/initialize.sh && touch /var/lib/app/.initialized' \
  not_if  'test -f /var/lib/app/.initialized'
```

#### Run a script as a specific user with custom env

```bash
execute 'rebuild-cache' \
  command './bin/rebuild-cache' \
  cwd     '/opt/myapp' \
  user    'myapp' \
  env     'CACHE_DIR=/var/cache/myapp' \
  env     'WORKERS=4' \
  not_if  'test -f /var/cache/myapp/.fresh'
```

#### Time-bounded operation

```bash
execute 'long-import' \
  command '/opt/app/bin/import.sh' \
  timeout 300 \
  creates '/var/lib/app/import-complete'
```

### Reporting

| Outcome | Status | `changed` |
|---------|--------|-----------|
| Guard says skip | `compliant` | `false` |
| Command ran, exit 0 | `compliant` | `true` |
| Command ran, non-zero exit | `error` | `true` |
| Audit mode, command would have run | `non_compliant` | `false` |
| Destroy mode | `compliant` | `false` (skipped) |

Failed-command stdout/stderr are captured to the debug log (first 2000 chars) so you can diagnose without re-running.

### Destroy mode

`execute` is **skipped** in destroy mode. Most installer commands have no one-line undo; if you need to uninstall something, declare a separate `execute` for the uninstall (or use `package <name> uninstalled` when the package manager is involved).

### Audit mode

In audit mode, `execute` reports `non_compliant: would run` when its guard says the command would execute. It never actually runs.

### Pitfalls

- **Always pair with a guard.** A guardless `execute` runs every pass, which defeats the point of idempotent configuration management. The configuration will still work, but `changed` will be `true` forever and the compliance signal becomes meaningless.
- **`only_if` and `not_if` shell expressions are `eval`'d.** Treat them as code, not data. Don't interpolate untrusted input.
- **Don't echo secrets in `command`.** They show up in the debug log on failure. Pull secrets into the script side via Secrets Manager / SSM Parameter Store.

### Notes

- Stdout and stderr are not streamed to the user - they're captured and only logged on failure. If you need real-time output for debugging, run the command outside `execute`.
- The command runs through `bash -c`, so shell features (pipes, `&&`, redirects, parameter expansion) are available.
- If `user` is set and is not the current user, the command runs through `sudo -u <user> -E bash -c ...` (existing env preserved with `-E`).
- See also [`file`](#file) for downloading the artifact you want to install, [`package`](#package) for distro-managed packages, and [`service`](#service) for managing services after install.

---

## `directory` { #directory }

Create, remove, or enforce ownership/mode on a directory.

### Syntax

```bash
directory '<path>' <state> [key value ...]
```

### Actions

| State | Effect |
|-------|--------|
| `present` | Create the directory (with parents) if missing; enforce attributes. |
| `absent` | Recursively remove the directory if it exists. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `owner` | - | User name that should own the directory. |
| `group` | - | Group name. |
| `mode` | - | Octal mode, e.g. `'0755'`, `'0700'`. |
| `recursive` | `false` | When `true`, apply owner/group/mode to the directory *and* its contents using `-R`. |

### Examples

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

### Destroy mode

`present` flips to `absent`: `rm -rf` removes the directory and any children. Use carefully.

### Notes

- `mkdir -p` is used, so missing parent directories are created too.
- `absent` uses `rm -rf` - children are removed with the directory.
- Mode comparison is 4-digit-octal aware (`0700` compares correctly against `stat -c %a = 700`).

---

## `service` { #service }

Manage a service's running state and its boot-time enablement. Abstracts over systemd, OpenRC, sysvinit, FreeBSD rc.d, Solaris SMF, and macOS launchd.

### Syntax

```bash
service '<name>' <state> [enabled|disabled] [key value ...]
```

The third positional argument (optional) sets boot-time state.

### Actions

| State | Effect |
|-------|--------|
| `running` | Start the service if it isn't active. |
| `stopped` | Stop the service if it is active. |
| `restarted` | Always restart the service (applies every run in enforce/destroy mode). |

### Enablement (third positional, optional)

| Value | Effect |
|-------|--------|
| `enabled` | Enable the service for boot. |
| `disabled` | Disable the service. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `notify` | - | Handler name to fire when this service changes. |

### Examples

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

### Init system detection

| Platform | Detected | Command family |
|----------|----------|----------------|
| Linux (modern) | `systemctl --version` succeeds | `systemctl start/stop/restart/enable/disable` |
| Alpine / Gentoo | `rc-service` present | `rc-service` + `rc-update` |
| FreeBSD | `/etc/rc.d` exists | `service` + edits to `/etc/rc.conf` |
| Solaris / illumos | `svcs` + `svcadm` present | SMF |
| macOS | `Darwin` uname | `launchctl` + plist discovery |
| Legacy Linux / fallback | `service` command | sysvinit + `chkconfig` or `update-rc.d` |

### Destroy mode

`running` flips to `stopped` and `enabled` flips to `disabled`. The service stays installed — only its runtime state is flipped. Use [`package`](#package) with destroy mode to uninstall the binary itself.

### Errors

- `no init system` - none of the detected init systems is available.
- `apply failed` - after start/stop, the service is not in the desired state. This can happen when a misconfigured unit file prevents startup.

### Notes

- `restarted` *always* counts as a change; it's useful for configs that explicitly want to bounce a service every run.
- For `enabled` on FreeBSD, the resource edits `/etc/rc.conf` (`${name}_enable="YES"`).
- On macOS, plists are searched under `/Library/LaunchDaemons`, `/Library/LaunchAgents`, `~/Library/LaunchAgents`, and the Homebrew plist locations.

---

## `user` { #user }

Create or remove a local user account; enforce the login shell, home directory, and supplementary groups.

### Syntax

```bash
user '<name>' <state> [key value ...]
```

### Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the user exists; optionally enforce attributes on an existing user. |
| `absent` | Remove the user (`userdel -r`, which also removes the home directory). |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `shell` | distro default | Login shell (`/bin/bash`, `/usr/sbin/nologin`, ...). |
| `groups` | *(none)* | Comma-separated list of supplementary groups (passed as `-G`). |
| `home` | `/home/<name>` | Home directory. |
| `system` | `false` | When `true`, create as a system user (`useradd -r`). |
| `uid` | *(auto)* | Force a specific UID. Only honoured on create, not on modify. |

### Examples

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

### Destroy mode

`present` flips to `absent`. Both the user and the home directory are removed.

### Errors

- `creation failed` - `useradd` returned non-zero.

### Notes

- Attribute enforcement on an existing user currently checks **shell only**. Changes to `groups` and `home` on an already-existing account are applied but not independently drift-checked.
- `user` calls `useradd`, so on distros with `adduser` (e.g. Debian) the behaviour differs slightly: `useradd` doesn't create a default group named after the user. Declare a matching [`group`](#group) if you want that.
- `absent` uses `-r` so the home directory and mail spool are removed too.

---

## `group` { #group }

Create or remove a local group. On create, you can seed the group's initial membership.

### Syntax

```bash
group '<name>' <state> [key value ...]
```

### Actions

| State | Effect |
|-------|--------|
| `present` | Create the group if missing. |
| `absent` | Remove the group (`groupdel`). |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `gid` | *(auto)* | Force a specific GID on creation. Only honoured on create. |
| `members` | *(none)* | Comma-separated list of users to add to the group at creation time. |

### Examples

```bash
group 'www-data' present

group 'developers' present members 'alice,bob,charlie'

group 'oldgroup' absent
```

### Destroy mode

`present` flips to `absent`.

### Notes

- `members` is only applied on **create**. To modify membership on an existing group, use [`user`](#user) with the `groups` property on the individual users, or manage the group with a [`line_in_file`](#line_in_file) on `/etc/group` for surgical edits.
- `absent` fails if the group is the primary group of any user. Remove those users first.

---

## `sysctl` { #sysctl }

Set (and optionally persist) a Linux kernel parameter.

### Syntax

```bash
sysctl '<key>' value '<value>' [persist true|false]
```

No "desired state" - sysctl is always a declarative "set to this value."

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `value` | *(required)* | The value to set. Space-separated values (like `1024 65535`) are fine. |
| `persist` | `true` | When `true`, also write the key=value pair into `/etc/sysctl.d/99-ssm-converge.conf` so it survives reboot. |

### Examples

```bash
sysctl 'vm.swappiness' value '10'
sysctl 'net.ipv4.ip_forward' value '1'
sysctl 'net.ipv4.ip_local_port_range' value '1024 65535'
sysctl 'net.ipv6.conf.all.disable_ipv6' value '1' persist false   # runtime only
```

Security hardening set:

```bash
sysctl 'kernel.randomize_va_space'              value '2'
sysctl 'net.ipv4.tcp_syncookies'                value '1'
sysctl 'net.ipv4.conf.all.send_redirects'       value '0'
sysctl 'net.ipv4.conf.all.accept_source_route'  value '0'
sysctl 'net.ipv4.conf.all.log_martians'         value '1'
```

### Destroy mode

**Skipped.** Kernel parameters have no safe inverse (what's the opposite of `vm.swappiness=10`?). The resource records `compliant` with detail `"skipped in destroy mode"`.

### Errors

- `sysctl -w failed` - invalid key, or the kernel refused the value (e.g. a read-only parameter, or a key that requires a specific module to be loaded).

### Notes

- The resource uses the absolute path to the `sysctl` binary (typically `/usr/sbin/sysctl`) internally to avoid recursing into the DSL function of the same name.
- Whitespace normalisation: runs of whitespace in both the current and desired values are collapsed to single spaces before comparison. This handles space-separated values like `ip_local_port_range` correctly (kernel returns them tab-separated).
- When `persist true`, the same key is rewritten in `/etc/sysctl.d/99-ssm-converge.conf` on each change. A `sysctl --system` is **not** automatically issued; the runtime value is set separately via `sysctl -w`.

---

## `cron` { #cron }

Create, update, or remove a cron entry for a given user. Entries are tagged with an SSM Converge marker comment so unrelated crontab lines aren't touched.

### Syntax

```bash
cron '<name>' <state> [key value ...]
```

The `name` is the logical identifier; it appears in the marker comment but not in the actual cron schedule.

### Actions

| State | Effect |
|-------|--------|
| `present` | Ensure a crontab entry tagged with this name exists with the given schedule and command. |
| `absent` | Remove any entry tagged with this name. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `schedule` | - | Standard cron schedule: `min hour dom month dow`. Required for `present`. |
| `command` | - | The command to run. Required for `present`. |
| `user` | `root` | Whose crontab to modify. |

### Examples

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

### Destroy mode

`present` flips to `absent`.

### The marker comment

Each managed entry looks like:

```
0 2 * * * /usr/local/bin/backup.sh # SSM-CONVERGE: backup-db
```

The resource finds and edits/removes entries by grepping for the `# SSM-CONVERGE: <name>` marker. Hand-written crontab entries without the marker are left alone.

### Notes

- Changing `schedule` or `command` on an existing entry is handled: the resource replaces the line in place (idempotent on subsequent runs).
- If the user has no crontab yet, a new one is created.
- The resource uses `crontab -u <user>`, which requires root privileges.

---

## `line_in_file` { #line_in_file }

Ensure a specific line exists, or is absent, in a text file. Similar to Ansible's `lineinfile` module.

### Syntax

```bash
line_in_file '<path>' <state> [key value ...]
```

### Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the exact line is in the file; if a `match` regex is given, replace or insert such that no stale line matches the regex. |
| `absent` | Remove matching line(s). |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `line` | - | The exact line to ensure. Required for `present`; optional for `absent` (use `match` instead). |
| `match` | - | Regex identifying the "slot" being managed. When set, the resource also deletes any other lines that match the regex but differ from `line`. |
| `notify` | - | Handler name to fire when the file changes. |

### Compliance rule (important)

When `match` is provided, the resource is compliant only when **exactly one** line in the file:

- matches the `match` regex, **AND**
- equals the `line` string.

Any other matching-but-different line is considered stale and will be removed on enforce. This is stronger than the Ansible default and makes `line_in_file` truly idempotent when the file has e.g. a commented-out placeholder and a value set.

### Examples

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

### Destroy mode

`present` flips to `absent` — the line is removed.

### Notes

- If the file doesn't exist on `present`, it is created with the single desired line.
- In-place edits use GNU sed on Linux and BSD sed on macOS automatically (the resource detects `sed --version | grep GNU`).
- When both `match` and `line` are given and multiple matching lines exist, the first match is replaced in place and subsequent matches are deleted — preserving the original line's position in the file.
- For managing multiple lines in the same file, use multiple `line_in_file` calls with different `match` patterns.

---

## `mount_fs` { #mount_fs }

Mount a filesystem at a given mount point, and optionally persist the entry to `/etc/fstab`.

The function is named `mount_fs` (not `mount`) to avoid shadowing the system `mount` binary.

### Syntax

```bash
mount_fs '<mount_point>' <state> [key value ...]
```

### Actions

| State | Aliases | Effect |
|-------|---------|--------|
| `present` | `mounted` | Ensure the filesystem is mounted here, with optional fstab entry. |
| `absent` | `unmounted` | Unmount and remove the fstab entry. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `device` | - | Block device or NFS source (`/dev/xvdf`, `10.0.1.5:/data`). Required for `present`. |
| `fstype` | `auto` | Filesystem type (`ext4`, `xfs`, `nfs`, `nfs4`, ...). |
| `options` | `defaults` | Mount options, comma-separated. |
| `dump` | `0` | fstab dump field. |
| `pass` | `0` | fstab pass field (fsck order). |
| `persist` | `true` | Whether to add an entry to `/etc/fstab`. When `false`, only mounts for the current boot. |

### Examples

EBS volume formatted ext4:

```bash
mount_fs '/mnt/data' present \
  device '/dev/xvdf' \
  fstype 'ext4' \
  options 'defaults,noatime'
```

NFS share:

```bash
mount_fs '/mnt/shared' present \
  device '10.0.1.50:/exports/shared' \
  fstype 'nfs4' \
  options 'rw,hard,intr,rsize=32768,wsize=32768'
```

Runtime-only mount (gone after reboot):

```bash
mount_fs '/mnt/scratch' present \
  device '/dev/xvdg' \
  fstype 'xfs' \
  persist false
```

Unmount and remove from fstab:

```bash
mount_fs '/mnt/old' absent
```

### Destroy mode

`present` / `mounted` flips to `absent` / `unmounted`. The filesystem is unmounted and the fstab line is removed. Data on the device is untouched.

### Notes

- The mount point directory is created if missing.
- Compliance check compares both live mount state (`mount | grep " on <point> "`) and fstab presence. Drift is reported if either is wrong.
- Removing an entry that's currently in use returns the usual `umount: target is busy` — record that as `error` on the operator.

---

## `timezone` { #timezone }

Set the system timezone.

### Syntax

```bash
timezone '<tz>'
```

Just one positional argument — the timezone name. No desired-state keyword (always "set this timezone").

### Examples

```bash
timezone 'UTC'
timezone 'America/New_York'
timezone 'Asia/Tokyo'
```

### How it's applied

Detected in this order:

| Detected | Uses |
|----------|------|
| `timedatectl` available (modern systemd Linux) | `timedatectl set-timezone` |
| `Darwin` | `systemsetup -settimezone` |
| FreeBSD | copies `/usr/share/zoneinfo/<tz>` to `/etc/localtime` |
| Fallback Linux | symlinks `/etc/localtime` and writes `/etc/timezone` |

### Destroy mode

**Skipped.** There's no safe inverse for "set timezone." The resource records `compliant` with detail `"skipped in destroy mode"`.

### Notes

- No state argument — the resource is declarative "set to this value."
- Drift is detected by reading the current value via `timedatectl` or `/etc/timezone` or `readlink /etc/localtime`, depending on platform.
- On Amazon Linux 2023 and other minimal images, `timedatectl show` may return an empty Timezone field until a first set. Subsequent runs then pick up the value correctly.

---

## `locale` { #locale }

Set the system LANG locale.

### Syntax

```bash
locale '<locale>'
```

### Examples

```bash
locale 'en_US.UTF-8'
locale 'ja_JP.UTF-8'
locale 'C.UTF-8'
```

### How it's applied

Detected in this order:

| Detected | Uses |
|----------|------|
| `localectl` available (systemd) | `localectl set-locale LANG=<value>` |
| `/etc/default/locale` exists (Debian/Ubuntu) | Writes `LANG=<value>`; runs `locale-gen` if available |
| `/etc/locale.conf` exists (RHEL/CentOS) | Writes `LANG=<value>` |

The current shell's `$LANG` is also exported so subsequent commands in the same run use the new value.

### Destroy mode

**Skipped.** Same rationale as [`timezone`](#timezone).

### Notes

- The locale must already be generated on the system. On Debian/Ubuntu the resource attempts `locale-gen <value>`; on other distros you may need to install a locale package (`glibc-langpack-en` on RHEL 8+, for example).
- Drift comparison reads the current `LANG` from `/etc/default/locale` or `/etc/locale.conf`, whichever exists. On minimal images where neither exists, the resource falls back to the current shell's `$LANG`.

---

## `host_entry` { #host_entry }

Manage a single entry in `/etc/hosts` (or any other hosts-format file).

### Syntax

```bash
host_entry '<ip>' <state> [key value ...]
```

The identity of the entry is the IP address. Only one hostname line per IP is managed.

### Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the line `<ip> <hostname>` is in the file. If an entry for `<ip>` already exists with a different hostname, it's updated. |
| `absent` | Remove any line starting with `<ip>` followed by whitespace. |

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `hostname` | - | Hostname or space-separated list of aliases. Required for `present`. |
| `hosts_file` | `/etc/hosts` | Alternative hosts file. Useful for tests. |

### Examples

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

### Destroy mode

`present` flips to `absent`.

### Notes

- If the same IP appears more than once in `/etc/hosts`, the resource updates the **first** occurrence to match and leaves the rest alone. Consider using `line_in_file` for truly surgical edits.
- The Windows equivalent is `HostEntry` — same semantics, different capitalization, operates on `C:\Windows\System32\drivers\etc\hosts` by default.

---


# Windows Resources

## `File` / `File-Content` { #File-windows }

Manage a single file on Windows. Content can come from an inline string, an S3 object, an HTTPS URL (with optional authentication and checksum verification), or a local file.

### Syntax

```powershell
File '<Path>' <State> [-Source <uri>] [-Content <string>] [-Checksum <hash>] `
              [-AuthBearer <token>] [-AuthBasic <user:pass>] `
              [-Headers @{ ... }] [-Notify <handler>]

File-Content -Path '<Path>' -Content <here-string> [-Notify <handler>]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Ensure the file exists with the given content. |
| `Absent` | Remove the file if it exists. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | Path to the file. |
| `-Source` | - | Where the content comes from. Accepts: `s3://bucket/key`, `https://...`, `http://...`, `file:///C:/abs/path`, or a bare absolute path. |
| `-Content` | - | Inline string. SHA-256 used for drift detection. |
| `-Checksum` | - | Expected SHA-256 of the downloaded content, e.g. `'sha256:abc123...'`. **Recommended for any HTTPS source.** |
| `-AuthBearer` | - | Bearer token for HTTPS sources. Sent as `Authorization: Bearer <token>`. |
| `-AuthBasic` | - | HTTP basic auth, format `'user:pass'`. |
| `-Headers` | - | Hashtable of additional HTTP headers, e.g. `@{ 'X-Api-Key' = 'abc' }`. |
| `-Notify` | - | Handler name to fire when the file changes. |

### Examples

#### Fetch from S3

```powershell
File 'C:\inetpub\wwwroot\web.config' Present `
     -Source 's3://DOC-EXAMPLE-BUCKET/web.config' `
     -Notify 'restart-iis'
```

#### Fetch a public installer over HTTPS with checksum verification

```powershell
File 'C:\temp\agent.msi' Present `
     -Source   'https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi' `
     -Checksum 'sha256:abc123...'
```

The next run hashes the local file and compares to the expected checksum. If they match, no download happens.

#### Authenticated download from a private artifact repo

```powershell
# GitHub release asset.
File 'C:\temp\release.zip' Present `
     -Source     'https://api.github.com/repos/my-org/my-app/releases/assets/123456' `
     -AuthBearer $env:GITHUB_TOKEN `
     -Headers    @{ 'Accept' = 'application/octet-stream' } `
     -Checksum   "sha256:$env:RELEASE_SHA256"

# Nexus / JFrog with HTTP basic auth.
File 'C:\temp\lib.dll' Present `
     -Source    'https://nexus.corp/private/lib.dll' `
     -AuthBasic 'svc-deploy:S3cret' `
     -Checksum  'sha256:abcdef...'

# Vendor API with custom headers.
File 'C:\temp\blob' Present `
     -Source  'https://api.vendor.com/download/v2/blob' `
     -Headers @{ 'X-Api-Key' = 'abc123'; 'X-Tenant' = 'prod' }
```

#### Inline content

```powershell
File 'C:\app\app.conf' Present -Content 'key=value'
```

#### Multi-line content via `File-Content`

```powershell
File-Content -Path 'C:\app\settings.json' -Content @'
{
  "port": 8080,
  "workers": 4
}
'@
```

#### Remove a file

```powershell
File 'C:\temp\old.log' Absent
```

### Idempotency model

| Source kind | Drift detection without `-Checksum` | Drift detection with `-Checksum` |
|-------------|-------------------------------------|----------------------------------|
| `-Content`  | SHA-256 of `-Content` vs file       | (n/a) |
| `s3://...`  | Hashes a fresh download against the local file | Compare local SHA-256 to expected hash |
| `https://`, `http://` | Presence-only (no re-download) | Compare local SHA-256 to expected hash |
| `file://`, bare path | Presence-only             | Compare local SHA-256 to expected hash |

Pinning a checksum is recommended for any non-S3 source: it both detects drift and verifies the download integrity.

### Destroy mode

`Present` flips to `Absent`.

### Errors

- `download failed` - the configured fetcher (`Invoke-WebRequest`, `aws s3 cp`, or `Copy-Item`) returned non-zero.
- `checksum mismatch` - the file was downloaded but its SHA-256 did not match the expected value. The downloaded file is removed so the next run starts clean.

### Security notes

- TLS 1.2 is forced for HTTPS downloads (PowerShell 5.1's default sometimes negotiates older protocols).
- `-AuthBearer` and `-Headers` are passed through `Invoke-WebRequest`'s parameters, not via shell command lines.
- Prefer secrets pulled from Secrets Manager / SSM Parameter Store at runtime over plaintext values in the configuration.

### Notes

- The S3 path shells out to `aws.exe` on PATH (not `Read-S3Object`) for parity with the Linux path.
- Inline content is written as UTF-8 without BOM. If you need BOM or a specific encoding, use a separate Task / Handler.
- `File-Content` is a thin wrapper that calls `File Present -Content $Content`.
- See also [`Execute`](#Execute) for the typical "download then run installer" pattern.
- The Linux equivalent is `file` / `file_content` - same semantics, different capitalisation.

---

## `Directory` { #Directory-windows }

Create or remove a directory.

### Syntax

```powershell
Directory '<Path>' <State> [-Recursive]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Create the directory (with parents) if missing. |
| `Absent` | Remove the directory, recursively. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | Full path to the directory. |
| `-Recursive` | *off* | Reserved for future attribute-recursion. Has no effect on creation (always recursive). |

### Examples

```powershell
Directory 'C:\inetpub\wwwroot\myapp' Present
Directory 'C:\temp\old-cache' Absent
```

### Destroy mode

`Present` flips to `Absent` - the directory and its contents are deleted.

### Notes

- `Present` uses `New-Item -ItemType Directory -Force`, so intermediate parents are created.
- `Absent` uses `Remove-Item -Recurse -Force`. Contents go with the directory.
- No owner / mode enforcement; Windows ACLs are managed through `DscResource` wrapping `PSDscResources.NTFSAccessEntry` or similar if needed.

---

## `Package` { #Package-windows }

Install or uninstall software on Windows. Falls back across winget, Chocolatey, and the PowerShellGet `Package` provider (MSI).

### Syntax

```powershell
Package '<Name>' <State>
```

### State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Ensure the package is installed. |
| `Uninstalled` | `Absent` | Ensure the package is not installed. |

### Parameters

| Parameter | Description |
|-----------|-------------|
| `-Name` | *(positional 0)* The package identifier. Format depends on the detected manager (see below). |
| `-State` | *(positional 1)* One of `Installed`, `Uninstalled`, `Present`, `Absent`. |

### Detected managers

In order; the first one that's available wins:

1. **winget** - IDs are Microsoft-curated (e.g. `7zip.7zip`, `Notepad++.Notepad++`).
2. **Chocolatey** (`choco`) - IDs from community.chocolatey.org (e.g. `notepadplusplus`).
3. **Get-Package / Install-Package** (built-in) - fallback, works with MSIs.

The manager that succeeded is recorded in the compliance report's detail field.

### Examples

```powershell
Package '7zip.7zip'            Installed       # winget ID
Package 'notepadplusplus'      Installed       # choco ID
Package 'Legacy-Tool'          Uninstalled
```

### Destroy mode

`Installed` flips to `Uninstalled` and vice versa.

### Errors

- `install failed via <manager>` - the selected manager returned non-zero, or the package is still in the wrong state after the command.

### Notes

- `winget` and `choco` both need to be in the system `PATH` or the fallback kicks in.
- If winget is installed but returns "not found" for your ID, the fallback to choco is **not** automatic - we commit to the first available manager. Make sure the package ID matches the chosen manager.
- For PowerShell module installs (like DSC modules), use [`PowerShellModule`](#PowerShellModule), not `Package`.

---

## `Execute` { #Execute }

Run an arbitrary command (PowerShell or external EXE), idempotently. Idempotency comes from a guard (`-Creates`, `-OnlyIf`, or `-NotIf`) that the resource consults before executing.

This is the escape hatch for installers (MSI / EXE), one-shot bootstraps, and operations that don't fit a more specific resource. Keep configurations as declarative as possible; reach for `Execute` when there's no purpose-built resource.

### Syntax

```powershell
Execute '<Name>' [-State Run] -Command '<command>' `
                 [-Creates <path>] [-OnlyIf <expr>] [-NotIf <expr>] `
                 [-Cwd <path>] [-EnvVars @{...}] [-TimeoutSec N] `
                 [-Interpreter powershell|pwsh|cmd] [-Notify <handler>]
```

The `Name` is a logical identifier - it appears in the report and in log output but doesn't have to match anything on disk.

### Guards (idempotency)

At least one is recommended. If multiple are supplied, all must agree the command needs to run.

| Parameter | Skip when |
|-----------|-----------|
| `-Creates` | The path exists. Most natural for "install something that creates a file." |
| `-OnlyIf`  | The PowerShell expression is `$false` or returns non-zero exit code. Run only if it succeeds. |
| `-NotIf`   | The PowerShell expression is `$true` or returns exit 0. Skip if it succeeds. |

Guards run in this order: `-Creates`, then `-NotIf`, then `-OnlyIf`. The first one that says "skip" wins.

### Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Command` | - | The command to run. **Required.** |
| `-Cwd` | - | Working directory. |
| `-EnvVars` | - | Hashtable of environment variables. |
| `-TimeoutSec` | 600 | Wall-clock timeout in seconds. |
| `-Interpreter` | `powershell` | One of `powershell`, `pwsh`, or `cmd`. Picks the shell that runs `-Command`. |
| `-Notify` | - | Handler name to fire when the command runs. |

### Examples

#### Install an MSI with idempotency via `-Creates`

```powershell
File 'C:\temp\agent.msi' Present `
     -Source   'https://vendor.com/agent.msi' `
     -Checksum 'sha256:abc123...'

Execute 'install-vendor-agent' `
        -Command     'msiexec /i C:\temp\agent.msi /qn /norestart' `
        -Creates     'C:\Program Files\Vendor\agent.exe' `
        -Interpreter 'cmd'
```

The first run downloads and installs. The second run skips the `Execute` because the binary already exists.

#### Install an EXE installer with silent flags

```powershell
File 'C:\temp\setup.exe' Present `
     -Source   'https://vendor.com/setup.exe' `
     -Checksum 'sha256:abc123...'

Execute 'install-vendor-app' `
        -Command     'C:\temp\setup.exe /S /D=C:\Program Files\Vendor' `
        -NotIf       '(Get-Package -Name "Vendor App" -ErrorAction SilentlyContinue) -ne $null' `
        -Interpreter 'cmd'
```

#### Run a PowerShell script unless a sentinel says it's done

```powershell
Execute 'first-boot-init' `
        -Command 'C:\scripts\Initialize-Server.ps1; New-Item -ItemType File -Path C:\ProgramData\app\.initialized -Force' `
        -NotIf   'Test-Path C:\ProgramData\app\.initialized'
```

#### Run with a working directory and env vars

```powershell
Execute 'rebuild-cache' `
        -Command 'pwsh ./bin/Rebuild-Cache.ps1' `
        -Cwd     'C:\opt\myapp' `
        -EnvVars @{ CACHE_DIR = 'C:\cache\myapp'; WORKERS = '4' } `
        -NotIf   'Test-Path C:\cache\myapp\.fresh'
```

#### Time-bounded operation

```powershell
Execute 'long-import' `
        -Command    'C:\opt\app\bin\Import.ps1' `
        -TimeoutSec 300 `
        -Creates    'C:\ProgramData\app\import-complete'
```

### Reporting

| Outcome | Status | `changed` |
|---------|--------|-----------|
| Guard says skip | `compliant` | `false` |
| Command ran, exit 0 | `compliant` | `true` |
| Command ran, non-zero exit | `error` | `true` |
| Audit mode, command would have run | `non_compliant` | `false` |
| Destroy mode | `compliant` | `false` (skipped) |

Failed-command stdout/stderr are captured to the debug log (first 2000 chars) so you can diagnose without re-running.

### Destroy mode

`Execute` is **skipped** in destroy mode. Most installer commands have no one-line undo; if you need to uninstall something, declare a separate `Execute` for the uninstall (or use `Package <id> Uninstalled` when the package manager is involved).

### Audit mode

In audit mode, `Execute` reports `non_compliant: would run` when its guard says the command would execute. It never actually runs.

### Pitfalls

- **Always pair with a guard.** A guardless `Execute` runs every pass, which defeats the point of idempotent configuration management.
- **`-OnlyIf` and `-NotIf` are evaluated via `Invoke-Expression`.** Treat them as code, not data. Don't interpolate untrusted input.
- **Pick the right `-Interpreter`.** Use `cmd` for `msiexec` and most native installers (avoids PowerShell's argument parsing). Use `powershell` (default) for cmdlet pipelines or .ps1 scripts.
- **MSI and EXE installers vary in silent flags.** Common patterns:
  - MSI: `msiexec /i <file>.msi /qn /norestart` (use `-Interpreter cmd`)
  - InnoSetup: `setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
  - NSIS: `setup.exe /S`
  - WiX: same as MSI

### Notes

- Stdout and stderr are captured but not streamed. Failed-command output is logged to the debug log.
- The default `-Interpreter powershell` runs through `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command <script>`.
- `cmd` interpreter does not honour PowerShell's argument-quoting rules - use it for native commands.
- See also [`File`](#File-windows) for downloading the artifact you want to install, [`Package`](#Package-windows) for winget/Chocolatey-managed packages, [`WindowsService`](#WindowsService) for managing services after install, and [`DscResource`](#DscResource) for wrapping any installed DSC resource.
- The Linux equivalent is `execute` - same semantics.

---

## `WindowsService` { #WindowsService }

Manage a Windows service's running state and startup type. Wraps `Get-Service`, `Start-Service`, `Stop-Service`, `Set-Service`, and `Restart-Service`.

### Syntax

```powershell
WindowsService '<Name>' <State> [-StartupType <type>] [-Notify <handler>]
```

### State

| State | Effect |
|-------|--------|
| `Running` | Start the service if stopped. |
| `Stopped` | Stop the service if running. |
| `Restarted` | Always restart (counts as a change every run). |

### Startup type (optional)

| Value | Effect |
|-------|--------|
| `Automatic` | Start at boot. |
| `Manual` | Require explicit start. |
| `Disabled` | Prevent starting. |
| `AutomaticDelayedStart` | Start at boot after a short delay. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Service short name (as reported by `Get-Service`). |
| `-State` | *(positional 1)* | Running, Stopped, or Restarted. |
| `-StartupType` | *(no change)* | Automatic / Manual / Disabled / AutomaticDelayedStart. |
| `-Notify` | - | Handler to fire on change. |

### Examples

```powershell
WindowsService 'W3SVC'   Running   -StartupType Automatic
WindowsService 'Spooler' Stopped   -StartupType Disabled
WindowsService 'W3SVC'   Restarted                              # fires every run
```

Driven by a handler:

```powershell
File 'C:\inetpub\wwwroot\web.config' Present `
     -Source 's3://cfg/web.config' `
     -Notify 'restart-iis'

Handler 'restart-iis' Restart-Service W3SVC
```

### Destroy mode

`Running` flips to `Stopped`; `Automatic` flips to `Disabled`; `Disabled` flips to `Manual`.

### Errors

- `service not found on this host` - `Get-Service -Name` returned nothing. The service isn't installed. Use [`Package`](#Package-windows) / [`WindowsFeature`](#WindowsFeature) / `DscResource` to install the software that provides the service first.
- `apply failed` - post-apply state check didn't match the desired state. Usually indicates a failed startup; check the service's event log.

### Notes

- Startup-type drift is checked by reading `Win32_Service.StartMode` via CIM and normalising `Auto` - `Automatic` for comparison.
- `Restarted` is treated as "always changed." If you want to restart only when a config changes, use a handler instead.

---

## `RegistryKey` { #RegistryKey }

Manage a registry key or a value under it.

### Syntax

```powershell
RegistryKey '<Path>' <State> `
  [-ValueName <name>] `
  [-ValueData <data>] `
  [-ValueType <String|DWord|QWord|Binary|MultiString|ExpandString>]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Ensure the key exists; if a `-ValueName` is given, ensure the value is set to `-ValueData` of the given type. |
| `Absent` | Remove the value (if `-ValueName` is given) or the whole key. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | PowerShell-style registry path (`HKLM:\SOFTWARE\MyApp`). |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-ValueName` | - | Name of the value under the key. Omit to manage just the key. |
| `-ValueData` | - | The data to set. Required when `-ValueName` is given on `Present`. |
| `-ValueType` | `String` | `String`, `DWord`, `QWord`, `Binary`, `MultiString`, `ExpandString`. |

### Examples

Create a key with a DWORD value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\MyApp' Present `
    -ValueName 'Version' -ValueData '1.2.3' -ValueType String

RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
    -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord
```

Just create the key, no value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany' Present
```

Remove a single value:

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\MyApp' Absent -ValueName 'LegacyFlag'
```

Remove the whole key (and all values under it):

```powershell
RegistryKey 'HKLM:\SOFTWARE\MyCompany\LegacyApp' Absent
```

### Destroy mode

`Present` flips to `Absent`. If the resource was managing just a value, only that value is removed; if it was managing a whole key, the key is removed recursively.

### Notes

- `-Path` uses the PowerShell drive-style (`HKLM:\...`, `HKCU:\...`). Native registry paths like `HKEY_LOCAL_MACHINE\SOFTWARE\...` are not accepted directly.
- Data comparison is done with string coercion. For multi-value / binary types, drift is detected on any change in the string representation.
- When removing an entire key, subkeys go with it (`Remove-Item -Recurse -Force`).

---

## `WindowsFeature` { #WindowsFeature }

Install or uninstall Windows Server roles and features via the `ServerManager` module.

Replaces the `PSDscResources.WindowsFeature` and `xPSDesiredStateConfiguration.xWindowsFeature` DSC resources.

### Syntax

```powershell
WindowsFeature '<Name>' <State> [-IncludeManagementTools] [-IncludeAllSubFeature] [-Source <sxs-path>]

# Or bulk:
WindowsFeature @('Web-Server','Web-Common-Http') Installed -IncludeManagementTools
```

### State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Install the feature. |
| `Uninstalled` | `Absent` | Uninstall the feature. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0, accepts array)* | Feature name(s) from `Get-WindowsFeature`. |
| `-State` | *(positional 1)* | `Installed`, `Uninstalled`, `Present`, or `Absent`. |
| `-IncludeManagementTools` | *off* | Pass `-IncludeManagementTools` to `Install-WindowsFeature`. |
| `-IncludeAllSubFeature` | *off* | Install all nested sub-features. |
| `-Source` | - | SxS (side-by-side) source path for offline installs. |

### Examples

IIS with management tools:

```powershell
WindowsFeature 'Web-Server' Installed -IncludeManagementTools
```

Failover clustering bundle:

```powershell
WindowsFeature 'Failover-Clustering' Installed -IncludeManagementTools
WindowsFeature 'RSAT-Clustering'     Installed
WindowsFeature 'RSAT-AD-PowerShell'  Installed
```

Multiple at once:

```powershell
WindowsFeature @(
    'Web-Server','Web-Common-Http','Web-Default-Doc',
    'Web-Static-Content','Web-Http-Logging'
) Installed -IncludeManagementTools
```

Remove a legacy feature:

```powershell
WindowsFeature 'FS-SMB1' Uninstalled
```

### Destroy mode

`Installed` flips to `Uninstalled`.

### Reboot handling

Many Windows features need a reboot to finish installation. The resource treats `Get-WindowsFeature` returning `InstallState = InstallPending` as *installed with reboot required*, calls `Request-Reboot`, and records the reboot intent. At the end of your configuration check `Test-RebootRequired`:

```powershell
WindowsFeature 'Failover-Clustering' Installed -IncludeManagementTools
Report-Compliance

if (Test-RebootRequired) {
    Write-Host "Reboot required. Restart via `aws ssm send-command -DocumentName AWS-RestartEC2Instance` and re-run."
}
```

### Errors

- `ServerManager module not available` - this isn't a Windows Server host (desktop Windows doesn't ship `ServerManager`).
- `unknown feature` - the name isn't recognised by `Get-WindowsFeature`.
- `did not converge` - post-install state is something other than `Installed` / `InstallPending`.

### Notes

- Multiple names are handled by iterating; if one fails the others still run.
- For Windows Optional Features (client-side `Enable-WindowsOptionalFeature`), use a `DscResource` wrapper around `PSDesiredStateConfiguration.WindowsOptionalFeature`.

---

## `PowerShellModule` { #PowerShellModule }

Install or uninstall a PowerShell module via `Install-Module` (PowerShellGet).

### Syntax

```powershell
PowerShellModule '<Name>' <State> `
  [-Version <version>] `
  [-Repository <name>] `
  [-Scope <CurrentUser|AllUsers>]
```

### State

| State | Aliases | Effect |
|-------|---------|--------|
| `Installed` | `Present` | Install the module. |
| `Uninstalled` | `Absent` | Uninstall all installed versions. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Module name (e.g. `FailoverClusterDsc`, `SqlServerDsc`). |
| `-State` | *(positional 1)* | `Installed`, `Uninstalled`, `Present`, or `Absent`. |
| `-Version` | *(any)* | Pin a specific `RequiredVersion`. Drift is reported if a different version is installed. |
| `-Repository` | `PSGallery` | Source repo. |
| `-Scope` | `AllUsers` | `AllUsers` or `CurrentUser`. |

### Examples

Install the DSC modules commonly used for cluster / SQL configurations:

```powershell
PowerShellModule 'PSDscResources'        Installed
PowerShellModule 'FailoverClusterDsc'    Installed
PowerShellModule 'ComputerManagementDsc' Installed
PowerShellModule 'ActiveDirectoryDsc'    Installed
PowerShellModule 'CertificateDsc'        Installed
PowerShellModule 'SqlServerDsc'          Installed
```

Pin a specific version:

```powershell
PowerShellModule 'FailoverClusterDsc' Installed -Version '2.2.0'
```

Remove an old module:

```powershell
PowerShellModule 'AzureRM' Uninstalled
```

Install from a private repo:

```powershell
PowerShellModule 'MyInternalModule' Installed -Repository 'MyCorpRepo' -Scope AllUsers
```

### Destroy mode

`Installed` flips to `Uninstalled`.

### NuGet bootstrap

On a fresh Windows PowerShell 5.1, the first call to `Install-Module` prompts to install the NuGet provider interactively, which fails under SSM's non-interactive PowerShell. The resource silently pre-installs the NuGet provider (`Install-PackageProvider -Name NuGet -Force -Scope AllUsers`) before the first module install, so this is handled for you.

### Notes

- Uninstall removes *all* installed versions of the module.
- The `PSGallery` repository is auto-set to `Trusted` to avoid the confirmation prompt.
- Module installs go to `C:\Program Files\WindowsPowerShell\Modules\` (for `AllUsers` scope) by default.

---

## `Certificate` { #Certificate }

Import or remove certificates in a Windows certificate store. Handles both `.cer` / `.crt` public certificates and password-protected `.pfx` bundles.

Replaces the ad-hoc `Import-Certificate` / `Import-PfxCertificate` you'd otherwise put in a pre-config script, and covers the same ground as `CertificateDsc.CertificateImport` / `CertificateDsc.PfxImport`.

### Syntax

```powershell
# Import from file:
Certificate -Path '<file>' -Store '<store>' -State Present [-Password <secureString>] [-Exportable]

# Remove by thumbprint:
Certificate -Thumbprint '<thumbprint>' -Store '<store>' -State Absent
```

### State

| State | Effect |
|-------|--------|
| `Present` | Import if the certificate with this thumbprint isn't already in the store. |
| `Absent` | Remove the certificate with this thumbprint from the store. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | - | Path to a `.cer`, `.crt`, or `.pfx` file. Required for `Present`. |
| `-Thumbprint` | *(derived from file)* | SHA-1 thumbprint. Required for `Absent` when `-Path` isn't given. |
| `-Store` | *(required)* | PowerShell cert store path, e.g. `Cert:\LocalMachine\My`, `Cert:\LocalMachine\Root`. |
| `-Password` | - | SecureString for PFX bundles. Required for PFX. |
| `-Exportable` | *off* | For PFX imports, marks the private key as exportable. |

### Common stores

| Store | Purpose |
|-------|---------|
| `Cert:\LocalMachine\Root` | Trusted root CAs |
| `Cert:\LocalMachine\CA` | Intermediate CAs |
| `Cert:\LocalMachine\My` | Personal / server certs (used by IIS) |
| `Cert:\LocalMachine\AuthRoot` | Third-party root CAs |

### Examples

Import a corporate root CA:

```powershell
Certificate -Path  'C:\certs\corp-ca.cer' `
            -Store 'Cert:\LocalMachine\Root' `
            -State Present
```

Import a PFX for IIS, keeping the private key non-exportable:

```powershell
$pw = Get-SecureStringFromSsmParameterStore 'iis/pfx-password'  # your helper
Certificate -Path     'C:\certs\iis-wildcard.pfx' `
            -Store    'Cert:\LocalMachine\My' `
            -Password $pw `
            -State    Present
```

Remove an expired certificate by thumbprint:

```powershell
Certificate -Thumbprint 'ABCDEF0123456789...' `
            -Store      'Cert:\LocalMachine\My' `
            -State      Absent
```

### Destroy mode

`Present` flips to `Absent`.

### Notes

- When `-Path` is given, the resource computes the PFX thumbprint by loading the bundle with the provided `-Password`. `.cer` / `.crt` thumbprints are read directly.
- The Import-PfxCertificate default is to leave the private key non-exportable. Pass `-Exportable` if you specifically need it exportable (usually you don't).
- For DSC encryption certificates (used by LCM), this resource replaces the historical `LCM-Config.ps1` pattern entirely - once imported, any downstream `DscResource` calls that use encrypted credentials find the cert automatically.

---

## `LocalUser` { #LocalUser }

Manage a local Windows user account. For Active Directory users, wrap the `ActiveDirectoryDsc.ADUser` resource via [`DscResource`](#DscResource) instead.

The DSL keyword is `LocalUser` (not `User`) to avoid conflicts with any `User` function you might already have in scope.

### Syntax

```powershell
LocalUser '<Name>' <State> `
  [-Password <secureString>] `
  [-FullName <string>] `
  [-Description <string>] `
  [-PasswordNeverExpires] `
  [-UserMayNotChangePassword] `
  [-Disabled]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Create the user if missing; enforce attributes on existing user. |
| `Absent` | Remove the user. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | User name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Password` | *(none, created without password)* | SecureString for the password. |
| `-FullName` | - | Display name. |
| `-Description` | - | Description field. |
| `-PasswordNeverExpires` | *off* | Set password-never-expires flag. |
| `-UserMayNotChangePassword` | *off* | Prevent user from changing password. |
| `-Disabled` | *off* | Create/leave the account disabled. |

### Examples

Service account with a fixed password (from SSM Parameter Store in production):

```powershell
$pw = ConvertTo-SecureString 'REPLACE-FROM-SSM-PARAMETER-STORE' -AsPlainText -Force

LocalUser 'svc_app' Present `
    -FullName     'App service' `
    -Description  'Runs MyApp via task scheduler' `
    -Password     $pw `
    -PasswordNeverExpires
```

Remove a legacy account:

```powershell
LocalUser 'olduser' Absent
```

### Destroy mode

`Present` flips to `Absent`.

### Errors

- `LocalAccounts module not available` - on very old Windows (pre-Windows 10 / Server 2016) the `LocalAccounts` module doesn't exist. Use `DscResource` with `PSDscResources.User` instead.

### Notes

- Attribute enforcement drift-checks `FullName`, `Description`, `PasswordNeverExpires`, and `Enabled` on existing users. Password drift is not checked (we can't read it back); `Password` is only set on create.
- For membership in a group, use [`LocalGroup`](#LocalGroup).
- Windows built-in aliases: on Windows Server the `User` PowerShell function name is reserved by some modules, so we use `LocalUser` to avoid conflicts.

---

## `LocalGroup` { #LocalGroup }

Manage a local Windows group and its membership. For AD groups, wrap `ActiveDirectoryDsc.ADGroup` via [`DscResource`](#DscResource).

Named `LocalGroup` (not `Group`) because `Group` is an alias for PowerShell's built-in `Group-Object` cmdlet.

### Syntax

```powershell
LocalGroup '<Name>' <State> `
  [-Description <string>] `
  [-Members <string[]>] `
  [-MembersToInclude <string[]>] `
  [-MembersToExclude <string[]>]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Create the group if missing; enforce membership. |
| `Absent` | Remove the group. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Group name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Description` | - | Group description. |
| `-Members` | - | **Declarative** list. The group's membership is REPLACED to be exactly this set. |
| `-MembersToInclude` | - | **Additive** list. These members are added; existing members left alone. |
| `-MembersToExclude` | - | **Subtractive** list. These members are removed; other members left alone. |

Use `-Members` *or* `-MembersToInclude` / `-MembersToExclude`, not both.

### Examples

Declarative - these are the only members:

```powershell
LocalGroup 'AppOperators' Present `
    -Description 'Operators of MyApp' `
    -Members     'svc_app','CORP\deployer'
```

Additive - add without removing existing members:

```powershell
LocalGroup 'Remote Desktop Users' Present `
    -MembersToInclude 'CORP\helpdesk'
```

Subtractive:

```powershell
LocalGroup 'Administrators' Present `
    -MembersToExclude 'CORP\ex-employee'
```

Remove a group:

```powershell
LocalGroup 'OldGroup' Absent
```

### Destroy mode

`Present` flips to `Absent`.

### Notes

- Members can be local accounts (`Alice`) or domain accounts (`CORP\alice`). Domain members require the host to be domain-joined and able to resolve the account.
- `-Members` with an empty array means "empty group" (removes all members).
- The compliance report counts adds and removes separately (e.g. `members: +1 -2`).

---

## `HostEntry` { #HostEntry }

Manage an entry in `C:\Windows\System32\drivers\etc\hosts`.

### Syntax

```powershell
HostEntry '<IpAddress>' <State> [-Hostname '<name>'] [-HostsFile <path>]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Ensure the line `<ip> <hostname>` is in the file. |
| `Absent` | Remove any line starting with this IP. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-IpAddress` | *(positional 0)* | The IP address. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Hostname` | - | Hostname or space-separated aliases. Required for `Present`. |
| `-HostsFile` | `$env:SystemRoot\System32\drivers\etc\hosts` | Override for testing. |

### Examples

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

### Destroy mode

`Present` flips to `Absent`.

### Notes

- Entries are written with a tab separating IP and hostname, matching Windows's `hosts` convention.
- If the same IP appears more than once, the resource normalises to a single line on enforce. Other IPs are untouched.
- Writes the file as ASCII (required by Windows DNS client).

---

## `EnvironmentVariable` { #EnvironmentVariable }

Manage a persistent Machine, User, or Process-scoped environment variable.

### Syntax

```powershell
EnvironmentVariable '<Name>' <State> [-Value <string>] [-Target <Machine|User|Process>] [-Path]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Ensure the variable exists with the given value. |
| `Absent` | Remove the variable. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Variable name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Value` | - | The value to set. Required for `Present`. |
| `-Target` | `Machine` | Scope: `Machine`, `User`, or `Process`. |
| `-Path` | *off* | Treat as a PATH-style list. `Value` is appended to the current variable if not already present (dedup via string match). |

### Examples

System-wide JAVA_HOME:

```powershell
EnvironmentVariable 'JAVA_HOME' Present `
    -Value  'C:\Program Files\Java\jdk-17' `
    -Target Machine
```

Append to PATH without obliterating existing entries:

```powershell
EnvironmentVariable 'PATH' Present `
    -Value  'C:\Tools;C:\Program Files\Custom' `
    -Target Machine `
    -Path
```

Remove a deprecated variable:

```powershell
EnvironmentVariable 'LEGACY_VAR' Absent
```

### Destroy mode

`Present` flips to `Absent`.

### Notes

- `Machine` target requires admin privileges (the SSM Agent runs as SYSTEM so this is fine under SSM).
- `Process` changes are visible to the current configuration run only — not persisted.
- PATH appending uses `;` as separator (Windows convention). Deduplication is string-exact, so `C:\Tools` and `C:\Tools\` are different.
- Changes take effect for new processes. Existing sessions won't see the new value until they respawn.

---

## `ScheduledTask` { #ScheduledTask }

Manage a Windows Scheduled Task. This is the Windows analogue of the Linux [`cron`](#cron) resource.

Tasks managed by SSM Converge are tagged with a marker in their Description (`[managed by ssm-converge]`), so unrelated tasks are left alone.

### Syntax

```powershell
ScheduledTask '<Name>' <State> `
  [-Execute <path>] [-Argument <string>] `
  [-Daily <HH:mm> | -IntervalMinutes <N>] `
  [-RunAsUser <SYSTEM|user>] `
  [-Path <taskpath>]
```

### State

| State | Effect |
|-------|--------|
| `Present` | Create/update the task with the specified schedule + action. |
| `Absent` | Unregister the task. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Task name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Execute` | - | Executable to run. Required for `Present`. |
| `-Argument` | - | Command-line arguments. |
| `-Daily` | - | Time in `HH:mm` for a daily trigger. |
| `-IntervalMinutes` | - | Numeric interval for a repeating trigger. |
| `-RunAsUser` | `SYSTEM` | Principal to run the task as. |
| `-Path` | `\` | Task Scheduler folder path. |

Exactly one of `-Daily` or `-IntervalMinutes` must be provided for `Present`.

### Examples

Daily cleanup at 02:00 as SYSTEM:

```powershell
ScheduledTask 'Nightly-Cleanup' Present `
    -Execute  'powershell.exe' `
    -Argument '-NoProfile -File C:\scripts\cleanup.ps1' `
    -Daily    '02:00' `
    -RunAsUser 'SYSTEM'
```

Every 15 minutes:

```powershell
ScheduledTask 'Health-Check' Present `
    -Execute         'C:\scripts\health.ps1' `
    -IntervalMinutes 15 `
    -RunAsUser       'SYSTEM'
```

Remove a stale task:

```powershell
ScheduledTask 'OldBackup' Absent
```

### Destroy mode

`Present` flips to `Absent`.

### Notes

- The marker lives in the task Description; tasks you created by hand (without the marker) are left alone.
- On change, the task is unregistered and re-registered atomically. Triggers and actions are fully replaced.
- For running as a domain user, pass `-RunAsUser 'CORP\serviceuser'`. You'll need to pre-install a credential via a separate mechanism (e.g. `DscResource` with `PSDscResources.xScheduledTask` for richer credential handling).

---

## `DscResource` (generic wrapper) { #DscResource }

Invoke **any** existing DSC resource (from any installed module) through SSM Converge's check/apply/report pipeline.

This is the keystone that lets you reuse your existing DSC investment without rewriting. The module stays the same; the execution model and reporting move to SSM Converge.

### Syntax

```powershell
DscResource `
    -Name       '<ResourceName>' `
    -Module     '<ModuleName>' `
    -Properties @{ <property hashtable> } `
   [-ResourceId '<stable-label>']
```

### How it works

1. **Test** - `Invoke-DscResource -Method Test` determines whether the node is already in the desired state.
2. **Set** - In `enforce` or `destroy` mode, if Test returned `InDesiredState=false`, `Invoke-DscResource -Method Set` applies the change.
3. **Re-test** - After Set, another Test confirms convergence; if still drifted, the run is recorded as `error`.
4. **Reboot tracking** - If Set returns `RebootRequired=true`, the reboot intent is recorded and `Test-RebootRequired` at the end of the configuration reports it.

### Parameters

| Parameter | Description |
|-----------|-------------|
| `-Name` | The DSC resource type name (e.g. `Cluster`, `ADUser`, `SqlSetup`). |
| `-Module` | The PowerShell module that provides the resource (`FailoverClusterDsc`, `ActiveDirectoryDsc`, `SqlServerDsc`, ...). |
| `-Properties` | A hashtable of the resource's properties as you'd write them in a native DSC configuration. Passed straight through to `Invoke-DscResource -Property`. |
| `-ResourceId` | Optional stable label used in the compliance report. If omitted, the resource picks a sensible key from `Properties.Name` / `DomainName` / `Path` / `ServiceAccountName` / `Id` / `Identity`, whichever exists first. |

### Works with any DSC module

Examples of what you can wrap:

| Module | Resources |
|--------|-----------|
| `PSDscResources` | `WindowsFeature`, `WindowsOptionalFeature`, `Script`, `Registry`, `NTFSAccessEntry`, ... |
| `FailoverClusterDsc` | `Cluster`, `ClusterNode`, `ClusterResource`, `ClusterDisk`, ... |
| `ComputerManagementDsc` | `Computer`, `TimeZone`, `ScheduledTask`, `SystemLocale`, `PowerPlan`, ... |
| `CertificateDsc` | `CertificateImport`, `PfxImport`, `CertReq`, ... |
| `ActiveDirectoryDsc` | `ADUser`, `ADGroup`, `ADServiceAccount`, `ADManagedServiceAccount`, `ADOrganizationalUnit`, ... |
| `SqlServerDsc` | `SqlSetup`, `SqlLogin`, `SqlDatabase`, `SqlRole`, `SqlAGDatabase`, `SqlRSSetup`, ... |
| `NetworkingDsc` | `FirewallRule`, `DNSServerAddress`, `DefaultGatewayAddress`, ... |
| `StorageDsc` | `Disk`, `MountImage`, `OpticalDiskDriveLetter`, ... |

Any properly-packaged class-based or MOF-based DSC resource works. The library doesn't hard-code a list.

### Examples

#### Failover cluster creation

```powershell
PowerShellModule 'FailoverClusterDsc' Installed

DscResource -Name Cluster -Module FailoverClusterDsc -Properties @{
    Name            = 'SQLCluster01'
    StaticIPAddress = '10.0.1.100/24'
    Ensure          = 'Present'
}
```

#### Domain join (replaces ComputerManagementDsc.Computer)

```powershell
$joinCred = Get-SsmParameterCredential 'domain/joiner'   # your helper

DscResource -Name Computer -Module ComputerManagementDsc -Properties @{
    Name       = 'SQL01-A'
    DomainName = 'corp.example.com'
    Credential = $joinCred
}
```

#### gMSA provisioning (replaces the whole Create-ADServiceAccountDSC.ps1 pattern)

```powershell
DscResource -Name ADManagedServiceAccount -Module ActiveDirectoryDsc -Properties @{
    ServiceAccountName         = 'svc-sql01'
    AccountType                = 'Group'
    ManagedPasswordPrincipals  = 'SQL01-A$','SQL01-B$'
    Path                       = 'OU=Service Accounts,OU=Corp,DC=corp,DC=example,DC=com'
    Ensure                     = 'Present'
}
```

#### Full SQL Server install

```powershell
PowerShellModule 'SqlServerDsc' Installed

DscResource -Name SqlSetup -Module SqlServerDsc -Properties @{
    InstanceName            = 'MSSQLSERVER'
    Features                = 'SQLENGINE,FULLTEXT'
    SourcePath              = 'C:\sql-media'
    SQLSvcAccountUsername   = 'NT Service\MSSQLSERVER'
    SQLSysAdminAccounts     = @("$env:COMPUTERNAME\SqlAdmins","BUILTIN\Administrators")
    UpdateEnabled           = 'True'
}
```

#### Firewall rule

```powershell
DscResource -Name FirewallRule -Module NetworkingDsc -Properties @{
    Name      = 'AllowHTTP'
    Direction = 'Inbound'
    LocalPort = 80
    Protocol  = 'TCP'
    Action    = 'Allow'
    Ensure    = 'Present'
}
```

### Destroy mode

If the resource's `Properties` hash contains an `Ensure` key, destroy mode flips its value (`Present` <-> `Absent`). If there's no `Ensure` key, destroy mode is a no-op for that resource.

### Errors

- `Invoke-DscResource not available` - the host doesn't have `PSDesiredStateConfiguration` loadable. On Windows PowerShell 5.1 it's built-in; on PowerShell 7, install the v2 module separately.
- `DSC Test failed: Resource <Name> was not found` - the DSC module providing the resource isn't installed. Precede the `DscResource` call with [`PowerShellModule '<Module>' Installed`](#PowerShellModule).
- `DSC Set failed: <message>` - the underlying resource raised an error. The message is surfaced verbatim; consult the DSC module's docs.
- `set did not converge` - Set completed without exception, but the subsequent Test still returns drifted. Usually indicates a configuration problem with the resource inputs.

### What you gain by wrapping DSC resources

Compared to calling `Invoke-DscResource` directly in a `runPowerShellScript` step:

1. **Modes for free.** The same configuration runs in `audit`, `enforce`, `destroy`, or `comply` mode. Your DSC resources work in all four.
2. **Compliance reporting.** Every DSC resource's Test result becomes a row in `latest.json`, with check + apply timings, the run ID, and the resource's stable ID.
3. **Handler chaining.** A DSC-resource-driven change can `-Notify` a handler the same way a primitive can.
4. **Reboot handling.** `Request-Reboot` is called automatically if the DSC Set reports `RebootRequired`.
5. **Idempotency assurance.** The post-set re-Test proves the resource actually converged; DSC doesn't always do this itself.

### What you don't get

- No MOF compilation. You pass the `-Properties` hashtable as PowerShell data, not via a `Configuration {}` block. This is the same shape you'd use with `Invoke-DscResource` directly.
- No dependency graph between DSC resources. Resources run in declaration order, top to bottom.
- No LCM. The SSM Agent is the scheduler — you don't have a local configuration manager pulling state on a cron.

### When to use a primitive vs. DscResource

- **If a primitive exists** (`LocalUser`, `LocalGroup`, `WindowsService`, `WindowsFeature`, `RegistryKey`, etc.), use it. Faster, no DSC module to install, clearer error messages.
- **If the primitive doesn't cover your case** (custom DSC resources, SQL, cluster, AD, complex registry permissions), use `DscResource`. You're almost certainly reusing a DSC resource someone else has already written.
- **If you're building something truly custom**, write a PowerShell function in a helper module and have your configuration call it. `DscResource` is only worth it when you're wrapping an existing third-party module.

---


---

*Source files: per-resource pages in [Linux index](index.md#linux-index) and [Windows index](index.md#windows-index). Regenerate with `bash docs/resources/build-usage.sh`.*
