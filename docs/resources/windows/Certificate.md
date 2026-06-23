# `Certificate`

Import or remove certificates in a Windows certificate store. Handles both `.cer` / `.crt` public certificates and password-protected `.pfx` bundles.

Replaces the ad-hoc `Import-Certificate` / `Import-PfxCertificate` you'd otherwise put in a pre-config script, and covers the same ground as `CertificateDsc.CertificateImport` / `CertificateDsc.PfxImport`.

## Syntax

```powershell
# Import from file:
Certificate -Path '<file>' -Store '<store>' -State Present [-Password <secureString>] [-Exportable]

# Remove by thumbprint:
Certificate -Thumbprint '<thumbprint>' -Store '<store>' -State Absent
```

## State

| State | Effect |
|-------|--------|
| `Present` | Import if the certificate with this thumbprint isn't already in the store. |
| `Absent` | Remove the certificate with this thumbprint from the store. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | - | Path to a `.cer`, `.crt`, or `.pfx` file. Required for `Present`. |
| `-Thumbprint` | *(derived from file)* | SHA-1 thumbprint. Required for `Absent` when `-Path` isn't given. |
| `-Store` | *(required)* | PowerShell cert store path, e.g. `Cert:\LocalMachine\My`, `Cert:\LocalMachine\Root`. |
| `-Password` | - | SecureString for PFX bundles. Required for PFX. |
| `-Exportable` | *off* | For PFX imports, marks the private key as exportable. |

## Common stores

| Store | Purpose |
|-------|---------|
| `Cert:\LocalMachine\Root` | Trusted root CAs |
| `Cert:\LocalMachine\CA` | Intermediate CAs |
| `Cert:\LocalMachine\My` | Personal / server certs (used by IIS) |
| `Cert:\LocalMachine\AuthRoot` | Third-party root CAs |

## Examples

Import a corporate root CA:

```powershell
Certificate -Path  'C:\certs\corp-ca.cer' `
            -Store 'Cert:\LocalMachine\Root' `
            -State Present
```

Import a PFX for IIS, keeping the private key non-exportable:

```powershell
$pw = Get-SecureStringFromSsmParameterStore 'iis/pfx-password'  # your helper
Certificate -Path     'C:\certs\iis-wildcard.pfx' `
            -Store    'Cert:\LocalMachine\My' `
            -Password $pw `
            -State    Present
```

Remove an expired certificate by thumbprint:

```powershell
Certificate -Thumbprint 'ABCDEF0123456789...' `
            -Store      'Cert:\LocalMachine\My' `
            -State      Absent
```

## Destroy mode

`Present` flips to `Absent`.

## Notes

- When `-Path` is given, the resource computes the PFX thumbprint by loading the bundle with the provided `-Password`. `.cer` / `.crt` thumbprints are read directly.
- The Import-PfxCertificate default is to leave the private key non-exportable. Pass `-Exportable` if you specifically need it exportable (usually you don't).
- For DSC encryption certificates (used by LCM), this resource replaces the historical `LCM-Config.ps1` pattern entirely - once imported, any downstream `DscResource` calls that use encrypted credentials find the cert automatically.
