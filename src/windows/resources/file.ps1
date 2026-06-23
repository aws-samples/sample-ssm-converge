# ===============================================================================
# SSM Converge - Resource Provider: File (Windows)
#
# Manage a single file on Windows. Content may come from an S3 object, an
# HTTPS URL (with optional auth + checksum), or an inline string.
#
# Source schemes:
#   s3://bucket/key       - aws s3 cp (requires aws.exe on PATH)
#   https://...|http://...- Invoke-WebRequest
#   file:///C:/abs/path   - local copy
#   bare absolute path    - local copy
#
# Idempotency for remote sources:
#   - With -Checksum 'sha256:...', subsequent runs are no-ops once the hash matches.
#   - Without -Checksum, presence of the file is treated as compliant. Pin a
#     checksum if you need drift detection.
#
# Authentication for HTTP(S):
#   -AuthBearer 'TOKEN'         -> Authorization: Bearer TOKEN
#   -AuthBasic  'user:pass'     -> HTTP basic auth
#   -Headers    @{ k = 'v' }    -> arbitrary additional headers
#
# Usage:
#   File 'C:\inetpub\wwwroot\web.config' Present -Source 's3://bucket/web.config'
#
#   File 'C:\app\config\app.conf' Present -Content 'key=value'
#
#   File 'C:\temp\agent.msi' Present `
#       -Source   'https://vendor.com/agent.msi' `
#       -Checksum 'sha256:abc123...'
#
#   File 'C:\temp\release.zip' Present `
#       -Source     'https://api.github.com/repos/x/y/releases/assets/123' `
#       -AuthBearer $env:GITHUB_TOKEN `
#       -Headers    @{ 'Accept' = 'application/octet-stream' }
#
#   File 'C:\temp\old.log' Absent
#
#   # Heredoc-style multi-line content:
#   File-Content -Path 'C:\app\settings.json' -Content @'
#   {
#     "port": 8080,
#     "workers": 4
#   }
#   '@
# ===============================================================================

function File-Content {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [string]$Notify
    )
    File $Path Present -Content $Content -Notify $Notify
}

# --- Internal: parse 'sha256:HEX' or 'HEX' to lowercase hex ------------------
function _File-ParseChecksum {
    param([string]$Raw)
    if (-not $Raw) { return '' }
    $h = $Raw -replace '^sha256:', '' -replace '^SHA256:', ''
    return $h.ToLowerInvariant()
}

# --- Internal: SHA-256 of a file as lowercase hex ----------------------------
function _File-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}

# --- Internal: download from any supported scheme to a destination path ------
function _File-Fetch {
    param(
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$Source,
        [string]$AuthBearer,
        [string]$AuthBasic,
        [hashtable]$Headers
    )

    if ($Source -match '^s3://') {
        & aws s3 cp $Source $Dest --quiet 2>$null
        return ($LASTEXITCODE -eq 0)
    }

    if ($Source -match '^https?://') {
        return (_File-FetchHttp -Dest $Dest -Source $Source -AuthBearer $AuthBearer -AuthBasic $AuthBasic -Headers $Headers)
    }

    if ($Source -match '^file://') {
        $local = $Source -replace '^file:///?', ''
        try { Copy-Item -LiteralPath $local -Destination $Dest -Force -ErrorAction Stop; return $true }
        catch { _Debug "file: local copy failed: $($_.Exception.Message)"; return $false }
    }

    # Bare path
    try { Copy-Item -LiteralPath $Source -Destination $Dest -Force -ErrorAction Stop; return $true }
    catch { _Debug "file: copy failed: $($_.Exception.Message)"; return $false }
}

# --- Internal: HTTP(S) download via Invoke-WebRequest ------------------------
function _File-FetchHttp {
    param(
        [string]$Dest,
        [string]$Source,
        [string]$AuthBearer,
        [string]$AuthBasic,
        [hashtable]$Headers
    )

    $hdr = @{}
    if ($Headers) {
        foreach ($k in $Headers.Keys) { $hdr[$k] = [string]$Headers[$k] }
    }
    if ($AuthBearer) {
        $hdr['Authorization'] = "Bearer $AuthBearer"
    }

    $iwrParams = @{
        Uri             = $Source
        OutFile         = $Dest
        UseBasicParsing = $true
        TimeoutSec      = 600
        ErrorAction     = 'Stop'
    }
    if ($hdr.Count -gt 0) { $iwrParams['Headers'] = $hdr }

    if ($AuthBasic) {
        $parts = $AuthBasic -split ':', 2
        if ($parts.Count -eq 2) {
            $sec  = ConvertTo-SecureString $parts[1] -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($parts[0], $sec)
            $iwrParams['Credential'] = $cred
        }
    }

    # Force TLS 1.2 (PS5.1 default is sometimes TLS 1.0/1.1).
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol } catch {}

    try {
        Invoke-WebRequest @iwrParams | Out-Null
        return $true
    } catch {
        _Debug "file: HTTP download failed: $($_.Exception.Message)"
        return $false
    }
}

function File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$Path,
        [Parameter(Mandatory, Position=1)][ValidateSet('Present','Absent')][string]$State,
        [string]$Source,
        [string]$Content,
        [string]$Checksum,
        [string]$AuthBearer,
        [string]$AuthBasic,
        [hashtable]$Headers,
        [string]$Notify
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart    = Get-NowMs
    $resourceName  = "file$Path"
    $expectedHash  = _File-ParseChecksum $Checksum

    $isRemote = ($Source -match '^(s3://|https?://|file://)')

    switch ($State) {
        'Present' {
            $compliant = $true
            $reasons   = [System.Collections.ArrayList]::new()

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                $compliant = $false
                $null = $reasons.Add('missing')
            } else {
                # Inline content drift via SHA-256.
                if ($Content) {
                    $hasher = [System.Security.Cryptography.SHA256]::Create()
                    $desiredHash = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Content))) -replace '-','').ToLowerInvariant()
                    $currentHash = _File-Sha256 $Path
                    if ($desiredHash -ne $currentHash) {
                        $compliant = $false
                        $null = $reasons.Add('content drift')
                    }
                }

                # Remote source drift.
                if ($Source -and -not $Content) {
                    if ($expectedHash) {
                        $currentHash = _File-Sha256 $Path
                        if ($currentHash -ne $expectedHash) {
                            $compliant = $false
                            $null = $reasons.Add('checksum mismatch')
                        }
                    }
                    elseif ($Source -match '^s3://') {
                        # S3 + no checksum: hash compare against fresh fetch.
                        $tmp = New-TemporaryFile
                        & aws s3 cp $Source $tmp.FullName --quiet 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            $desiredHash = _File-Sha256 $tmp.FullName
                            $currentHash = _File-Sha256 $Path
                            if ($desiredHash -ne $currentHash) {
                                $compliant = $false
                                $null = $reasons.Add('content drift')
                            }
                        }
                        Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue
                    }
                    # http(s)/file:// + no checksum: presence treated as compliant.
                }
            }

            $checkMs = (Get-NowMs) - $checkStart

            if ($compliant) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }

            if (-not (_Should-Apply)) {
                $why = $reasons -join ', '
                _Log-Drift $resourceName $why
                _Record-Result $resourceName 'non_compliant' $false $why $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                $parent = Split-Path $Path -Parent
                if ($parent -and -not (Test-Path $parent)) {
                    $null = New-Item -ItemType Directory -Force -Path $parent -ErrorAction Stop
                }

                if ($Source) {
                    $ok = _File-Fetch -Dest $Path -Source $Source -AuthBearer $AuthBearer -AuthBasic $AuthBasic -Headers $Headers
                    if (-not $ok) {
                        $applyMs = (Get-NowMs) - $applyStart
                        _Log-Error $resourceName "failed to download from $Source"
                        _Record-Result $resourceName 'error' $false 'download failed' $checkMs $applyMs
                        return
                    }
                    if ($expectedHash) {
                        $gotHash = _File-Sha256 $Path
                        if ($gotHash -ne $expectedHash) {
                            $applyMs = (Get-NowMs) - $applyStart
                            _Log-Error $resourceName "checksum mismatch after download (got $gotHash)"
                            _Record-Result $resourceName 'error' $false 'checksum mismatch' $checkMs $applyMs
                            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                            return
                        }
                    }
                } elseif ($Content) {
                    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
                } elseif (-not (Test-Path -LiteralPath $Path)) {
                    New-Item -ItemType File -Force -Path $Path | Out-Null
                }

                $applyMs = (Get-NowMs) - $applyStart
                $why = $reasons -join ', '
                _Log-Changed $resourceName "converged ($why)"
                _Record-Result $resourceName 'compliant' $true "converged: $why" $checkMs $applyMs
                if ($Notify) { _Notify-Handler $Notify }
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }

        'Absent' {
            $checkMs = (Get-NowMs) - $checkStart

            if (-not (Test-Path -LiteralPath $Path)) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }

            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName 'exists (should be absent)'
                _Record-Result $resourceName 'non_compliant' $false 'exists' $checkMs 0
                return
            }

            $applyStart = Get-NowMs
            try {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName 'removed'
                _Record-Result $resourceName 'compliant' $true 'removed' $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }
    }
}
