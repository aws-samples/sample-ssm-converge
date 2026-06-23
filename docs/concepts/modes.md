# Modes

A single configuration supports four execution modes, selected via the `DSC_MODE` environment variable (or, for ad-hoc runs, the `Mode` parameter on the `SSMConverge-Run` document).

| Mode | Behaviour | Exit code |
|------|-----------|-----------|
| `enforce` *(default)* | Check state, fix drift, write report. The standard "make it so" mode. | 0 if all converged, 1 if any errors |
| `audit` | Check state only, **never change anything**. Drift is logged as `non_compliant`. | 0 if all compliant, 2 if drift, 1 if errors |
| `destroy` | Flip desired state (`present` → `absent`, `running` → `stopped`) and converge. The "tear it down" mode. | 0 on success |
| `comply` | Audit mode + full per-resource detail in the report. Optimised for compliance evidence. | Same as `audit` |

## When to use each

```bash
# Daily / on-demand reconciliation - the most common path.
DSC_MODE=enforce ssm-converge run webserver.sh

# Pre-deployment dry run, or scheduled drift detection.
DSC_MODE=audit   ssm-converge run webserver.sh

# Tear it down (e.g. before reimaging or decommissioning).
DSC_MODE=destroy ssm-converge run webserver.sh

# Compliance evidence collection (audit + full detail).
ssm-converge comply webserver.sh
```

## Audit-then-enforce rollout pattern

The recommended way to roll out a new configuration across a fleet:

1. **Audit** against the target tag set. Look at the per-instance reports. Confirm the count of `non_compliant` resources matches what you expect to change.
2. **Enforce** with `--max-concurrency 10-20%` and `--max-errors 5%` - SSM's safe rollout knobs.
3. **Re-audit** after enforcement. Every resource should report `compliant, changed=false`. If anything is still changing on the second pass, you've found a non-idempotent resource — file a bug.

```bash
# 1) Audit
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=audit,Config=$CFG_B64"

# 2) Inspect reports, then enforce
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Config=$CFG_B64" \
  --max-concurrency '20%' --max-errors '5%'

# 3) Re-audit; expect zero drift
```

## Destroy mode - what gets flipped

Most resources have a clean inverse:

| Declared state | Destroy-mode effective state |
|----------------|------------------------------|
| `present`, `installed`, `mounted` | `absent` |
| `absent`, `uninstalled`, `removed` | `present` |
| `running` | `stopped` |
| `enabled` | `disabled` |

A few have **no safe inverse** and are skipped in destroy mode with an OK status:

- `sysctl` — kernel parameters can't be "unset" without rebooting.
- `timezone`, `locale` — no notion of "the previous value."
- `execute` / `Execute` — installer commands rarely have a one-line undo. Wire up a separate `execute` for the uninstall path when you need it.

!!! tip "When destroy mode is useful"
    - Wiping a previously-applied configuration before re-imaging an instance.
    - Cleaning up after a failed rollout: `DSC_MODE=destroy` removes everything the configuration declared.
    - Building tear-down logic for ephemeral environments where the same configuration runs forward (`enforce`) on creation and backward (`destroy`) on teardown.

## Mode is a runtime decision

The configuration file itself never references the mode. That's deliberate — the same file is the artifact, and only the run-time invocation changes behaviour. This is what makes "enforce on Monday, audit on Tuesday, destroy at decommission" trivial.
