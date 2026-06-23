# Examples

Ready-to-deploy configurations grouped by operating system family. All examples in the main `linux/` and `windows/` directories have been validated end-to-end on EC2.

<div class="grid cards" markdown>

- ### :material-linux: [Linux Examples](linux.md)
    NGINX, Apache, post-build OS baseline, security hardening, vendor-installer download-and-install.

- ### :material-microsoft-windows: [Windows Examples](windows.md)
    IIS web server, WSFC cluster prep, MSSQL standalone, MSSQL FCI baseline, vendor MSI/EXE download-and-install.

</div>

## Where the examples live

```
examples/
├── linux/                       # Bash configurations
│   ├── nginx-webserver.sh
│   ├── webserver-apache.sh
│   ├── os-post-build.sh
│   ├── security-hardening.sh
│   ├── install-vendor-package.sh
│   ├── ssm-doc-webserver.json
│   ├── ssm-doc-audit-only.json
│   └── reference/               # Starting points that need environment adaptation
└── windows/                     # PowerShell configurations
    ├── iis-webserver.ps1
    ├── wsfc-cluster.ps1
    ├── mssql-server.ps1
    ├── mssql-fci-baseline.ps1
    └── install-vendor-msi.ps1
```

## Running locally

=== "Linux"

    ```bash
    sudo DSC_MODE=enforce DSC_PROFILE=webserver bash examples/linux/nginx-webserver.sh
    ```

=== "Windows"

    ```powershell
    $env:DSC_MODE    = 'enforce'
    $env:DSC_PROFILE = 'iis-webserver'
    . C:\ProgramData\ssm-converge\lib.ps1
    . examples\windows\iis-webserver.ps1
    ```

    Or via the CLI:

    ```powershell
    & C:\ProgramData\ssm-converge\ssm-converge.ps1 run   examples\windows\iis-webserver.ps1
    & C:\ProgramData\ssm-converge\ssm-converge.ps1 check examples\windows\iis-webserver.ps1
    ```

## Running via SSM

```bash
# Linux
CFG_B64=$(base64 < examples/linux/nginx-webserver.sh)
aws ssm send-command \
  --document-name SSMConverge-Run \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "Mode=enforce,Profile=webserver,Config=$CFG_B64"
```

For full deployment guidance, see [Deploying › Running Configurations](../deploying/running.md).
