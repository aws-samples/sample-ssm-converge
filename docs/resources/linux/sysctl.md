# `sysctl`

Set (and optionally persist) a Linux kernel parameter.

## Syntax

```bash
sysctl '<key>' value '<value>' [persist true|false]
```

No "desired state" - sysctl is always a declarative "set to this value."

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `value` | *(required)* | The value to set. Space-separated values (like `1024 65535`) are fine. |
| `persist` | `true` | When `true`, also write the key=value pair into `/etc/sysctl.d/99-ssm-converge.conf` so it survives reboot. |

## Examples

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

## Destroy mode

**Skipped.** Kernel parameters have no safe inverse (what's the opposite of `vm.swappiness=10`?). The resource records `compliant` with detail `"skipped in destroy mode"`.

## Errors

- `sysctl -w failed` - invalid key, or the kernel refused the value (e.g. a read-only parameter, or a key that requires a specific module to be loaded).

## Notes

- The resource uses the absolute path to the `sysctl` binary (typically `/usr/sbin/sysctl`) internally to avoid recursing into the DSL function of the same name.
- Whitespace normalisation: runs of whitespace in both the current and desired values are collapsed to single spaces before comparison. This handles space-separated values like `ip_local_port_range` correctly (kernel returns them tab-separated).
- When `persist true`, the same key is rewritten in `/etc/sysctl.d/99-ssm-converge.conf` on each change. A `sysctl --system` is **not** automatically issued; the runtime value is set separately via `sysctl -w`.
