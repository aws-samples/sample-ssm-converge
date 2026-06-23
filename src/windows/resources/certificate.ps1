# =============================================================================
# SSM Converge - Resource Provider: Certificate
#
# Imports certificates into a Windows certificate store. Replaces the ad-hoc
# `Import-PfxCertificate` / `Import-Certificate` calls that LCM-Config.ps1 uses
# to seed the DSC encryption cert, as well as the DSC CertificateDsc resources.
#
# Usage:
#   # Import a public cert (.cer/.crt) into LocalMachine\Root:
#   Certificate -Path  'C:\certs\corp-ca.cer' `
#               -Store 'Cert:\LocalMachine\Root' `
#               -State Present
#
#   # Import a PFX into LocalMachine\My (the personal store used by IIS):
#   Certificate -Path       'C:\certs\iis-wildcard.pfx' `
#               -Store      'Cert:\LocalMachine\My' `
#               -Password   (ConvertTo-SecureString 'p@ssw0rd' -AsPlainText -Force) `
#               -State      Present
#
#   # Remove by thumbprint:
#   Certificate -Thumbprint 'ABCDEF0123456789...' `
#               -Store      'Cert:\LocalMachine\My' `
#               -State      Absent
# =============================================================================

function Certificate {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Thumbprint,
        [Parameter(Mandatory)][string]$Store,
        [Parameter(Mandatory)][ValidateSet('Present','Absent')][string]$State,
        [System.Security.SecureString]$Password,
        [switch]$Exportable
    )

    if (_Is-DestroyMode) { $State = _Flip-State $State }

    $checkStart = Get-NowMs

    # Resolve thumbprint if we only have a file path.
    $desiredThumb = $Thumbprint
    if (-not $desiredThumb -and $Path -and (Test-Path $Path)) {
        try {
            $ext = [IO.Path]::GetExtension($Path).ToLower()
            if ($ext -eq '.pfx' -or $ext -eq '.p12') {
                if (-not $Password) { throw "PFX certificates require -Password for thumbprint lookup" }
                $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
                $col.Import($Path, ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))),
                    'DefaultKeySet')
                $desiredThumb = $col[0].Thumbprint
            } else {
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $Path
                $desiredThumb = $cert.Thumbprint
            }
        } catch {
            $checkMs = (Get-NowMs) - $checkStart
            _Log-Error "certificate/$Path" $_.Exception.Message
            _Record-Result "certificate/$Path" 'error' $false $_.Exception.Message $checkMs 0
            return
        }
    }

    if (-not $desiredThumb) {
        $checkMs = (Get-NowMs) - $checkStart
        _Log-Error 'certificate' 'could not determine thumbprint - provide -Thumbprint or -Path'
        _Record-Result 'certificate' 'error' $false 'no thumbprint' $checkMs 0
        return
    }

    $resourceName = "certificate/$desiredThumb"
    $present = [bool](Get-ChildItem -Path $Store -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $desiredThumb })

    $checkMs = (Get-NowMs) - $checkStart

    switch ($State) {
        'Present' {
            if ($present) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName "not in $Store"
                _Record-Result $resourceName 'non_compliant' $false "not in $Store" $checkMs 0
                return
            }
            if (-not $Path) {
                _Log-Error $resourceName "cannot import without -Path"
                _Record-Result $resourceName 'error' $false 'no source path' $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                $ext = [IO.Path]::GetExtension($Path).ToLower()
                if ($ext -eq '.pfx' -or $ext -eq '.p12') {
                    $params = @{ FilePath = $Path; CertStoreLocation = $Store; Password = $Password; ErrorAction = 'Stop' }
                    if ($Exportable) { $params['Exportable'] = $true }
                    Import-PfxCertificate @params | Out-Null
                } else {
                    Import-Certificate -FilePath $Path -CertStoreLocation $Store -ErrorAction Stop | Out-Null
                }
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName "imported into $Store"
                _Record-Result $resourceName 'compliant' $true "imported into $Store" $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }

        'Absent' {
            if (-not $present) {
                _Log-Ok $resourceName
                _Record-Result $resourceName 'compliant' $false '' $checkMs 0
                return
            }
            if (-not (_Should-Apply)) {
                _Log-Drift $resourceName "still present in $Store"
                _Record-Result $resourceName 'non_compliant' $false "present in $Store" $checkMs 0
                return
            }
            $applyStart = Get-NowMs
            try {
                Get-ChildItem -Path $Store | Where-Object { $_.Thumbprint -eq $desiredThumb } |
                    Remove-Item -Force -ErrorAction Stop
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Changed $resourceName "removed from $Store"
                _Record-Result $resourceName 'compliant' $true "removed from $Store" $checkMs $applyMs
            } catch {
                $applyMs = (Get-NowMs) - $applyStart
                _Log-Error $resourceName $_.Exception.Message
                _Record-Result $resourceName 'error' $false $_.Exception.Message $checkMs $applyMs
            }
        }
    }
}
