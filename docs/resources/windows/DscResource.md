# `DscResource` (generic wrapper)

Invoke **any** existing DSC resource (from any installed module) through SSM Converge's check/apply/report pipeline.

This is the keystone that lets you reuse your existing DSC investment without rewriting. The module stays the same; the execution model and reporting move to SSM Converge.

## Syntax

```powershell
DscResource `
    -Name       '<ResourceName>' `
    -Module     '<ModuleName>' `
    -Properties @{ <property hashtable> } `
   [-ResourceId '<stable-label>']
```

## How it works

1. **Test** - `Invoke-DscResource -Method Test` determines whether the node is already in the desired state.
2. **Set** - In `enforce` or `destroy` mode, if Test returned `InDesiredState=false`, `Invoke-DscResource -Method Set` applies the change.
3. **Re-test** - After Set, another Test confirms convergence; if still drifted, the run is recorded as `error`.
4. **Reboot tracking** - If Set returns `RebootRequired=true`, the reboot intent is recorded and `Test-RebootRequired` at the end of the configuration reports it.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-Name` | The DSC resource type name (e.g. `Cluster`, `ADUser`, `SqlSetup`). |
| `-Module` | The PowerShell module that provides the resource (`FailoverClusterDsc`, `ActiveDirectoryDsc`, `SqlServerDsc`, ...). |
| `-Properties` | A hashtable of the resource's properties as you'd write them in a native DSC configuration. Passed straight through to `Invoke-DscResource -Property`. |
| `-ResourceId` | Optional stable label used in the compliance report. If omitted, the resource picks a sensible key from `Properties.Name` / `DomainName` / `Path` / `ServiceAccountName` / `Id` / `Identity`, whichever exists first. |

## Works with any DSC module

Examples of what you can wrap:

| Module | Resources |
|--------|-----------|
| `PSDscResources` | `WindowsFeature`, `WindowsOptionalFeature`, `Script`, `Registry`, `NTFSAccessEntry`, ... |
| `FailoverClusterDsc` | `Cluster`, `ClusterNode`, `ClusterResource`, `ClusterDisk`, ... |
| `ComputerManagementDsc` | `Computer`, `TimeZone`, `ScheduledTask`, `SystemLocale`, `PowerPlan`, ... |
| `CertificateDsc` | `CertificateImport`, `PfxImport`, `CertReq`, ... |
| `ActiveDirectoryDsc` | `ADUser`, `ADGroup`, `ADServiceAccount`, `ADManagedServiceAccount`, `ADOrganizationalUnit`, ... |
| `SqlServerDsc` | `SqlSetup`, `SqlLogin`, `SqlDatabase`, `SqlRole`, `SqlAGDatabase`, `SqlRSSetup`, ... |
| `NetworkingDsc` | `FirewallRule`, `DNSServerAddress`, `DefaultGatewayAddress`, ... |
| `StorageDsc` | `Disk`, `MountImage`, `OpticalDiskDriveLetter`, ... |

Any properly-packaged class-based or MOF-based DSC resource works. The library doesn't hard-code a list.

## Examples

### Failover cluster creation

```powershell
PowerShellModule 'FailoverClusterDsc' Installed

DscResource -Name Cluster -Module FailoverClusterDsc -Properties @{
    Name            = 'SQLCluster01'
    StaticIPAddress = '10.0.1.100/24'
    Ensure          = 'Present'
}
```

### Domain join (replaces ComputerManagementDsc.Computer)

```powershell
$joinCred = Get-SsmParameterCredential 'domain/joiner'   # your helper

DscResource -Name Computer -Module ComputerManagementDsc -Properties @{
    Name       = 'SQL01-A'
    DomainName = 'corp.example.com'
    Credential = $joinCred
}
```

### gMSA provisioning (replaces the whole Create-ADServiceAccountDSC.ps1 pattern)

```powershell
DscResource -Name ADManagedServiceAccount -Module ActiveDirectoryDsc -Properties @{
    ServiceAccountName         = 'svc-sql01'
    AccountType                = 'Group'
    ManagedPasswordPrincipals  = 'SQL01-A$','SQL01-B$'
    Path                       = 'OU=Service Accounts,OU=Corp,DC=corp,DC=example,DC=com'
    Ensure                     = 'Present'
}
```

### Full SQL Server install

```powershell
PowerShellModule 'SqlServerDsc' Installed

DscResource -Name SqlSetup -Module SqlServerDsc -Properties @{
    InstanceName            = 'MSSQLSERVER'
    Features                = 'SQLENGINE,FULLTEXT'
    SourcePath              = 'C:\sql-media'
    SQLSvcAccountUsername   = 'NT Service\MSSQLSERVER'
    SQLSysAdminAccounts     = @("$env:COMPUTERNAME\SqlAdmins","BUILTIN\Administrators")
    UpdateEnabled           = 'True'
}
```

### Firewall rule

```powershell
DscResource -Name FirewallRule -Module NetworkingDsc -Properties @{
    Name      = 'AllowHTTP'
    Direction = 'Inbound'
    LocalPort = 80
    Protocol  = 'TCP'
    Action    = 'Allow'
    Ensure    = 'Present'
}
```

## Destroy mode

If the resource's `Properties` hash contains an `Ensure` key, destroy mode flips its value (`Present` <-> `Absent`). If there's no `Ensure` key, destroy mode is a no-op for that resource.

## Errors

- `Invoke-DscResource not available` - the host doesn't have `PSDesiredStateConfiguration` loadable. On Windows PowerShell 5.1 it's built-in; on PowerShell 7, install the v2 module separately.
- `DSC Test failed: Resource <Name> was not found` - the DSC module providing the resource isn't installed. Precede the `DscResource` call with [`PowerShellModule '<Module>' Installed`](PowerShellModule.md).
- `DSC Set failed: <message>` - the underlying resource raised an error. The message is surfaced verbatim; consult the DSC module's docs.
- `set did not converge` - Set completed without exception, but the subsequent Test still returns drifted. Usually indicates a configuration problem with the resource inputs.

## What you gain by wrapping DSC resources

Compared to calling `Invoke-DscResource` directly in a `runPowerShellScript` step:

1. **Modes for free.** The same configuration runs in `audit`, `enforce`, `destroy`, or `comply` mode. Your DSC resources work in all four.
2. **Compliance reporting.** Every DSC resource's Test result becomes a row in `latest.json`, with check + apply timings, the run ID, and the resource's stable ID.
3. **Handler chaining.** A DSC-resource-driven change can `-Notify` a handler the same way a primitive can.
4. **Reboot handling.** `Request-Reboot` is called automatically if the DSC Set reports `RebootRequired`.
5. **Idempotency assurance.** The post-set re-Test proves the resource actually converged; DSC doesn't always do this itself.

## What you don't get

- No MOF compilation. You pass the `-Properties` hashtable as PowerShell data, not via a `Configuration {}` block. This is the same shape you'd use with `Invoke-DscResource` directly.
- No dependency graph between DSC resources. Resources run in declaration order, top to bottom.
- No LCM. The SSM Agent is the scheduler — you don't have a local configuration manager pulling state on a cron.

## When to use a primitive vs. DscResource

- **If a primitive exists** (`LocalUser`, `LocalGroup`, `WindowsService`, `WindowsFeature`, `RegistryKey`, etc.), use it. Faster, no DSC module to install, clearer error messages.
- **If the primitive doesn't cover your case** (custom DSC resources, SQL, cluster, AD, complex registry permissions), use `DscResource`. You're almost certainly reusing a DSC resource someone else has already written.
- **If you're building something truly custom**, write a PowerShell function in a helper module and have your configuration call it. `DscResource` is only worth it when you're wrapping an existing third-party module.
