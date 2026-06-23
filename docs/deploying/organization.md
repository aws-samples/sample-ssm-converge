# Organization-wide

Three valid options for deploying SSM Converge across an AWS Organization, in order of complexity.

## Option 1 — Quick Setup (lowest effort, Console-driven)

AWS Systems Manager Quick Setup has a built-in **State Manager configuration** that targets all (or selected) accounts and OUs in your organization. It registers the document and creates the associations in every member account.

**This is the fastest path when:**

- You have AWS Organizations already set up.
- You're OK with Console-based configuration.
- You want SSM to automatically include new accounts as they join the org.

**Steps (run from the management account or a delegated administrator):**

1. Console: Systems Manager → Quick Setup → Custom Setup Type
2. Choose your custom document (`SSMConverge-Run`) from a centralised S3 bucket or pre-register it across accounts.
3. Set the schedule and target instances by tag (e.g. `Role=WebServer`).
4. Choose targets: All accounts, or specific OUs.

Quick Setup will deploy the same association to every selected account/region. Updates roll out by editing the configuration in the management account.

**Tradeoff:** less flexibility on per-account customisation. Fine for "the entire org should run this baseline."

## Option 2 — CloudFormation StackSets

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

## Option 3 — Run Command with cross-account targeting (org-wide one-shot)

For one-time bulk operations across the org without creating durable associations - say, a security patch — use a script in the management account that iterates over accounts, assumes a role into each, and runs `aws ssm send-command`:

```bash
for account in $(aws organizations list-accounts \
                 --query 'Accounts[?Status==`ACTIVE`].Id' --output text); do
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

**Pros:** full control. **Cons:** no auto-onboarding for new accounts; you maintain the loop.

## Choosing between the three

| Want | Use |
|------|-----|
| Easiest, Console-driven, auto-onboard new accounts | Quick Setup (Option 1) |
| IaC, version-controlled, granular per-OU control | StackSets (Option 2) |
| One-time bulk run, scripted, no durable association | Cross-account loop (Option 3) |

## Permissions and prerequisites

All three options require:

1. **AWS Organizations** with trusted access enabled for SSM (`aws organizations enable-aws-service-access --service-principal ssm.amazonaws.com`).
2. **The library installed** on every target instance in every member account. The recommended way is to have Quick Setup or a separate StackSet manage Distributor packaging across the org. See [Installation](installation.md).
3. **Instance roles with `AmazonSSMManagedInstanceCore`** so SSM can target them. AWS provides this as a managed policy.
4. **Optional: cross-account IAM role** named consistently (e.g. `SSMConvergeOperator`) for Option 3's `assume-role` loop.

## Multi-region

Each region is independent — register the document and create associations once per region. Quick Setup and StackSets both have built-in multi-region support; for the Option 3 loop, add a region iteration to the inner block.

```bash
for region in ap-south-1 us-east-1 eu-west-1; do
  for account in ... ; do
    # assume role + send-command --region $region
  done
done
```

## Updating across the org

| Mechanism | How updates flow |
|-----------|------------------|
| Quick Setup | Edit the configuration in the management account; Quick Setup propagates to all selected accounts/regions. |
| StackSet (Option 2) | `update-stack-set` cascades through OUs/regions according to the deployment plan. |
| Manual loop (Option 3) | Re-run the loop with the new configuration's base64. |

For all three, the underlying mechanism is the same: a new `Config` parameter value on the Association (or a fresh send-command). The library on the instance doesn't need updating unless you're upgrading the library version itself — that's handled separately via Distributor.
