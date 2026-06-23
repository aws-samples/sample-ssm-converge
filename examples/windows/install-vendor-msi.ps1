# =============================================================================
# SSM Converge Configuration: Download a vendor MSI/EXE and install it
#
# Demonstrates the canonical "download + unattended install" pattern using
# only built-in resources:
#
#   1. File downloads the artifact (S3 or HTTPS, authenticated or public,
#      with checksum verification).
#   2. Execute runs the installer with a guard so it only runs once.
#   3. WindowsService starts the resulting service and ensures Automatic.
#
# Three concrete scenarios are shown:
#
#   A. Public HTTPS download (Amazon CloudWatch Agent .msi) - no auth
#   B. Authenticated HTTPS download (token-based, Artifactory-style)
#   C. S3 download (instance-role credentials)
#
# Pick whichever matches your delivery model. The pattern is the same.
#
# Run:
#   $env:DSC_MODE    = 'enforce'         # or audit / destroy
#   $env:DSC_PROFILE = 'install-vendor'
#   . C:\ProgramData\ssm-converge\lib.ps1
#   . examples\windows\install-vendor-msi.ps1
# =============================================================================

. C:\ProgramData\ssm-converge\lib.ps1

# --- Scenario A: Public HTTPS download - Amazon CloudWatch Agent ------------

$cwUrl   = 'https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi'
$cwLocal = 'C:\temp\amazon-cloudwatch-agent.msi'

# Pin a checksum if you have one. See File.md for guidance on resolving
# the expected hash at runtime (sidecar file, SSM parameter, etc.).
# $cwSha256 = 'sha256:abcd1234...'

$fileParams = @{ Source = $cwUrl }
if ($cwSha256) { $fileParams['Checksum'] = $cwSha256 }
File $cwLocal Present @fileParams

Execute 'install-cloudwatch-agent' `
        -Command     "msiexec /i $cwLocal /qn /norestart" `
        -Creates     'C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1' `
        -Interpreter 'cmd'

# The agent service won't start until a configuration is supplied; we just
# ensure the service is registered with the right startup type.
WindowsService 'AmazonCloudWatchAgent' Stopped -StartupType Automatic -ErrorAction SilentlyContinue

# --- Scenario B: Authenticated HTTPS download from a private artifact repo --

if ($env:MYCO_TOKEN -and $env:MYCO_VERSION) {
    $mycoUrl   = "https://artifactory.corp/repos/agents/myco-agent-$($env:MYCO_VERSION).msi"
    $mycoLocal = 'C:\temp\myco-agent.msi'

    $fileParams = @{
        Source     = $mycoUrl
        AuthBearer = $env:MYCO_TOKEN
        Headers    = @{ 'Accept' = 'application/octet-stream' }
    }
    if ($env:MYCO_SHA256) { $fileParams['Checksum'] = $env:MYCO_SHA256 }
    File $mycoLocal Present @fileParams

    Execute 'install-myco-agent' `
            -Command     "msiexec /i $mycoLocal /qn /norestart" `
            -NotIf       '(Get-Package -Name "Myco Agent" -ErrorAction SilentlyContinue) -ne $null' `
            -Interpreter 'cmd'

    WindowsService 'MycoAgent' Running -StartupType Automatic
}

# --- Scenario C: S3 download with instance-role credentials -----------------

if ($env:S3_AGENT_BUCKET) {
    $agentLocal = 'C:\temp\internal-agent.msi'
    File $agentLocal Present -Source "s3://$($env:S3_AGENT_BUCKET)/internal-agent.msi"

    Execute 'install-internal-agent' `
            -Command     "msiexec /i $agentLocal /qn /norestart" `
            -NotIf       '(Get-Package -Name "Internal Agent" -ErrorAction SilentlyContinue) -ne $null' `
            -Interpreter 'cmd'

    WindowsService 'InternalAgent' Running -StartupType Automatic
}

# --- Scenario D: A non-MSI installer (EXE with silent flags) ----------------
#
# Many vendors ship InnoSetup or NSIS-based installers. Silent flags vary;
# common ones:
#   InnoSetup: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
#   NSIS:      /S
#   InstallShield: /s /v"/qn /norestart"

if ($env:VENDOR_EXE_URL -and $env:VENDOR_EXE_SHA256) {
    File 'C:\temp\vendor-setup.exe' Present `
         -Source   $env:VENDOR_EXE_URL `
         -Checksum $env:VENDOR_EXE_SHA256

    Execute 'install-vendor-app' `
            -Command     'C:\temp\vendor-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' `
            -Creates     'C:\Program Files\Vendor\app.exe' `
            -Interpreter 'cmd'
}

# --- Report -----------------------------------------------------------------

Report-Compliance

if (Test-RebootRequired) {
    Write-Host ''
    Write-Host 'Reboot required (some MSI installers request it). Reboot and re-run.'
}
