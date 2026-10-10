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
# PATCH-8: `localhost` resolves to ::1 first in the guest; with only the IPv4 binding the TLS handshake to [::1]:8443 is reset and clients (App Installer, .NET) fail with 0x80072EFE.
& netsh http add sslcert ipport=[::1]:$Port certhash=$($cert.Thumbprint) appid=$appId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'netsh http add sslcert [::1] failed' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("https://localhost:$Port/")
$listener.Start()
"serving $root at https://localhost:$Port/sliceapp/ (cert $($cert.Thumbprint))"
$types = @{ '.appinstaller' = 'application/appinstaller'; '.msix' = 'application/msix' }
# PATCH-9: the original single-threaded loop answered every request with the whole file via ReadAllBytes+Write, which throws for HEAD and Range requests
# (what App Installer / the deployment service send) and ended the script on the first exception (0x80072EFE at the client). The deployment service also opens
# several ranged connections at once. Now: a runspace pool (8 workers), HEAD without a body, byte ranges (206 + Content-Range), Accept-Ranges, chunked
# streaming, per-request try/catch, and a request log in %TEMP%\serve-local-feed.log.
$logPath = Join-Path $env:TEMP 'serve-local-feed.log'
$handler = {
    param($ctx, $root, $types, $logPath)
    $req = $ctx.Request; $res = $ctx.Response
    $line = ''
    try { [IO.File]::AppendAllText($logPath, "$(Get-Date -Format o) START $($req.HttpMethod) $($req.Url.AbsolutePath) range=[$($req.Headers['Range'])] ua=[$($req.UserAgent)] from=$($req.RemoteEndPoint)`r`n") } catch { }
    try {
        $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
        if ($rel.StartsWith('sliceapp/')) { $rel = $rel.Substring(9) } else { $rel = '' }
        $file = if ($rel) { [IO.Path]::GetFullPath((Join-Path $root $rel)) } else { '' }
        if ($file -and $file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
            $len = (Get-Item -LiteralPath $file).Length
            $start = 0L; $end = $len - 1; $status = 200
            $rng = $req.Headers['Range']
            if ($rng -and $rng -match '^bytes=(\d*)-(\d*)$') {
                if ($Matches[1] -ne '') { $start = [long]$Matches[1]; if ($Matches[2] -ne '') { $end = [Math]::Min([long]$Matches[2], $len - 1) } }
                elseif ($Matches[2] -ne '') { $start = [Math]::Max(0L, $len - [long]$Matches[2]) }
                $status = 206
                $res.AddHeader('Content-Range', "bytes $start-$end/$len")
            }
            $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
            $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $res.AddHeader('Accept-Ranges', 'bytes')
            $res.StatusCode = $status
            $res.ContentLength64 = ($end - $start + 1)
            if ($req.HttpMethod -ne 'HEAD') {
                $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
                try {
                    [void]$fs.Seek($start, 'Begin'); $left = $end - $start + 1; $sent = 0L; $nextMark = 4MB; $buf = New-Object byte[] 1048576
                    while ($left -gt 0) { $n = $fs.Read($buf, 0, [int][Math]::Min($buf.Length, $left)); if ($n -le 0) { break }; $res.OutputStream.Write($buf, 0, $n); $left -= $n; $sent += $n; if ($sent -ge $nextMark) { try { [IO.File]::AppendAllText($logPath, "$(Get-Date -Format o) PROGRESS $($req.Url.AbsolutePath) sent=$sent left=$left`r`n") } catch { }; $nextMark += 4MB } }
                } finally { $fs.Dispose() }
            }
            $line = "$(Get-Date -Format o) $status $($req.HttpMethod) $($req.Url.AbsolutePath) range=[$rng]"
        } else { $res.StatusCode = 404; $line = "$(Get-Date -Format o) 404 $($req.HttpMethod) $($req.Url.AbsolutePath)" }
    } catch { $line = "$(Get-Date -Format o) ERR $($req.HttpMethod) $($req.Url.AbsolutePath): $($_.Exception.Message)" }
    finally { try { $res.Close() } catch { } }
    try { [IO.File]::AppendAllText($logPath, $line + "`r`n") } catch { }
}
$pool = [runspacefactory]::CreateRunspacePool(1, 8); $pool.Open()
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $ps = [powershell]::Create(); $ps.RunspacePool = $pool
        [void]$ps.AddScript($handler).AddArgument($ctx).AddArgument($root).AddArgument($types).AddArgument($logPath)
        [void]$ps.BeginInvoke()
    }
} finally { $listener.Stop(); $pool.Close() }
