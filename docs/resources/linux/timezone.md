# `timezone`

Set the system timezone.

## Syntax

```bash
timezone '<tz>'
```

Just one positional argument — the timezone name. No desired-state keyword (always "set this timezone").

## Examples

```bash
timezone 'UTC'
timezone 'America/New_York'
timezone 'Asia/Tokyo'
```

## How it's applied

Detected in this order:

| Detected | Uses |
|----------|------|
| `timedatectl` available (modern systemd Linux) | `timedatectl set-timezone` |
| `Darwin` | `systemsetup -settimezone` |
| FreeBSD | copies `/usr/share/zoneinfo/<tz>` to `/etc/localtime` |
| Fallback Linux | symlinks `/etc/localtime` and writes `/etc/timezone` |

## Destroy mode

**Skipped.** There's no safe inverse for "set timezone." The resource records `compliant` with detail `"skipped in destroy mode"`.

## Notes

- No state argument — the resource is declarative "set to this value."
- Drift is detected by reading the current value via `timedatectl` or `/etc/timezone` or `readlink /etc/localtime`, depending on platform.
- On Amazon Linux 2023 and other minimal images, `timedatectl show` may return an empty Timezone field until a first set. Subsequent runs then pick up the value correctly.
