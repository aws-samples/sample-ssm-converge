# `Execute`

Run an arbitrary command (PowerShell or external EXE), idempotently. Idempotency comes from a guard (`-Creates`, `-OnlyIf`, or `-NotIf`) that the resource consults before executing.

This is the escape hatch for installers (MSI / EXE), one-shot bootstraps, and operations that don't fit a more specific resource. Keep configurations as declarative as possible; reach for `Execute` when there's no purpose-built resource.

## Syntax

```powershell
Execute '<Name>' [-State Run] -Command '<command>' `
                 [-Creates <path>] [-OnlyIf <expr>] [-NotIf <expr>] `
                 [-Cwd <path>] [-EnvVars @{...}] [-TimeoutSec N] `
                 [-Interpreter powershell|pwsh|cmd] [-Notify <handler>]
```

The `Name` is a logical identifier - it appears in the report and in log output but doesn't have to match anything on disk.

## Guards (idempotency)

At least one is recommended. If multiple are supplied, all must agree the command needs to run.

| Parameter | Skip when |
|-----------|-----------|
| `-Creates` | The path exists. Most natural for "install something that creates a file." |
| `-OnlyIf`  | The PowerShell expression is `$false` or returns non-zero exit code. Run only if it succeeds. |
| `-NotIf`   | The PowerShell expression is `$true` or returns exit 0. Skip if it succeeds. |

Guards run in this order: `-Creates`, then `-NotIf`, then `-OnlyIf`. The first one that says "skip" wins.

## Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Command` | - | The command to run. **Required.** |
| `-Cwd` | - | Working directory. |
| `-EnvVars` | - | Hashtable of environment variables. |
| `-TimeoutSec` | 600 | Wall-clock timeout in seconds. |
| `-Interpreter` | `powershell` | One of `powershell`, `pwsh`, or `cmd`. Picks the shell that runs `-Command`. |
| `-Notify` | - | Handler name to fire when the command runs. |

## Examples

### Install an MSI with idempotency via `-Creates`

```powershell
File 'C:\temp\agent.msi' Present `
     -Source   'https://vendor.com/agent.msi' `
     -Checksum 'sha256:abc123...'

Execute 'install-vendor-agent' `
        -Command     'msiexec /i C:\temp\agent.msi /qn /norestart' `
        -Creates     'C:\Program Files\Vendor\agent.exe' `
        -Interpreter 'cmd'
```

The first run downloads and installs. The second run skips the `Execute` because the binary already exists.

### Install an EXE installer with silent flags

```powershell
File 'C:\temp\setup.exe' Present `
     -Source   'https://vendor.com/setup.exe' `
     -Checksum 'sha256:abc123...'

Execute 'install-vendor-app' `
        -Command     'C:\temp\setup.exe /S /D=C:\Program Files\Vendor' `
        -NotIf       '(Get-Package -Name "Vendor App" -ErrorAction SilentlyContinue) -ne $null' `
        -Interpreter 'cmd'
```

### Run a PowerShell script unless a sentinel says it's done

```powershell
Execute 'first-boot-init' `
        -Command 'C:\scripts\Initialize-Server.ps1; New-Item -ItemType File -Path C:\ProgramData\app\.initialized -Force' `
        -NotIf   'Test-Path C:\ProgramData\app\.initialized'
```

### Run with a working directory and env vars

```powershell
Execute 'rebuild-cache' `
        -Command 'pwsh ./bin/Rebuild-Cache.ps1' `
        -Cwd     'C:\opt\myapp' `
        -EnvVars @{ CACHE_DIR = 'C:\cache\myapp'; WORKERS = '4' } `
        -NotIf   'Test-Path C:\cache\myapp\.fresh'
```

### Time-bounded operation

```powershell
Execute 'long-import' `
        -Command    'C:\opt\app\bin\Import.ps1' `
        -TimeoutSec 300 `
        -Creates    'C:\ProgramData\app\import-complete'
```

## Reporting

| Outcome | Status | `changed` |
|---------|--------|-----------|
| Guard says skip | `compliant` | `false` |
| Command ran, exit 0 | `compliant` | `true` |
| Command ran, non-zero exit | `error` | `true` |
| Audit mode, command would have run | `non_compliant` | `false` |
| Destroy mode | `compliant` | `false` (skipped) |

Failed-command stdout/stderr are captured to the debug log (first 2000 chars) so you can diagnose without re-running.

## Destroy mode

`Execute` is **skipped** in destroy mode. Most installer commands have no one-line undo; if you need to uninstall something, declare a separate `Execute` for the uninstall (or use `Package <id> Uninstalled` when the package manager is involved).

## Audit mode

In audit mode, `Execute` reports `non_compliant: would run` when its guard says the command would execute. It never actually runs.

## Pitfalls

- **Always pair with a guard.** A guardless `Execute` runs every pass, which defeats the point of idempotent configuration management.
- **`-OnlyIf` and `-NotIf` are evaluated via `Invoke-Expression`.** Treat them as code, not data. Don't interpolate untrusted input.
- **Pick the right `-Interpreter`.** Use `cmd` for `msiexec` and most native installers (avoids PowerShell's argument parsing). Use `powershell` (default) for cmdlet pipelines or .ps1 scripts.
- **MSI and EXE installers vary in silent flags.** Common patterns:
  - MSI: `msiexec /i <file>.msi /qn /norestart` (use `-Interpreter cmd`)
  - InnoSetup: `setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
  - NSIS: `setup.exe /S`
  - WiX: same as MSI

## Notes

- Stdout and stderr are captured but not streamed. Failed-command output is logged to the debug log.
- The default `-Interpreter powershell` runs through `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command <script>`.
- `cmd` interpreter does not honour PowerShell's argument-quoting rules - use it for native commands.
- See also [`File`](File.md) for downloading the artifact you want to install, [`Package`](Package.md) for winget/Chocolatey-managed packages, [`WindowsService`](WindowsService.md) for managing services after install, and [`DscResource`](DscResource.md) for wrapping any installed DSC resource.
- The Linux equivalent is `execute` - same semantics.
