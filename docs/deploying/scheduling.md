# Scheduled Enforcement

Run Command is one-shot. State Manager runs the same command on a schedule and is the right tool for "always be enforcing" or "audit every 30 minutes."

## Create an Association

```bash
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)

aws ssm create-association \
  --association-name webserver-baseline \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(30 minutes)" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64" \
  --max-concurrency "20%" \
  --max-errors "5%" \
  --compliance-severity HIGH
```

## Common patterns

### Audit every 15 minutes (compliance dashboard)

```bash
aws ssm create-association \
  --association-name webserver-audit \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(15 minutes)" \
  --parameters "Mode=audit,Profile=webserver,Report=full,Config=$CFG_B64" \
  --compliance-severity MEDIUM
```

The `--compliance-severity` flag lets non-compliant runs surface in the SSM Compliance dashboard with a severity tag.

### Enforce nightly (slow-moving baselines)

```bash
aws ssm create-association \
  --association-name security-baseline \
  --name SSMConverge-Run \
  --targets "Key=tag:Environment,Values=production" \
  --schedule-expression "cron(0 4 * * ? *)" \
  --parameters "Mode=enforce,Profile=security-baseline,Config=$CFG_B64"
```

`cron(0 4 * * ? *)` is "04:00 UTC every day."

### Enforce on launch (auto-onboard new instances)

```bash
aws ssm create-association \
  --association-name webserver-on-launch \
  --name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "rate(30 minutes)" \
  --apply-only-at-cron-interval false \
  --parameters "Mode=enforce,Config=$CFG_B64"
```

By default, an Association runs against newly-tagged instances **as soon as they appear**, then again on the schedule. The first run typically lands within a minute of the instance becoming SSM-managed. New instances are picked up automatically — no orchestration needed.

## Schedule-expression reference

| Expression | Meaning |
|------------|---------|
| `rate(15 minutes)` | every 15 minutes |
| `rate(2 hours)` | every 2 hours |
| `rate(1 day)` | once a day at the time of association creation |
| `cron(0 4 * * ? *)` | 04:00 UTC daily |
| `cron(0 4 ? * MON-FRI *)` | 04:00 UTC weekdays |
| `cron(*/30 * * * ? *)` | every 30 minutes on the hour and half-hour |

Cron expressions follow [SSM's six-field syntax](https://docs.aws.amazon.com/systems-manager/latest/userguide/reference-cron-and-rate-expressions.html). UTC only.

## Inspecting and updating an Association

```bash
# Show the current association.
aws ssm describe-association \
  --association-id <id-from-create-association>

# Show recent runs.
aws ssm list-association-executions \
  --association-id <id>

# Update parameters (e.g. roll out a new configuration).
NEW_CFG_B64=$(base64 < webserver-v2.sh)
aws ssm update-association \
  --association-id <id> \
  --parameters "Mode=enforce,Profile=webserver,Config=$NEW_CFG_B64"
```

## Compliance signal

When `--compliance-severity` is set, the SSM Compliance dashboard shows per-instance status:

```
Compliance Type   Severity   Status         Source
Association       HIGH       Compliant      <association-id>
Association       HIGH       Non-compliant  <association-id>
```

Combine that with the in-document `report_compliance` call (which writes `latest.json`) and you have two layers of compliance signal: SSM-level (did the run succeed?) and resource-level (what was found).

## When to use Run Command vs an Association

| Need | Tool |
|------|------|
| One-time apply | Run Command |
| Try a configuration on a few instances | Run Command |
| "Always be enforcing" baseline | Association |
| Continuous drift detection feeding a dashboard | Association in `audit` mode |
| Auto-onboard new instances by tag | Association |
| Manual approval gate before each run | Run Command (don't put a manual step in an Association) |

The general rule: anything you'd want to happen "automatically going forward" is an Association. Anything you want to do "once, deliberately" is Run Command.

## Disabling an Association

```bash
aws ssm update-association \
  --association-id <id> \
  --schedule-expression "rate(7 days)"   # effectively pause

# Or delete entirely:
aws ssm delete-association --association-id <id>
```

There's no "pause" flag — the trick above bumps the schedule out so far that it effectively stops, while keeping the Association for re-enabling later.
