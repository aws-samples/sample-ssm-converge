# Compliance Reporting

What the report contains, where it goes, and how to ship it.

## Three places it always ends up

1. **Local file** — `/var/lib/ssm-converge/latest.json` (Linux) or `C:\ProgramData\ssm-converge\latest.json` (Windows). Overwritten every run.
2. **Local history** — same directory, under `history/`. Last 50 runs by default; configurable via `DSC_HISTORY_RETAIN`.
3. **Standard output** — a one-line summary by default; the full table when `DSC_REPORT=full` or `Mode=full`.

What happens *beyond* those three is entirely up to you. The library's job is to produce a structured report; the customer owns where it lands.

## Calling it

=== "Linux"

    ```bash
    # In your configuration, after declaring all resources:
    report_compliance

    # Anywhere later, get the JSON for piping:
    get_report_json
    ```

=== "Windows"

    ```powershell
    # In your configuration:
    Report-Compliance

    # Anywhere later, get the JSON:
    Get-ReportJson
    ```

`report_compliance` / `Report-Compliance` writes the local files and prints the summary. `get_report_json` / `Get-ReportJson` returns the JSON document on stdout.

## The report shape

```json
{
  "version": "0.1.2",
  "run_id": "1778671806-53379",
  "timestamp": "2026-05-13T18:30:07Z",
  "instance_id": "i-0a1b2c3d4e5f6g7h8",
  "account_id": "111122223333",
  "region": "ap-south-1",
  "profile": "webserver",
  "mode": "enforce",
  "summary": {
    "total": 11,
    "compliant": 11,
    "non_compliant": 0,
    "errors": 0,
    "changed": 4,
    "compliance_pct": 100.0
  },
  "resources": [
    {
      "resource": "package/nginx",
      "status": "compliant",
      "changed": false,
      "detail": "",
      "timestamp": "2026-05-13T18:30:07Z",
      "run_id": "1778671806-53379",
      "check_duration_ms": 12,
      "apply_duration_ms": 0
    },
    {
      "resource": "file/etc/nginx/nginx.conf",
      "status": "compliant",
      "changed": true,
      "detail": "converged: content drift",
      "timestamp": "2026-05-13T18:30:07Z",
      "run_id": "1778671806-53379",
      "check_duration_ms": 23,
      "apply_duration_ms": 187
    },
    ...
  ]
}
```

See the [Report Schema reference](../reference/schema.md) for field-by-field descriptions.

## Statuses

Three values, no more:

| Status | Meaning |
|--------|---------|
| `compliant` | Current state matches desired state. May or may not have been fixed this run (`changed` tells you which). |
| `non_compliant` | Drift detected in `audit` mode, or apply attempted and could not converge. |
| `error` | Check or apply failed (missing binary, permission denied, invalid argument). The `detail` field includes the failure reason. |

There is intentionally no "warning." The framework's stance: every resource is in one of three states. If you'd write a warning, it's drift.

## Shipping the report somewhere

The report is just JSON on stdout. Pipe it wherever you need.

### To S3

```bash
get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/$(hostname)/$(date +%Y%m%d%H%M).json"
```

```powershell
Get-ReportJson | Out-File C:\Windows\Temp\report.json -Encoding ascii
Write-S3Object -BucketName DOC-EXAMPLE-BUCKET `
               -Key "$(hostname)/$(Get-Date -Format yyyyMMddHHmm).json" `
               -File C:\Windows\Temp\report.json
```

### To an internal compliance API

```bash
get_report_json | curl -X POST \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data-binary @- \
  https://compliance.internal/api/v1/report
```

### To AWS SSM Compliance

The bundled `reporters/ssm_compliance.sh` (Linux) sample:

```bash
source /opt/ssm-converge/reporters/ssm_compliance.sh
_report_to_ssm_compliance "$(get_report_json)"
```

This calls `aws ssm put-compliance-items` for the run, which makes the data show up in the SSM Compliance dashboard alongside built-in compliance signals like Patch Manager.

### To EventBridge

```bash
source /opt/ssm-converge/reporters/eventbridge.sh
_report_to_eventbridge "$(get_report_json)" "ssm-converge.audit"
```

Useful for triggering downstream automation (Lambda, Step Functions, SNS) on configuration runs.

## Drift log

In addition to the structured report, the library writes a plain-text drift log for grep-style triage:

- Linux: `/var/lib/ssm-converge/drift.log`
- Windows: `C:\ProgramData\ssm-converge\drift.log`

Each line is timestamped and tagged with the run_id. `tail -f` it during rollouts.

## Debug log

Verbose internal logging for the library itself, useful when a resource is misbehaving:

- Linux: `/var/log/ssm-converge.log` (or `/tmp/ssm-converge.log` if /var/log isn't writable)
- Windows: `C:\ProgramData\ssm-converge\ssm-converge.log` (or `%TEMP%\ssm-converge.log`)

Includes the timestamped CHECK / APPLY / NOTIFY trail and, for failed `execute` resources, the first 2KB of stderr/stdout. Disabled by setting `DSC_DEBUG=false`.

## Putting it all together

A typical configuration footer:

=== "Linux"

    ```bash
    # ... resources declared above ...

    handler 'reload-nginx' systemctl reload nginx

    report_compliance

    # Ship the report off-instance.
    get_report_json | aws s3 cp - "s3://DOC-EXAMPLE-BUCKET/webserver/$(hostname)-$(date +%s).json"
    ```

=== "Windows"

    ```powershell
    # ... resources declared above ...

    Handler 'restart-iis' Restart-Service W3SVC

    Report-Compliance

    Get-ReportJson | Out-File C:\Windows\Temp\report.json -Encoding ascii
    Write-S3Object -BucketName DOC-EXAMPLE-BUCKET `
                   -Key "webserver/$(hostname)-$(Get-Date -UFormat %s).json" `
                   -File C:\Windows\Temp\report.json
    ```

That's the full pattern. Library writes structurally, customer routes operationally.
