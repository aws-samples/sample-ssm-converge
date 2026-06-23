# Report Schema

The JSON document that `get_report_json` / `Get-ReportJson` produces. Stable across versions within the same minor release; changes flagged in the [Changelog](changelog.md).

## Top-level fields

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
  "summary": { ... },
  "resources": [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Library version that produced the report |
| `run_id` | string | Unique-per-run identifier (`<unix-seconds>-<pid>`) |
| `timestamp` | string | ISO-8601 UTC of when the report was assembled |
| `instance_id` | string | EC2 instance ID from IMDSv2; empty if not on EC2 |
| `account_id` | string | AWS account ID; empty if not on EC2 |
| `region` | string | AWS region; empty if not on EC2 |
| `profile` | string | The `DSC_PROFILE` value passed to the run |
| `mode` | string | One of `enforce`, `audit`, `destroy`, `comply` |
| `summary` | object | Aggregate counts; see below |
| `resources` | array | One entry per resource declared; see below |

## `summary` object

```json
{
  "total": 11,
  "compliant": 11,
  "non_compliant": 0,
  "errors": 0,
  "changed": 4,
  "compliance_pct": 100.0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `total` | integer | Number of resources reported |
| `compliant` | integer | Resources whose final state matches desired |
| `non_compliant` | integer | Drift detected and not converged (audit mode, or apply failed to converge) |
| `errors` | integer | Resources where check or apply threw an error |
| `changed` | integer | How many resources actually modified state this run |
| `compliance_pct` | number | `(compliant / total) * 100`, rounded to one decimal |

## `resources` array

Each entry:

```json
{
  "resource": "package/nginx",
  "status": "compliant",
  "changed": false,
  "detail": "",
  "timestamp": "2026-05-13T18:30:07Z",
  "run_id": "1778671806-53379",
  "check_duration_ms": 12,
  "apply_duration_ms": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `resource` | string | `<resource-type>/<name>` — stable identifier across runs |
| `status` | string | One of `compliant`, `non_compliant`, `error` |
| `changed` | boolean | Did this run modify the system? |
| `detail` | string | Free-text reason; empty when status is clean compliant |
| `timestamp` | string | ISO-8601 UTC of when this resource finished |
| `run_id` | string | Run ID, repeated for downstream joining |
| `check_duration_ms` | integer | Time spent in the check phase |
| `apply_duration_ms` | integer | Time spent in the apply phase (0 if no apply) |

### Resource identifier conventions

| Resource type | Identifier shape |
|---------------|------------------|
| `package` | `package/<name>` |
| `file` / `File` | `file<path>` (no slash separator — path starts with `/` or `C:\`) |
| `directory` / `Directory` | `directory<path>` |
| `service` / `WindowsService` | `service/<name>` or `service/<name>` |
| `user` / `LocalUser` | `user/<username>` |
| `execute` / `Execute` | `execute/<name>` |
| `registry_key` / `RegistryKey` | `registry/<full-key-path>` |
| `dsc_resource` / `DscResource` | `dsc/<resource-name>` |

### Status semantics

| `status` | When |
|----------|------|
| `compliant` | Current state matches desired state. May or may not have been fixed this run (`changed` distinguishes). |
| `non_compliant` | Drift detected in `audit` mode, or apply attempted and could not converge. |
| `error` | Check or apply failed (missing binary, permission denied, invalid argument, exit code from the underlying tool). The `detail` field includes the failure reason. |

### `detail` field examples

```text
""                                         # clean compliant
"converged: content drift"                 # was non-compliant, applied successfully
"mode is 0755, want 0644"                  # audit-mode drift
"download failed"                          # error during file fetch
"checksum mismatch"                        # downloaded content didn't match expected hash
"exit 5: ls: /no/such/path: ..."           # execute failed; includes most-useful stderr line
"skipped in destroy mode"                  # destroy mode, no-op resource (sysctl, execute, etc.)
"$Creates exists"                          # execute guard satisfied; skipped
```

The `detail` string is plain text - downstream consumers should treat it as opaque human-readable context, not parse it for structure.

## Schema stability

Within a minor version (`0.1.x`), the schema is **add-only**: existing fields keep their meaning, new fields may appear, no fields are removed.

Across minor versions, breaking changes are documented in the [Changelog](changelog.md) with migration notes. Major-version bumps may include schema reorganisation.

## Consuming the schema

### jq one-liners

```bash
# Total resources by status
get_report_json | jq '.resources | group_by(.status) | map({status: .[0].status, count: length})'

# Slowest resources
get_report_json | jq '.resources | sort_by(-.apply_duration_ms) | .[0:5] | .[] | {resource, apply_duration_ms}'

# Anything that errored, with details
get_report_json | jq '.resources[] | select(.status == "error") | {resource, detail}'

# Compliance pct as a single number
get_report_json | jq '.summary.compliance_pct'
```

### Python

```python
import json, sys
report = json.load(sys.stdin)

errored = [r for r in report['resources'] if r['status'] == 'error']
for r in errored:
    print(f"{r['resource']}: {r['detail']}")

if report['summary']['compliance_pct'] < 95:
    sys.exit(1)
```

## Local report files

`report_compliance` / `Report-Compliance` writes the report to disk in addition to making it retrievable via `get_report_json`:

| File | Purpose |
|------|---------|
| `<DSC_LOCAL_DIR>/latest.json` | The most recent run's full report. Overwritten each run. |
| `<DSC_LOCAL_DIR>/history/<run_id>.json` | Per-run archive. Last `DSC_HISTORY_RETAIN` (default 50) kept. |
| `<DSC_LOCAL_DIR>/drift.log` | Plain-text drift log; one line per non-compliant or error result. |

Default `DSC_LOCAL_DIR`:

- Linux: `/var/lib/ssm-converge`
- Windows: `C:\ProgramData\ssm-converge`
