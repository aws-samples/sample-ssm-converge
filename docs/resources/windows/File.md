# `File` / `File-Content`

Manage a single file on Windows. Content can come from an inline string, an S3 object, an HTTPS URL (with optional authentication and checksum verification), or a local file.

## Syntax

```powershell
File '<Path>' <State> [-Source <uri>] [-Content <string>] [-Checksum <hash>] `
              [-AuthBearer <token>] [-AuthBasic <user:pass>] `
              [-Headers @{ ... }] [-Notify <handler>]

File-Content -Path '<Path>' -Content <here-string> [-Notify <handler>]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Ensure the file exists with the given content. |
| `Absent` | Remove the file if it exists. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Path` | *(positional 0)* | Path to the file. |
| `-Source` | - | Where the content comes from. Accepts: `s3://bucket/key`, `https://...`, `http://...`, `file:///C:/abs/path`, or a bare absolute path. |
| `-Content` | - | Inline string. SHA-256 used for drift detection. |
| `-Checksum` | - | Expected SHA-256 of the downloaded content, e.g. `'sha256:abc123...'`. **Recommended for any HTTPS source.** |
| `-AuthBearer` | - | Bearer token for HTTPS sources. Sent as `Authorization: Bearer <token>`. |
| `-AuthBasic` | - | HTTP basic auth, format `'user:pass'`. |
| `-Headers` | - | Hashtable of additional HTTP headers, e.g. `@{ 'X-Api-Key' = 'abc' }`. |
| `-Notify` | - | Handler name to fire when the file changes. |

## Examples

### Fetch from S3

```powershell
File 'C:\inetpub\wwwroot\web.config' Present `
     -Source 's3://DOC-EXAMPLE-BUCKET/web.config' `
     -Notify 'restart-iis'
```

### Fetch a public installer over HTTPS with checksum verification

```powershell
File 'C:\temp\agent.msi' Present `
     -Source   'https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi' `
     -Checksum 'sha256:abc123...'
```

The next run hashes the local file and compares to the expected checksum. If they match, no download happens.

### Authenticated download from a private artifact repo

```powershell
# GitHub release asset.
File 'C:\temp\release.zip' Present `
     -Source     'https://api.github.com/repos/my-org/my-app/releases/assets/123456' `
     -AuthBearer $env:GITHUB_TOKEN `
     -Headers    @{ 'Accept' = 'application/octet-stream' } `
     -Checksum   "sha256:$env:RELEASE_SHA256"

# Nexus / JFrog with HTTP basic auth.
File 'C:\temp\lib.dll' Present `
     -Source    'https://nexus.corp/private/lib.dll' `
     -AuthBasic 'svc-deploy:S3cret' `
     -Checksum  'sha256:abcdef...'

# Vendor API with custom headers.
File 'C:\temp\blob' Present `
     -Source  'https://api.vendor.com/download/v2/blob' `
     -Headers @{ 'X-Api-Key' = 'abc123'; 'X-Tenant' = 'prod' }
```

### Inline content

```powershell
File 'C:\app\app.conf' Present -Content 'key=value'
```

### Multi-line content via `File-Content`

```powershell
File-Content -Path 'C:\app\settings.json' -Content @'
{
  "port": 8080,
  "workers": 4
}
'@
```

### Remove a file

```powershell
File 'C:\temp\old.log' Absent
```

## Idempotency model

| Source kind | Drift detection without `-Checksum` | Drift detection with `-Checksum` |
|-------------|-------------------------------------|----------------------------------|
| `-Content`  | SHA-256 of `-Content` vs file       | (n/a) |
| `s3://...`  | Hashes a fresh download against the local file | Compare local SHA-256 to expected hash |
| `https://`, `http://` | Presence-only (no re-download) | Compare local SHA-256 to expected hash |
| `file://`, bare path | Presence-only             | Compare local SHA-256 to expected hash |

Pinning a checksum is recommended for any non-S3 source: it both detects drift and verifies the download integrity.

## Destroy mode

`Present` flips to `Absent`.

## Errors

- `download failed` - the configured fetcher (`Invoke-WebRequest`, `aws s3 cp`, or `Copy-Item`) returned non-zero.
- `checksum mismatch` - the file was downloaded but its SHA-256 did not match the expected value. The downloaded file is removed so the next run starts clean.

## Security notes

- TLS 1.2 is forced for HTTPS downloads (PowerShell 5.1's default sometimes negotiates older protocols).
- `-AuthBearer` and `-Headers` are passed through `Invoke-WebRequest`'s parameters, not via shell command lines.
- Prefer secrets pulled from Secrets Manager / SSM Parameter Store at runtime over plaintext values in the configuration.

## Notes

- The S3 path shells out to `aws.exe` on PATH (not `Read-S3Object`) for parity with the Linux path.
- Inline content is written as UTF-8 without BOM. If you need BOM or a specific encoding, use a separate Task / Handler.
- `File-Content` is a thin wrapper that calls `File Present -Content $Content`.
- See also [`Execute`](Execute.md) for the typical "download then run installer" pattern.
- The Linux equivalent is `file` / `file_content` - same semantics, different capitalisation.
