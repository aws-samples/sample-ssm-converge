# Windows Examples

| File | Description | EC2 validation |
|------|-------------|----------------|
| [`iis-webserver.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/iis-webserver.ps1) | IIS from bare Windows — Web-Server role + sub-features, site directory, index.html, service state, registry hardening | **Full enforce + audit + idempotent re-run.** GET / returns HTTP 200. Uses pure primitives, no DscResource. |
| [`wsfc-cluster.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/wsfc-cluster.ps1) | Failover Cluster node prep + cluster create | Prerequisites fully enforced: Failover-Clustering feature, RSAT-Clustering, FailoverClusterDsc module v2.2.0, host entries, ClusterAdmins local group. Cluster creation itself requires two nodes + AD domain (not attempted on single-node test). |
| [`mssql-server.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/mssql-server.ps1) | Standalone SQL Server via `DscResource -Module SqlServerDsc` | Audit-only: correctly catalogs missing prerequisites (SqlServerDsc module, data directories, services, registry tuning). Full install requires installer media staged in S3 (outside scope of the sample). |
| [`mssql-fci-baseline.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/mssql-fci-baseline.ps1) | MSSQL FCI node baseline demonstrating the pattern for porting existing DSC configurations (features, modules, host entries, local groups, cert import, domain join, gMSA, cluster create, node join, SQL install) | Documentary / audit pattern - full enforcement needs a real FCI environment. Shows the primitive + DscResource composition. |
| [`install-vendor-msi.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/install-vendor-msi.ps1) | Download + unattended install pattern for Windows: public HTTPS, authenticated HTTPS (bearer / basic / custom headers), and S3 sources, paired with `Execute -Creates` / `-NotIf`. Includes MSI (CloudWatch Agent), authenticated MSI (Artifactory-style), S3 MSI, and InnoSetup/NSIS-style EXE installers. | enforce + audit, idempotent re-run verified on Windows Server 2022 |

## IIS example anatomy

A typical Windows configuration looks like this. The pattern: features, directories, files, registry, service, host entries, report.

```powershell
. C:\ProgramData\ssm-converge\lib.ps1

$SiteName = 'example.com'
$SiteRoot = "C:\inetpub\$SiteName"

# 1. IIS role + common sub-features
WindowsFeature 'Web-Server'           Installed -IncludeManagementTools
WindowsFeature 'Web-Common-Http'      Installed
WindowsFeature 'Web-Default-Doc'      Installed
WindowsFeature 'Web-Static-Content'   Installed

# 2. Directory layout
Directory $SiteRoot Present

# 3. Default landing page
File-Content -Path (Join-Path $SiteRoot 'index.html') -Content @"
<!DOCTYPE html>
<html><body><h1>It works - $SiteName</h1></body></html>
"@

# 4. Security hardening via registry
RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
    -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord

# 5. Service state
WindowsService 'W3SVC' Running -StartupType Automatic

# 6. Host entry
HostEntry '127.0.0.1' Present -Hostname "$SiteName local.$SiteName"

# 7. Report
Report-Compliance

if (Test-RebootRequired) {
    Write-Host 'Reboot required (usually from Web-Server feature install). Reboot and re-run.'
}
```

Full file: [`examples/windows/iis-webserver.ps1`](https://github.com/awslabs/ssm-converge/blob/main/examples/windows/iis-webserver.ps1).

## DscResource bridge — keeping existing DSC investment

The `wsfc-cluster.ps1` and `mssql-server.ps1` examples demonstrate the `DscResource` wrapper pattern. Any installed PSDSC module (FailoverClusterDsc, SqlServerDsc, ActiveDirectoryDsc, ComputerManagementDsc, CertificateDsc, NetworkingDsc, ...) can be invoked through SSM Converge's check / apply / report pipeline:

```powershell
# Install the module first (use SSM Converge's PowerShellModule resource).
PowerShellModule 'FailoverClusterDsc' Installed -Version '2.2.0'

# Then invoke any of its resources through the wrapper.
DscResource 'CreateMyCluster' `
    -Module    FailoverClusterDsc `
    -Resource  Cluster `
    -Properties @{
        Name                          = 'MyCluster'
        StaticIPAddress               = '10.0.1.10/24'
        DomainAdministratorCredential = $cred
    }
```

The result lands in the SSM Converge compliance report just like a primitive resource — same `compliant` / `non_compliant` / `error` states, same JSON schema. See [`DscResource`](../resources/windows/DscResource.md).

## Download-and-install pattern

```powershell
# Download CloudWatch Agent MSI from public HTTPS with checksum verification.
File 'C:\temp\amazon-cloudwatch-agent.msi' Present `
     -Source   'https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi' `
     -Checksum 'sha256:...'

# Install via msiexec with idempotency guard.
Execute 'install-cloudwatch-agent' `
        -Command     'msiexec /i C:\temp\amazon-cloudwatch-agent.msi /qn /norestart' `
        -Creates     'C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1' `
        -Interpreter 'cmd'
```

Use `-Interpreter cmd` for native installers like `msiexec` to avoid PowerShell's argument-quoting rules.

For authenticated downloads (bearer token, basic auth, custom headers), see [`File`](../resources/windows/File.md). For non-MSI installers (InnoSetup, NSIS, InstallShield), see [`Execute`](../resources/windows/Execute.md).
