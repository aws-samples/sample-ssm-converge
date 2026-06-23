# Deploying SSM Converge Configurations

This is the practical, copy-paste guide for getting your configuration onto instances using AWS Systems Manager. It covers:

1. [How configurations reach instances](#how-configurations-reach-instances)
2. [Create an SSM Document that runs your configuration](#create-an-ssm-document-that-runs-your-configuration)
3. [Run a document against specific instance IDs](#run-a-document-against-specific-instance-ids)
4. [Run a document against tagged instances](#run-a-document-against-tagged-instances)
5. [Run a document against a Resource Group](#run-a-document-against-a-resource-group)
6. [Schedule continuous enforcement with State Manager](#schedule-continuous-enforcement-with-state-manager)
7. [Deploy across an AWS Organization](#deploy-across-an-aws-organization)
8. [Operational checklist](#operational-checklist)

A short read; everything is `aws` CLI commands you can run today. Each section ends with what to verify.

---

## How configurations reach instances

There are three layers, each separately deployable:

1. **The library** (`lib.sh` / `lib.ps1` and resources) lives on the instance under `/opt/ssm-converge/` (Linux) or `C:\ProgramData\ssm-converge\` (Windows). Install it once via SSM Distributor (recommended) or via the `SSMConverge-Install` document.
2. **The configuration** (your `.sh` / `.ps1` file) is what declares the desired state. It can be:
   - Embedded base64 in a Run Command parameter (smallest blast radius, no S3 dependency).
   - Stored in S3 / Git and pulled at runtime.
   - Baked into a custom SSM document.
3. **The trigger** is how SSM decides to run the configuration on which instances and how often:
   - `aws ssm send-command` — one-shot Run Command.
   - State Manager Association — scheduled, continuous enforcement.
   - EventBridge Scheduler / Lambda — for custom triggers.

The deployment guide assumes the library is already installed (see [README - Installation](../README.md#installation)). What follows is configuration delivery.

---

## Create an SSM Document that runs your configuration

You have two patterns. Pick the one that fits your guardrails.

### Pattern A - Generic runner with config-as-parameter (recommended)

Use the bundled `SSMConverge-Run` document (Linux today; a Windows-native runner is on the v0.2 roadmap). The configuration body is base64-encoded and passed as a parameter, so the document itself never changes - only the parameter value does.

**Register the document once per region:**

```bash
aws ssm create-document \
  --name SSMConverge-Run \
  --document-type Command \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Run.json \
  --region <region>
```

Update on subsequent versions:

```bash
aws ssm update-document \
  --name SSMConverge-Run \
  --document-version '$LATEST' \
  --document-format JSON \
  --content file://ssm-documents/SSMConverge-Run.json \
  --region <region>

aws ssm update-document-default-version \
  --name SSMConverge-Run \
  --document-version 2 \
  --region <region>
```

**Parameters:** `Mode` (enforce / audit / destroy), `Profile` (label for the report), `Report` (summary / full), `Config` (base64 of your configuration), `InstallPath` (default `/opt/ssm-converge`).

### Pattern B - One document per configuration

When the same configuration runs unchanged across many invocations, bake it into the document itself. Useful when the configuration is a release artifact reviewed and approved once. The downside: any configuration change requires a new document version.

```bash
# Create a small wrapper document that invokes lib.sh + your inline configuration.
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
  --content file:///tmp/MyApp-Baseline.json \
  --region <region>
```

### Verify

```bash
aws ssm describe-document --name SSMConverge-Run --region <region> \
  --query '{Name:Document.Name,Status:Document.Status,Version:Document.LatestVersion}'
```

`Status` should be `Active`.

---

## Run a document against specific instance IDs

When you have a known set of instances - a single host, a fleet of three, an explicit allow-list.

```bash
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)

aws ssm send-command \
  --document-name SSMConverge-Run \
  --instance-ids i-0a1b2c3d4e5f6g7h8 i-0123456789abcdef0 \
  --parameters "Mode=enforce,Profile=webserver,Report=summary,Config=$CFG_B64" \
  --comment "nginx baseline 2026-05-13" \
  --region <region>
```

Capture the command ID and follow it:

```bash
CMD_ID=$(aws ssm send-command --document-name SSMConverge-Run \
  --instance-ids i-0a1b2c3d4e5f6g7h8 \
  --parameters "Mode=enforce,Config=$CFG_B64" \
  --query 'Command.CommandId' --output text \
  --region <region>)

# Poll status (Pending, InProgress, Success, Failed, ...)
aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id i-0a1b2c3d4e5f6g7h8 \
  --region <region> \
  --query '[Status,StandardOutputContent,StandardErrorContent]' \
  --output text
```

### Verify

The configuration should report `compliant` for every resource on the second pass. A run that's still showing `changed=true` after a second invocation is a sign of a non-idempotent resource - file a bug.

---

## Run a document against tagged instances

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
  --comment "rolling out nginx baseline" \
  --region <region>
```

Notes:

- `Key=tag:<TagName>,Values=<TagValue>` - both the key prefix `tag:` and exact-match values are required.
- Multiple `--targets` entries are **AND-ed** together. The example above hits instances that are *both* `Role=WebServer` and `Environment=production`.
- `--max-concurrency` caps how many instances run in parallel (number or percentage). Without it, SSM uses 50.
- `--max-errors` stops the rollout if too many instances fail. `5%` means: stop once 5% of targets have failed.

### Verify

```bash
# How many instances did it match? How many succeeded so far?
aws ssm list-command-invocations \
  --command-id "$CMD_ID" \
  --query 'CommandInvocations[].[InstanceId,Status]' \
  --output table \
  --region <region>
```

Expect `Success` for each row. `Failed` rows: pull `StandardErrorContent` for the first one and read the failure snippet (the `execute` resource in v0.1.2 surfaces the most-useful line of stderr alongside the exit code).

### Bulk audit before bulk enforcement

Always audit first against the same target set, then enforce only when the audit looks right:

```bash
# 1) Audit-only pass
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=audit,Profile=webserver,Config=$CFG_B64" \
  --region <region>

# 2) Inspect the per-instance reports, look for `non_compliant` totals
# 3) Enforce
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64" \
  --region <region>
```

---

## Run a document against a Resource Group

A Resource Group is a saved query (tag-based or CFN-stack-based). Useful when the targeting logic is non-trivial or shared across workflows.

```bash
# Create a Resource Group once.
aws resource-groups create-group \
  --name webservers-prod \
  --resource-query '{
    "Type": "TAG_FILTERS_1_0",
    "Query": "{\"ResourceTypeFilters\":[\"AWS::EC2::Instance\"],\"TagFilters\":[{\"Key\":\"Role\",\"Values\":[\"WebServer\"]},{\"Key\":\"Environment\",\"Values\":[\"production\"]}]}"
  }' \
  --region <region>

# Send the command targeting the group.
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=resource-groups:Name,Values=webservers-prod" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64" \
  --region <region>
```

`Key=resource-groups:Name,Values=<group-name>` is the magic incantation. It also accepts `Key=resource-groups:ResourceTypeFilters,Values=AWS::EC2::Instance`.

### Verify

`aws resource-groups list-group-resources --group-name webservers-prod` shows what's in scope before you send the command.

---

## Schedule continuous enforcement with State Manager

Run Command is one-shot. State Manager runs the same command on a schedule and is the right tool for "always be enforcing" or "audit every 30 minutes."

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
  --compliance-severity HIGH \
  --region <region>
```

Common patterns:

- **Audit every 15 minutes** to feed compliance dashboards: `Mode=audit`, `rate(15 minutes)`.
- **Enforce nightly** for slow-changing baselines: `Mode=enforce`, `cron(0 4 * * ? *)`.
- **Enforce on launch** by tagging new instances with the appropriate role - the next association run picks them up automatically.

The `--compliance-severity` flag lets non-compliant runs surface in the SSM Compliance dashboard with a severity tag.

### Verify

```bash
aws ssm describe-association \
  --association-id <id-from-create-association> \
  --region <region>

aws ssm list-association-executions \
  --association-id <id> \
  --region <region>
```

---

## Deploy across an AWS Organization

Three valid options, in order of complexity.

### Option 1 - Quick Setup (lowest effort, Console-driven)

AWS Systems Manager Quick Setup has a built-in **State Manager configuration** that targets all (or selected) accounts and OUs in your organization. It registers the document and creates the associations in every member account.

This is the fastest path when:
- You have AWS Organizations already set up.
- You're OK with Console-based configuration.
- You want SSM to automatically include new accounts as they join the org.

Run it from the **management account** (or a delegated administrator). Steps:

1. Console: Systems Manager > Quick Setup > Custom Setup Type
2. Choose your custom document (`SSMConverge-Run`) from a centralised S3 bucket or pre-register it across accounts.
3. Set the schedule and target instances by tag (e.g. `Role=WebServer`).
4. Choose targets: All accounts, or specific OUs.

Quick Setup will deploy the same association to every selected account/region. Updates roll out by editing the configuration in the management account.

Tradeoff: less flexibility on per-account customisation. Fine for "the entire org should run this baseline."

### Option 2 - CloudFormation StackSets

When you want IaC-managed deployment with full control over per-OU and per-region targeting:

```yaml
# stackset-template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: SSM Converge - register Run document and create State Manager association
Parameters:
  ConfigBase64: { Type: String }
  Schedule:     { Type: String, Default: 'rate(30 minutes)' }
  TargetTagKey: { Type: String, Default: 'Role' }
  TargetTagVal: { Type: String, Default: 'WebServer' }

Resources:
  RunDocument:
    Type: AWS::SSM::Document
    Properties:
      Name: SSMConverge-Run
      DocumentType: Command
      Content:
        # Inline the SSMConverge-Run.json content here, or use a stored URL.
        Fn::Transform:
          Name: AWS::Include
          Parameters: { Location: 's3://my-bucket/SSMConverge-Run.json' }

  Baseline:
    Type: AWS::SSM::Association
    Properties:
      AssociationName: webserver-baseline
      Name: !Ref RunDocument
      Targets:
        - Key: !Sub 'tag:${TargetTagKey}'
          Values: [!Ref TargetTagVal]
      ScheduleExpression: !Ref Schedule
      Parameters:
        Mode:    [enforce]
        Profile: [webserver]
        Config:  [!Ref ConfigBase64]
      MaxConcurrency: '20%'
      MaxErrors:      '5%'
      ComplianceSeverity: HIGH
```

Deploy as a StackSet that targets your Organization:

```bash
aws cloudformation create-stack-set \
  --stack-set-name ssm-converge-baseline \
  --template-body file://stackset-template.yaml \
  --capabilities CAPABILITY_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false

aws cloudformation create-stack-instances \
  --stack-set-name ssm-converge-baseline \
  --deployment-targets OrganizationalUnitIds=ou-abcd-1234abcd \
  --regions ap-south-1 us-east-1 \
  --parameter-overrides "ParameterKey=ConfigBase64,ParameterValue=$(base64 < webserver.sh)"
```

`SERVICE_MANAGED` permission model + `Enabled=true` auto-deployment means new accounts joining the OU get the stack automatically.

### Option 3 - Run Command with cross-account targeting (org-wide one-shot)

For one-time bulk operations across the org without creating durable associations - say, a security patch - use Run Command's CloudWatch / EventBridge integration plus IAM cross-account roles, or use **AWS-RunCommand** through Quick Setup's "Run command on multiple accounts and Regions" feature.

The simpler form: a script in the management account that iterates over accounts, assumes a role into each, and runs `aws ssm send-command`:

```bash
for account in $(aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].Id' --output text); do
  creds=$(aws sts assume-role \
    --role-arn arn:aws:iam::${account}:role/SSMConvergeOperator \
    --role-session-name converge-rollout \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)
  read AK SK ST <<< "$creds"

  AWS_ACCESS_KEY_ID=$AK AWS_SECRET_ACCESS_KEY=$SK AWS_SESSION_TOKEN=$ST \
    aws ssm send-command \
      --document-name SSMConverge-Run \
      --targets "Key=tag:Role,Values=WebServer" \
      --parameters "Mode=audit,Config=$CFG_B64" \
      --region ap-south-1
done
```

Pros: full control. Cons: no auto-onboarding for new accounts; you maintain the loop.

### Choosing between the three

| Want | Use |
|------|-----|
| Easiest, Console-driven, auto-onboard new accounts | Quick Setup (Option 1) |
| IaC, version-controlled, granular per-OU control | StackSets (Option 2) |
| One-time bulk run, scripted, no durable association | Cross-account loop (Option 3) |

---

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
- [ ] State Manager association in place if continuous enforcement is desired.

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

The configuration's `compliance` report includes a per-resource `error: <message>` field. The `execute` resource in v0.1.2 surfaces the most-useful line of failure output alongside the exit code, so most issues are diagnosable from the report alone without SSH.

For deeper debugging, the debug log on the instance:

```
Linux:   /var/log/ssm-converge.log
Windows: C:\ProgramData\ssm-converge\ssm-converge.log
```

contains the full stderr/stdout of every failed `execute` (first 2KB), plus the timestamped CHECK / APPLY / NOTIFY trail.

---

## Reference

- [`ssm-documents/SSMConverge-Run.json`](../ssm-documents/SSMConverge-Run.json) - the bundled Linux runner document.
- [`ssm-documents/SSMConverge-Install.json`](../ssm-documents/SSMConverge-Install.json) - one-shot install document (use Distributor for production).
- [README - Installation](../README.md#installation) - how the library gets onto the instance in the first place.
- [examples/](../examples/) - ready-to-deploy configurations.
- [docs/resources/README.md](resources/README.md) - the resource manual.
