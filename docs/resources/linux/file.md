# `file`

Manage a single file: its content, ownership, and permissions. Content can come from an inline string, an S3 object, an HTTPS URL (with optional authentication and checksum verification), or a local file.

## Syntax

```bash
file '<path>' <state> [key value ...]
```

## Actions

| State | Effect |
|-------|--------|
| `present` | Ensure the file exists with the specified content and attributes. |
| `absent` | Remove the file if it exists. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `source` | - | Where the content comes from. Accepts: `s3://bucket/key`, `https://...`, `http://...`, `file:///abs/path`, or a bare absolute path. |
| `content` | - | Inline string that becomes the file's content. SHA-256 used for drift detection. |
| `checksum` | - | Expected SHA-256 of the downloaded content, e.g. `'sha256:abc123...'`. Used both for drift detection and to verify the download after fetching. **Recommended for any HTTPS source.** |
| `auth_bearer` | - | Bearer token for HTTPS sources. Sent as `Authorization: Bearer <token>`. Token is passed via curl config file (not the command line) to keep it out of `ps`. |
| `auth_basic` | - | HTTP basic auth, format `'user:pass'`. Sent through curl's `user` config (or wget's `--user`/`--password`). |
| `header` | - | Additional HTTP header, format `'Name: value'`. Repeatable - specify once per header. |
| `owner` | - | User name (not UID) that should own the file. |
| `group` | - | Group name (not GID) that should own the file. |
| `mode` | - | Octal mode, e.g. `'0644'`, `'0600'`. Zero-padding-insensitive. |
| `notify` | - | Handler name to fire when this file changes. |

Use either `source` or `content`, not both. Neither is required if the file just needs to exist with specific attributes.

## Examples

### File from S3

```bash
file '/etc/nginx/nginx.conf' present \
  source 's3://DOC-EXAMPLE-BUCKET/nginx.conf' \
  owner 'root' group 'root' mode '0644' \
  notify 'reload-nginx'
```

### File from a public HTTPS URL with checksum verification

```bash
file '/tmp/amazon-cloudwatch-agent.deb' present \
  source   'https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb' \
  checksum 'sha256:9f4c1d3a...e8b2'   \
  mode '0644'
```

The next run hashes the local file and compares to the expected checksum. If they match, no download happens. Drift is detected if the file is replaced or corrupted.

### Authenticated download from a private artifact repo

```bash
# GitHub release asset (requires Accept header for the binary, plus a token).
file '/tmp/release.tgz' present \
  source      'https://api.github.com/repos/my-org/my-app/releases/assets/123456' \
  auth_bearer "$GITHUB_TOKEN" \
  header      'Accept: application/octet-stream' \
  checksum    "sha256:$RELEASE_SHA256"
```

```bash
# Nexus or JFrog with HTTP basic auth.
file '/tmp/lib.jar' present \
  source     'https://nexus.corp/private/lib.jar' \
  auth_basic 'svc-deploy:S3cret' \
  checksum   'sha256:abcdef...'
```

```bash
# Vendor API with an X-Api-Key header.
file '/tmp/blob' present \
  source 'https://api.vendor.com/download/v2/blob' \
  header 'X-Api-Key: abc123' \
  header 'X-Tenant: prod'
```

### Inline content

```bash
file '/etc/motd' present content 'Welcome to production'
```

### Enforce permissions on an existing file (no content change)

```bash
file '/etc/shadow' present owner 'root' group 'root' mode '0600'
```

### Remove a file

```bash
file '/tmp/debug.log' absent
```

## Idempotency model

| Source kind | Drift detection without `checksum` | Drift detection with `checksum` |
|-------------|------------------------------------|---------------------------------|
| Inline `content` | SHA-256 of `content` vs file | (n/a; `content` already implies its own hash) |
| `s3://...` | Hashes a fresh download against the local file | Compare local SHA-256 to expected hash |
| `https://`, `http://` | Presence-only (cheap; no re-download) | Compare local SHA-256 to expected hash |
| `file://`, bare path | Presence-only | Compare local SHA-256 to expected hash |

Pinning a `checksum` is recommended for any non-S3 source: it both detects drift and verifies the download integrity.

## Destroy mode

`present` flips to `absent`: the configuration's files are deleted.

## Errors

- `download failed` - the configured fetcher (curl, wget, aws s3 cp, or local cp) returned non-zero. Check the URL, network reachability, IAM role, or credentials.
- `checksum mismatch` - the file was downloaded but its SHA-256 did not match the expected value. The downloaded file is removed so the next run starts clean.

## Security notes

- Authentication tokens go through curl's config file (`-K`), not the command line, so they don't appear in `ps`. The config file is created with mode 0600, written to `/dev/shm` when available (RAM-backed), and removed immediately after the fetch.
- Prefer `auth_bearer` with a short-lived token from Secrets Manager / SSM Parameter Store over `auth_basic`. Keep the configuration loading the token into a shell var just before calling `file`.
- For S3 sources, prefer instance role credentials over baking access keys into the configuration.

## Notes

- Parent directory is created automatically when writing content.
- The HTTP fetcher prefers `curl` and falls back to `wget` if curl is missing.
- TLS protocol negotiation follows the system's curl/wget defaults; both honour the OS trust store.
- For heredoc-style multi-line content, use [`file_content`](file_content.md) instead.
- See [`execute`](execute.md) for the typical "download then run installer" pattern.
