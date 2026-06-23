# Driver run on the Windows EC2 instance to verify Execute + File HTTPS + auth + checksum.
$ErrorActionPreference = 'Continue'
$env:DSC_MODE    = 'enforce'
$env:DSC_PROFILE = 'execute-and-file-test'

. C:\ProgramData\ssm-converge\lib.ps1

Write-Host "== ssm-converge version =="
Write-Host "v$($script:SsmConvergeVersion)"

# --- Test A: Execute with -Creates, run-once-then-skip ----------------------
$marker = 'C:\temp\ssmc-marker.txt'
Remove-Item $marker -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path 'C:\temp' -Force | Out-Null

Execute 'mark-once' `
    -Command "Set-Content -Path '$marker' -Value 'HELLO'" `
    -Creates $marker
Write-Host "first pass content: $(Get-Content $marker -ErrorAction SilentlyContinue)"

Execute 'mark-once' `
    -Command "Set-Content -Path '$marker' -Value 'SHOULD-NOT-RUN'" `
    -Creates $marker
Write-Host "second pass content (must still be HELLO): $(Get-Content $marker -ErrorAction SilentlyContinue)"

# --- Test B: Execute with -NotIf -------------------------------------------
$installed = 'C:\temp\ssmc-installed.txt'
Remove-Item $installed -ErrorAction SilentlyContinue
Execute 'guarded' `
    -Command "New-Item -ItemType File -Path '$installed' -Force | Out-Null" `
    -NotIf   "Test-Path '$installed'"

# --- Test C: File HTTPS download with checksum -----------------------------
$url   = 'https://www.gnu.org/licenses/gpl-3.0.txt'
$local = 'C:\temp\ssmc-gpl.txt'
Remove-Item $local -ErrorAction SilentlyContinue
File $local Present -Source $url
$expected = (Get-FileHash -Algorithm SHA256 -LiteralPath $local).Hash.ToLowerInvariant()
Write-Host "downloaded: $((Get-Item $local).Length) bytes, sha256=$expected"

# Re-run with correct checksum: should be no-op (compliant, not changed).
File $local Present -Source $url -Checksum "sha256:$expected"

# Wrong checksum: should fail.
Remove-Item $local -ErrorAction SilentlyContinue
File $local Present -Source $url -Checksum 'sha256:0000000000000000000000000000000000000000000000000000000000000000'

# --- Test D: File with -AuthBasic via httpbin -------------------------------
File 'C:\temp\ssmc-auth-ok.json' Present `
    -Source    'https://httpbin.org/basic-auth/svc-deploy/S3cret' `
    -AuthBasic 'svc-deploy:S3cret'

File 'C:\temp\ssmc-auth-bad.json' Present `
    -Source    'https://httpbin.org/basic-auth/svc-deploy/S3cret' `
    -AuthBasic 'wrong-user:wrong-pass'

# --- Test E: File with -AuthBearer via httpbin /bearer ---------------------
File 'C:\temp\ssmc-bearer-ok.json' Present `
    -Source     'https://httpbin.org/bearer' `
    -AuthBearer 'sample-token-xyz'

# --- Test F: download + Execute (full pattern) -----------------------------
$payload = 'C:\temp\ssmc-payload.bin'
$lines   = 'C:\temp\ssmc-payload.lines.txt'
Remove-Item $payload,$lines -ErrorAction SilentlyContinue

File $payload Present -Source $url

Execute 'process-payload' `
    -Command "(Get-Content '$payload').Length | Out-File -FilePath '$lines'" `
    -Creates $lines

if (Test-Path $lines) { Write-Host "payload lines: $(Get-Content $lines)" }

# --- Report ----------------------------------------------------------------
Report-Compliance

Write-Host ""
Write-Host "== Final report (filtered) =="
$report = Get-ReportJson | ConvertFrom-Json
Write-Host "summary: $($report.summary | ConvertTo-Json -Compress)"
foreach ($r in $report.resources) {
    Write-Host ("  {0,-13} changed={1,-5} {2}" -f $r.status, $r.changed, $r.resource)
}
