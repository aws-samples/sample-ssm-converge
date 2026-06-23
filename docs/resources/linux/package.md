# `package`

Install, upgrade, or remove software using whichever package manager the host provides.

## Syntax

```bash
package '<name>' <state> [key value ...]
```

## Actions (desired state)

| State | Aliases | Effect |
|-------|---------|--------|
| `installed` | `present` | Ensure the package is installed. Optionally matches a version prefix. |
| `uninstalled` | `removed`, `absent` | Ensure the package is not installed. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `version` | *(any)* | Match this version prefix. On install, picks the matching version; on check, drift is reported if installed version doesn't start with this string. |

## Supported package managers

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

## Examples

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

## Destroy mode

`installed` flips to `uninstalled` and vice versa. Useful for `ssm-converge destroy mybaseline.sh` to remove everything the configuration added.

## Errors

- `no package manager` - none of the detected managers is available on this host.
- `install failed` / `remove failed` - the underlying manager returned non-zero or the package is still in the wrong state after the command.

## Notes

- The resource calls `apt-get update` before installs on Debian/Ubuntu.
- Version match uses a prefix comparison (`1.24` matches `1.24.0`, `1.24.1-ubuntu3`).
- Removing a package on Debian uses `apt-get remove`, not `purge`. Config files are retained.
