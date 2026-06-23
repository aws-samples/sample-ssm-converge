# Handlers & Notifications

The "reload nginx after the config file changes" pattern, declared once and de-duplicated automatically.

## The pattern

A resource that changes can `notify` a named handler. Handlers run **once at the end of the configuration**, regardless of how many resources triggered them.

=== "Linux"

    ```bash
    file '/etc/nginx/nginx.conf' present \
      source 's3://cfg/nginx.conf' \
      notify 'reload-nginx'

    file '/etc/nginx/sites-available/default.conf' present \
      source 's3://cfg/default.conf' \
      notify 'reload-nginx'

    file '/etc/nginx/conf.d/headers.conf' present \
      source 's3://cfg/headers.conf' \
      notify 'reload-nginx'

    service 'nginx' running enabled

    # Handler defined once. Runs once even though three files notified it.
    handler 'reload-nginx' systemctl reload nginx
    ```

=== "Windows"

    ```powershell
    File 'C:\inetpub\wwwroot\web.config' Present `
         -Source 's3://cfg/web.config' `
         -Notify 'restart-iis'

    File 'C:\inetpub\wwwroot\App_Data\settings.json' Present `
         -Source 's3://cfg/settings.json' `
         -Notify 'restart-iis'

    WindowsService 'W3SVC' Running -StartupType Automatic

    Handler 'restart-iis' Restart-Service W3SVC
    ```

## Why end-of-run, not in-line?

Three reasons.

1. **Avoid restart storms.** Without de-duplication, three file changes in a row would restart nginx three times. Handlers run exactly once even if 50 resources notified them.

2. **Stable apply order.** Resources run in the order they're declared. If a handler ran inline, a later resource that also notified the same handler would queue a *second* invocation. End-of-run means: all changes are made, *then* services pick up the new state.

3. **Failures don't half-restart you.** If a later resource errors, the handler still runs because all of the prior changes succeeded. Conversely, if no resource changed anything (steady-state second pass), the handler doesn't run at all — even though it's *declared* in the configuration.

## Handler is just a command

A handler is a name and a command. It runs verbatim through the shell at end-of-run.

```bash
# Linux: anything you'd type at a shell.
handler 'reload-nginx'        systemctl reload nginx
handler 'flush-iptables'      iptables -F
handler 'rebuild-cache'       sudo -u myapp /opt/myapp/bin/rebuild-cache
handler 'reload-systemd'      systemctl daemon-reload
```

```powershell
# Windows: any PowerShell command line.
Handler 'restart-iis'         Restart-Service W3SVC
Handler 'reload-nginx'        nssm restart nginx
Handler 'rebuild-cache'       & 'C:\opt\myapp\bin\Rebuild-Cache.ps1'
```

## Handler outcomes in the report

Each handler that fires records a result with the resource name `handler/<name>`:

| Outcome | Status |
|---------|--------|
| Notified, ran, exit 0 | `compliant, changed=true` |
| Notified, ran, non-zero exit | `error, changed=true` |
| Notified but configuration didn't change anything | (not invoked; not in report) |

A failed handler doesn't fail the run — it's recorded as an error and the configuration moves on. Handlers are best-effort by design; the desired state was already converged when they fire.

## What handlers are not

- **Not for declaring desired state.** Use a resource for that.
- **Not for cross-resource ordering.** Resources run in declaration order; that's your ordering primitive.
- **Not a fan-out mechanism.** A single handler can run a single command. If you need a sequence, write a wrapper script and invoke that.

## When to skip handlers entirely

For very simple "always restart this service after I touch its config" cases, you can also use the resource's own state machine:

```bash
# Approach A: notify handler (what we just covered).
file '/etc/redis.conf' present source 's3://cfg/redis.conf' notify 'restart-redis'
service 'redis' running enabled
handler 'restart-redis' systemctl restart redis

# Approach B: declare 'restarted' as the desired state. The service resource
# will restart unconditionally on every run.
service 'redis' restarted
```

Approach A is the right pattern when the restart is *conditional* on a config change. Approach B is the right pattern only when you genuinely want a restart on every run (rare).
