# Deploying

Practical, copy-paste guides for getting configurations onto instances using AWS Systems Manager.

<div class="grid cards" markdown>

- ### :material-package-down: [Installation](installation.md)
    Get the library onto instances. Distributor (recommended), inline `SSMConverge-Install` document, or bake into AMI.

- ### :material-rocket-launch-outline: [Running Configurations](running.md)
    Create the runner document and trigger it: by instance ID, by tag, by Resource Group. Includes safe-rollout knobs.

- ### :material-clock-outline: [Scheduled Enforcement](scheduling.md)
    State Manager Associations for continuous drift detection and auto-remediation.

- ### :material-source-branch: [Organization-wide](organization.md)
    Deploy across an AWS Organization with Quick Setup, CloudFormation StackSets, or a cross-account loop.

</div>

## How configurations reach instances

Three layers, each separately deployable:

1. **The library** lives on the instance under `/opt/ssm-converge/` (Linux) or `C:\ProgramData\ssm-converge\` (Windows). Install it once via SSM Distributor (recommended) or via the `SSMConverge-Install` document.
2. **The configuration** (your `.sh` / `.ps1` file) is what declares the desired state. It can be embedded base64 in a Run Command parameter, stored in S3 / Git and pulled at runtime, or baked into a custom SSM document.
3. **The trigger** is how SSM decides to run the configuration on which instances and how often: `aws ssm send-command` (one-shot), State Manager Association (scheduled), or EventBridge Scheduler / Lambda for custom triggers.

The pages in this section walk through each layer.
