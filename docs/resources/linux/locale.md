# `locale`

Set the system LANG locale.

## Syntax

```bash
locale '<locale>'
```

## Examples

```bash
locale 'en_US.UTF-8'
locale 'ja_JP.UTF-8'
locale 'C.UTF-8'
```

## How it's applied

Detected in this order:

| Detected | Uses |
|----------|------|
| `localectl` available (systemd) | `localectl set-locale LANG=<value>` |
| `/etc/default/locale` exists (Debian/Ubuntu) | Writes `LANG=<value>`; runs `locale-gen` if available |
| `/etc/locale.conf` exists (RHEL/CentOS) | Writes `LANG=<value>` |

The current shell's `$LANG` is also exported so subsequent commands in the same run use the new value.

## Destroy mode

**Skipped.** Same rationale as [`timezone`](timezone.md).

## Notes

- The locale must already be generated on the system. On Debian/Ubuntu the resource attempts `locale-gen <value>`; on other distros you may need to install a locale package (`glibc-langpack-en` on RHEL 8+, for example).
- Drift comparison reads the current `LANG` from `/etc/default/locale` or `/etc/locale.conf`, whichever exists. On minimal images where neither exists, the resource falls back to the current shell's `$LANG`.
