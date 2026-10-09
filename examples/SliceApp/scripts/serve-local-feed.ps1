# F8: serve a local App Installer feed over loopback https INSIDE the disposable Windows Sandbox guest (host loopback
# is not reachable from the Sandbox, so the feed lives in the guest). Never run this on the Dell desktop or any
# machine that is not a throwaway guest: it adds a self-signed certificate to the machine Trusted Root store and binds
# it to a port. Requires elevation (the Sandbox user is an administrator).
#   serve-local-feed.ps1 -Dir C:\feed -DisposableGuest [-Port 8443]
# Layout under -Dir (URL path /sliceapp/): SliceApp.appinstaller plus the .msix files it names.
# Publishing "the update" = replace SliceApp.appinstaller with one for the newer version (make-local-appinstaller.mjs);
# the server re-reads files per request, no restart. Ctrl+C or closing the Sandbox stops it.
param([Parameter(Mandatory)][string]$Dir, [int]$Port = 8443, [switch]$DisposableGuest)
$ErrorActionPreference = 'Stop'
if (-not $DisposableGuest) { throw 'refusing to run: pass -DisposableGuest to confirm this is a throwaway Windows Sandbox guest' }
if (-not (Test-Path -LiteralPath $Dir)) { throw "feed directory not found: $Dir" }
$root = (Resolve-Path -LiteralPath $Dir).Path
$cert = New-SelfSignedCertificate -DnsName 'localhost' -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddDays(2)
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
$rootStore.Open('ReadWrite'); $rootStore.Add($cert); $rootStore.Close()
$appId = [guid]::NewGuid().ToString('B')
& netsh http add sslcert ipport=127.0.0.1:$Port certhash=$($cert.Thumbprint) appid=$appId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'netsh http add sslcert failed' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("https://localhost:$Port/")
$listener.Start()
"serving $root at https://localhost:$Port/sliceapp/ (cert $($cert.Thumbprint))"
$types = @{ '.appinstaller' = 'application/appinstaller'; '.msix' = 'application/msix' }
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
        if ($rel.StartsWith('sliceapp/')) { $rel = $rel.Substring(9) } else { $rel = '' }
        $file = if ($rel) { [IO.Path]::GetFullPath((Join-Path $root $rel)) } else { '' }
        if ($file -and $file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
            $ctx.Response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            "$(Get-Date -Format o) 200 $($ctx.Request.Url.AbsolutePath)"
        } else { $ctx.Response.StatusCode = 404; "$(Get-Date -Format o) 404 $($ctx.Request.Url.AbsolutePath)" }
        $ctx.Response.Close()
    }
} finally { $listener.Stop() }
