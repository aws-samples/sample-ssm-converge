# `file_content`

Heredoc-friendly sibling of [`file`](file.md). Reads the file's content from stdin, so multi-line strings don't have to be escaped into a single argument.

## Syntax

```bash
file_content '<path>' [key value ...] <<'EOF'
...file contents...
EOF
```

## Properties

Same as [`file`](file.md): `owner`, `group`, `mode`, `notify`. The `content` comes from the heredoc itself — you don't (and can't) pass it as a keyword argument.

`file_content` always applies `present` — there's no `absent` form; use `file '<path>' absent` for that.

## Examples

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

## Notes

- Uses `'EOF'` (single-quoted) to disable variable expansion, or unquoted `EOF` to enable it - standard bash heredoc semantics.
- Internally just delegates to [`file`](file.md) `present content ...` so all the drift detection, handlers, and destroy-mode behaviour are identical.
