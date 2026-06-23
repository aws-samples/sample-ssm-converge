# Running Configurations

Trigger a configuration through SSM Run Command. Three targeting modes: by instance ID, by tag, by Resource Group.

## Prerequisites

- The library is installed on the target instances ([Installation](installation.md)).
- The `SSMConverge-Run` document is registered (or your own custom document).

## Create the runner document

You have two patterns. Pick the one that fits your guardrails.

### Pattern A — Generic runner with config-as-parameter (recommended)

Use the bundled `SSMConverge-Run` document. The configuration body is base64-encoded and passed as a parameter, so the document itself never changes — only the parameter value does.

```bash
# Register the document once per region.
aws ssm create-document \
  --name SSMConverge-Run \
  --document-type Command \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Run.json

# Update on subsequent versions:
aws ssm update-document \
  --name SSMConverge-Run \
  --document-version '$LATEST' \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Run.json

aws ssm update-document-default-version \
  --name SSMConverge-Run \
  --document-version 2
```

**Parameters:**

- `Mode` — `enforce` / `audit` / `destroy` (default `enforce`)
- `Profile` — label that appears in the report (default `default`)
- `Report` — `summary` / `full` (default `summary`)
- `Config` — base64 of your configuration
- `InstallPath` — default `/opt/ssm-converge`

### Pattern B — One document per configuration

When the same configuration runs unchanged across many invocations, bake it into the document itself. Useful when the configuration is a release artifact reviewed and approved once. The downside: any configuration change requires a new document version.

```bash
cat > /tmp/MyApp-Baseline.json <<'EOF'
{
  "schemaVersion": "2.2",
  "description": "Apply the MyApp baseline using SSM Converge.",
  "parameters": {
    "Mode": { "type": "String", "default": "enforce", "allowedValues": ["enforce","audit","destroy"] }
  },
  "mainSteps": [{
    "action": "aws:runShellScript",
    "name": "ApplyBaseline",
    "inputs": {
      "runCommand": [
        "#!/bin/bash",
        "set -e",
        "export DSC_MODE='{{ Mode }}'",
        "export DSC_PROFILE='myapp-baseline'",
        "source /opt/ssm-converge/lib.sh",
        "package 'nginx' installed",
        "service 'nginx' running enabled",
        "report_compliance"
      ]
    }
  }]
}
EOF

aws ssm create-document \
  --name MyApp-Baseline \
  --document-type Command \
  --content file:///tmp/MyApp-Baseline.json
```

### Verify

```bash
aws ssm describe-document --name SSMConverge-Run \
  --query '{Name:Document.Name,Status:Document.Status,Version:Document.LatestVersion}'
```

`Status` should be `Active`.

## Target by specific instance IDs

When you have a known set of instances - a single host, a fleet of three, an explicit allow-list.

```bash
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)

aws ssm send-command \
  --document-name SSMConverge-Run \
  --instance-ids i-0a1b2c3d4e5f6g7h8 i-0123456789abcdef0 \
  --parameters "Mode=enforce,Profile=webserver,Report=summary,Config=$CFG_B64" \
  --comment "nginx baseline 2026-05-13"
```

Capture the command ID and follow it:

```bash
CMD_ID=$(aws ssm send-command --document-name SSMConverge-Run \
  --instance-ids i-0a1b2c3d4e5f6g7h8 \
  --parameters "Mode=enforce,Config=$CFG_B64" \
  --query 'Command.CommandId' --output text)

# Poll status (Pending, InProgress, Success, Failed, ...)
aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id i-0a1b2c3d4e5f6g7h8 \
  --query '[Status,StandardOutputContent,StandardErrorContent]' \
  --output text
```

### What "good" looks like

The configuration should report `compliant` for every resource on the second pass. A run that's still showing `changed=true` after a second invocation is a sign of a non-idempotent resource — file a bug.

## Target by tags

The standard pattern for production. Tag your instances by role and let SSM pick them up.

```bash
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)

aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
            "Key=tag:Environment,Values=production" \
  --parameters "Mode=enforce,Profile=webserver,Report=summary,Config=$CFG_B64" \
  --max-concurrency "20%" \
  --max-errors "5%" \
  --comment "rolling out nginx baseline"
```

Notes:

- `Key=tag:<TagName>,Values=<TagValue>` — both the key prefix `tag:` and exact-match values are required.
- Multiple `--targets` entries are **AND-ed** together. The example above hits instances that are *both* `Role=WebServer` and `Environment=production`.
- `--max-concurrency` caps how many instances run in parallel (number or percentage). Without it, SSM uses 50.
- `--max-errors` stops the rollout if too many instances fail. `5%` means: stop once 5% of targets have failed.

### Verify

```bash
# How many instances did it match? How many succeeded so far?
aws ssm list-command-invocations \
  --command-id "$CMD_ID" \
  --query 'CommandInvocations[].[InstanceId,Status]' \
  --output table
```

Expect `Success` for each row. `Failed` rows: pull `StandardErrorContent` for the first one and read the failure snippet (the [`execute`](../resources/linux/execute.md) resource surfaces the most-useful line of stderr alongside the exit code).

### Audit-then-enforce

Always audit first against the same target set, then enforce only when the audit looks right:

```bash
# 1) Audit-only pass
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=audit,Profile=webserver,Config=$CFG_B64"

# 2) Inspect the per-instance reports, look for `non_compliant` totals
# 3) Enforce
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

## Target by Resource Group

A Resource Group is a saved query (tag-based or CFN-stack-based). Useful when the targeting logic is non-trivial or shared across workflows.

```bash
# Create a Resource Group once.
aws resource-groups create-group \
  --name webservers-prod \
  --resource-query '{
    "Type": "TAG_FILTERS_1_0",
    "Query": "{\"ResourceTypeFilters\":[\"AWS::EC2::Instance\"],\"TagFilters\":[{\"Key\":\"Role\",\"Values\":[\"WebServer\"]},{\"Key\":\"Environment\",\"Values\":[\"production\"]}]}"
  }'

# Send the command targeting the group.
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=resource-groups:Name,Values=webservers-prod" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

`Key=resource-groups:Name,Values=<group-name>` is the magic incantation. Resource Groups also accept `Key=resource-groups:ResourceTypeFilters,Values=AWS::EC2::Instance`.

### Verify

`aws resource-groups list-group-resources --group-name webservers-prod` shows what's in scope before you send the command.

## Operational checklist

### Pre-flight

- [ ] Library installed on every target. Run `command -v ssm-converge` or check `/opt/ssm-converge/lib.sh` exists.
- [ ] Instance role has `AmazonSSMManagedInstanceCore`, plus any extra permissions the configuration needs (e.g. S3 read for `file source 's3://...'`).
- [ ] Configuration was tested locally with `bash -n my-config.sh` (syntax check) and `DSC_MODE=audit bash my-config.sh` on a representative test instance.
- [ ] Document registered in every region you target.
- [ ] CloudWatch Logs receiver configured if you want command output centralised (`--cloud-watch-output-config`).

### Rollout

- [ ] Audit-only pass first. Confirm 0 errors and the expected number of `non_compliant` resources before enforcing.
- [ ] Enforce with `--max-concurrency 10-20%` and `--max-errors 5%` for the first deployment of a configuration.
- [ ] Watch the first 5-10 instances complete before letting the rollout proceed at full speed.

### Post-flight

- [ ] Re-run in audit mode. Every resource should be `compliant, changed=false`. Anything still changing on the second pass is a non-idempotent resource.
- [ ] Compliance reports flowing to wherever you ship them (S3 lake / SSM Compliance API / your SIEM).
- [ ] State Manager association in place if continuous enforcement is desired - see [Scheduled Enforcement](scheduling.md).

### Triage when something fails

```bash
# Get all failed invocations from the last command.
aws ssm list-command-invocations \
  --command-id "$CMD_ID" \
  --filters "key=Status,value=Failed" \
  --query 'CommandInvocations[].InstanceId' --output text

# Pull the full error output from one of them.
aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id <failed-instance-id> \
  --query '[Status,StandardErrorContent]' --output text
```

The configuration's compliance report includes a per-resource `error: <message>` field. The `execute` resource surfaces the most-useful line of failure output alongside the exit code, so most issues are diagnosable from the report alone without SSH.

For deeper debugging, the debug log on the instance contains the full stderr/stdout of every failed `execute` (first 2KB), plus the timestamped CHECK / APPLY / NOTIFY trail. See [Concepts › Compliance Reporting](../concepts/reporting.md#debug-log).
