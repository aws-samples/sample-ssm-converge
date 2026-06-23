# Security

## Reporting a vulnerability

If you discover a potential security issue in this project, please notify AWS Security via email at <aws-security@amazon.com> or through the [AWS vulnerability reporting page](https://aws.amazon.com/security/vulnerability-reporting/). **Do not** create a public GitHub issue.

## Disclaimer

This project is provided as **sample code** for educational and reference purposes. It is **not** intended for direct production deployment without additional review, testing, and hardening appropriate to your environment.

## AWS services used

The library and its examples interact with the following AWS services:

- **AWS Systems Manager** — Run Command, State Manager, Distributor, Compliance API, Parameter Store
- **Amazon S3** — for downloading configuration files and uploading compliance reports (optional)
- **AWS KMS** — when configurations write to an SSE-KMS encrypted bucket
- **Amazon EC2** — the library runs on EC2 instances managed by SSM Agent
- **Amazon EventBridge** — optional reporter

No AWS credentials are stored in the library. All AWS calls inherit the EC2 instance profile of the host running the configuration.

## Known security considerations

### `execute` resource

The `execute` resource (Linux and Windows) runs arbitrary shell or PowerShell commands on the host as a configuration primitive. Configurations using `execute` should be reviewed in the same way you would review any other shell script: ensure command strings are not built from untrusted input.

### `eval` / `Invoke-Expression` usage

The library uses `eval` (bash) and `Invoke-Expression` (PowerShell) internally to dispatch resource calls. The inputs to these calls are constructed by the library itself from resource parameters in the configuration file, never from user-supplied runtime data. Review changes that touch dispatch carefully.

### `file` resource HTTPS auth

The `file` resource supports `auth_bearer`, `auth_basic`, and custom headers for downloading from authenticated HTTPS endpoints. Pass these via environment variables or AWS Secrets Manager — never hard-code them in configuration files.

### Cross-account writes

Examples that ship compliance reports to S3 expect the destination bucket to be configured with appropriate cross-account access. The library does no signing on its own; it inherits the EC2 instance role.

## Production hardening recommendations

Before using this library in production:

1. **Pin a specific library version** in your Distributor package; do not point at `latest`.
2. **Lock down the S3 bucket(s)** that hold your configurations and compliance reports — bucket policies should allow only the EC2 instance profiles you intend.
3. **Use SSE-KMS** with a customer-managed key on any audit lake bucket that holds compliance evidence.
4. **Review every `execute` resource** in your configurations as a security-sensitive item.
5. **Avoid embedding secrets in configurations** — fetch them from Parameter Store or Secrets Manager at runtime.
6. **Restrict who can `ssm:SendCommand`** the `SSMConverge-Run` document at the IAM level — anyone who can run an arbitrary configuration can execute arbitrary commands on the targeted hosts.
7. **Enable CloudTrail** on every account where the library runs; SSM Run Command invocations are logged there.
8. **Test in `audit` mode first** before flipping to `enforce` on production fleets.
9. **Pilot on a small number of instances** before org-wide rollout via State Manager Association.

## Cleanup

To remove the library from a fleet:

```bash
aws ssm send-command \
  --document-name AWS-ConfigureAWSPackage \
  --targets "..." \
  --parameters 'action=Uninstall,name=ssm-converge'
```

Compliance history under `/var/lib/ssm-converge/` (Linux) or `C:\ProgramData\ssm-converge\` (Windows) is preserved by default. Delete it explicitly if you want a clean removal:

```bash
# Linux
sudo rm -rf /var/lib/ssm-converge

# Windows
Remove-Item -Recurse -Force C:\ProgramData\ssm-converge
```

To remove the SSM Distributor package itself:

```bash
aws ssm delete-document --name ssm-converge
```
