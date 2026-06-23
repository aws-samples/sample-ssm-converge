# CLI Reference

The `ssm-converge` CLI is a thin wrapper around the library that standardises the operator experience across platforms. Configurations work fine when invoked directly with `bash my-config.sh` or `. my-config.ps1`; the CLI exists to give you the same commands on every supported OS.

## Subcommands

```text
ssm-converge run     <config>    Run in enforce mode (default behaviour)
ssm-converge check   <config>    Run in audit mode (read-only)
ssm-converge destroy <config>    Run in destroy mode (flip desired state)
ssm-converge comply  <config>    Run in audit mode + full per-resource report
ssm-converge status              Print the last run's summary
ssm-converge history             List the last N saved runs (default 10)
ssm-converge drift               Tail the local drift log
ssm-converge export              Print the latest run's JSON to stdout
ssm-converge version             Print the library version
ssm-converge help                Show usage
```

## Flags

```text
-v, --version    Same as `version` subcommand
-h, --help       Same as `help` subcommand
```

## Common workflows

### Local development loop

```bash
# Syntax check
bash -n my-config.sh

# Audit-only run
ssm-converge check my-config.sh

# Apply changes
ssm-converge run my-config.sh

# Re-audit; should be 0 changes
ssm-converge check my-config.sh

# Inspect what happened
ssm-converge status
ssm-converge export | jq '.summary'
```

### Triage on a host that's misbehaving

```bash
# Last run summary
ssm-converge status

# Drift log
ssm-converge drift | tail -50

# Full report from the latest run
ssm-converge export | jq '.resources[] | select(.status != "compliant")'

# Look at past runs
ssm-converge history
```

## Environment variables

The CLI honours every environment variable the library uses:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DSC_MODE` | `enforce` | One of `enforce`, `audit`, `destroy`, `comply` |
| `DSC_PROFILE` | `default` | Label that appears in the report |
| `DSC_REPORT` | `summary` | `summary` or `full` |
| `DSC_VERBOSE` | `true` | Per-resource OK / CHANGED / DRIFT lines on stdout |
| `DSC_DEBUG` | `true` | Debug log written to `/var/log/ssm-converge.log` |
| `DSC_LOG_FILE` | `/var/log/ssm-converge.log` | Override the debug log location |
| `DSC_LOCAL_DIR` | `/var/lib/ssm-converge` | Where `latest.json`, `history/`, `drift.log` live |
| `DSC_HISTORY_RETAIN` | `50` | How many past run reports to keep in `history/` |
| `SSM_CONVERGE_HOME` | `/opt/ssm-converge` | Library install path (defaults differ on Windows) |

## Windows differences

The Windows CLI is `ssm-converge.ps1`, located at `C:\ProgramData\ssm-converge\ssm-converge.ps1`. Add that path to `PATH` if you want bare `ssm-converge` invocation; otherwise reference it explicitly:

```powershell
& C:\ProgramData\ssm-converge\ssm-converge.ps1 run   webserver.ps1
& C:\ProgramData\ssm-converge\ssm-converge.ps1 check webserver.ps1
```

Or import once and invoke by short name:

```powershell
Set-Alias ssm-converge 'C:\ProgramData\ssm-converge\ssm-converge.ps1'
ssm-converge run webserver.ps1
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | All resources compliant; no errors |
| `1` | One or more resources reported `error` |
| `2` | Audit mode detected drift (`non_compliant > 0`) |

These are stable; downstream automation (CI gates, alerting) can depend on them.
