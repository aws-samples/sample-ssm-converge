# =============================================================================
# SSM Converge Configuration: IIS Web Server
#
# Installs IIS on Windows Server and configures a simple site:
#   - Web-Server role + common sub-features
#   - IIS management console
#   - A site directory at C:\inetpub\example.com
#   - A default index.html
#   - W3SVC running and set to Automatic
#   - Basic hardening via RegistryKey (disable directory browsing default)
#
# All primitives - no DscResource needed. Demonstrates that a full IIS stack
# is achievable with just the SSM Converge Windows primitives.
#
# Run:
#   $env:DSC_MODE    = "audit"           # or enforce / destroy / comply
#   $env:DSC_PROFILE = "iis-webserver"
#   . C:\ProgramData\ssm-converge\lib.ps1
#   . examples\windows\iis-webserver.ps1
# =============================================================================

. C:\ProgramData\ssm-converge\lib.ps1

$SiteName = 'example.com'
$SiteRoot = "C:\inetpub\$SiteName"

# -- 1. IIS role + common sub-features ---------------------------------------

WindowsFeature 'Web-Server'           Installed -IncludeManagementTools
WindowsFeature 'Web-Common-Http'      Installed
WindowsFeature 'Web-Default-Doc'      Installed
WindowsFeature 'Web-Dir-Browsing'     Installed
WindowsFeature 'Web-Http-Errors'      Installed
WindowsFeature 'Web-Static-Content'   Installed
WindowsFeature 'Web-Http-Logging'     Installed
WindowsFeature 'Web-Stat-Compression' Installed
WindowsFeature 'Web-Filtering'        Installed

# -- 2. Directory layout ----------------------------------------------------

Directory $SiteRoot Present

# -- 3. Default landing page ------------------------------------------------

File-Content -Path (Join-Path $SiteRoot 'index.html') -Content @"
<!DOCTYPE html>
<html>
<head><title>$SiteName</title></head>
<body>
  <h1>It works - $SiteName</h1>
  <p>Managed by SSM Converge on $(hostname)</p>
</body>
</html>
"@

# -- 4. Security hardening via registry --------------------------------------
#    Remove the "Server:" response header that reveals IIS/version info.
#    Keeps the banner generic for anyone probing.

RegistryKey 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' Present `
    -ValueName 'DisableServerHeader' -ValueData 1 -ValueType DWord

# -- 5. Service state --------------------------------------------------------
#    W3SVC = World Wide Web Publishing Service (the IIS service).

WindowsService 'W3SVC' Running -StartupType Automatic

# -- 6. Host entry (convenient name that resolves on the box itself) ---------

HostEntry '127.0.0.1' Present -Hostname "$SiteName local.$SiteName"

# -- 7. Report ---------------------------------------------------------------

Report-Compliance

if (Test-RebootRequired) {
    Write-Host ""
    Write-Host "Reboot required (usually from Web-Server feature install). Reboot and re-run."
}
