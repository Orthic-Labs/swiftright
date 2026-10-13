# Guest smoke of the test-signed tuple 12 SliceApp MSIX inside Windows Sandbox (job kind=command runs this file).
#   1. trust the throwaway signer, Add-AppxPackage the MSIX
#   2. activate through shell:AppsFolder (packaged identity), wait for the SliceApp window, screenshot it, check it renders, close through WM_CLOSE
#   3. unpack the same MSIX and run the existing QA driver `launch` case against those bytes (scrubbed PATH, UIA ready signal, 5 rows, clean quit exit 0)
#   4. remove the package
$ErrorActionPreference = 'Continue'
$d = 'C:\sbq\tuple12'; $out = Join-Path $d 'out'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null
$r = [ordered]@{ started = (Get-Date).ToString('o') }
function Save { ($r | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $out 'smoke.json') -Encoding utf8 }
try {
    $msix = Join-Path $d 'SliceApp_0.1.0.0_x64.testsigned.msix'
    $r.msix_sha256 = (Get-FileHash $msix -Algorithm SHA256).Hash
    $r.os = [string][Environment]::OSVersion.Version
    Import-Certificate -FilePath (Join-Path $d 'test-signer.cer') -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    $sig = Get-AuthenticodeSignature $msix
    $r.signature_status = [string]$sig.Status; $r.signer = $sig.SignerCertificate.Subject
    Get-AppxPackage -Name OrthicLabs.SliceApp | Remove-AppxPackage -ErrorAction SilentlyContinue
    Add-AppxPackage -Path $msix -ErrorAction Stop
    $pkg = Get-AppxPackage -Name OrthicLabs.SliceApp
    $r.package = [ordered]@{ full = $pkg.PackageFullName; version = [string]$pkg.Version; status = [string]$pkg.Status; arch = [string]$pkg.Architecture; install = $pkg.InstallLocation; signatureKind = [string]$pkg.SignatureKind }
    $appId = [string](Get-AppxPackageManifest -Package $pkg.PackageFullName).Package.Applications.Application.Id
    $r.app_id = $appId
    Save

    # --- packaged activation
    Add-Type -AssemblyName System.Drawing
    Add-Type -Namespace T12 -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }'
    Start-Process explorer.exe ('shell:AppsFolder\' + $pkg.PackageFamilyName + '!' + $appId)
    $proc = $null
    for ($i = 0; $i -lt 60 -and -not ($proc -and $proc.MainWindowHandle -ne 0); $i++) { Start-Sleep -Milliseconds 500; $proc = Get-Process SliceApp -ErrorAction SilentlyContinue | Select-Object -First 1; if ($proc) { $proc.Refresh() } }
    $act = [ordered]@{ process_found = [bool]$proc }
    if ($proc) {
        $act.pid = $proc.Id; $act.path = $proc.Path; $act.window_title = $proc.MainWindowTitle; $act.window_visible = [T12.W]::IsWindowVisible($proc.MainWindowHandle)
        Start-Sleep -Seconds 4
        $rc = New-Object T12.W+RECT; [void][T12.W]::GetWindowRect($proc.MainWindowHandle, [ref]$rc)
        $w = $rc.right - $rc.left; $h = $rc.bottom - $rc.top; $act.window_size = "$w x $h"
        if ($w -gt 50 -and $h -gt 50) {
            $bmp = New-Object System.Drawing.Bitmap $w, $h
            $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($rc.left, $rc.top, 0, 0, $bmp.Size); $g.Dispose()
            $png = Join-Path $out 'packaged-window.png'; $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
            $colors = @{}; $dark = 0; $total = 0
            for ($y = 0; $y -lt $h; $y += 3) { for ($x = 0; $x -lt $w; $x += 3) { $c = $bmp.GetPixel($x, $y); $colors[$c.ToArgb()] = 1; $total++; if ($c.R + $c.G + $c.B -lt 60) { $dark++ } } }
            $bmp.Dispose()
            $act.screenshot = $png; $act.distinct_colors_sampled = $colors.Count; $act.black_fraction = [math]::Round($dark / [math]::Max(1, $total), 3)
            $act.rendered = ($colors.Count -gt 20 -and ($dark / [math]::Max(1, $total)) -lt 0.9)
        }
        $act.close_sent = $proc.CloseMainWindow()
        $exited = $proc.WaitForExit(20000)
        $act.exited_within_20s = $exited
        if (-not $exited) { $act.forced_kill = $true; try { $proc.Kill() } catch { } }
    }
    $act.crash_events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', 'Windows Error Reporting'; StartTime = [datetime]$r.started } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'SliceApp' } | ForEach-Object { $_.Message.Substring(0, [math]::Min(200, $_.Message.Length)) })
    $r.packaged_activation = $act
    Save

    # --- same bytes through the QA driver launch case
    $app = Join-Path $d 'app'
    Remove-Item -Recurse -Force $app -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force (Join-Path $app 'qa'), (Join-Path $app '.build') | Out-Null
    Copy-Item (Join-Path $d 'drive-windows.ps1') (Join-Path $app 'qa\drive-windows.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = Join-Path $app '.build\msix-stage'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($msix, $stage)
    $rec = [ordered]@{ commit = ''; exeSha256 = (Get-FileHash (Join-Path $stage 'SliceApp.exe') -Algorithm SHA256).Hash; rendererSha256 = (Get-FileHash (Join-Path $stage 'swiftright_render.dll') -Algorithm SHA256).Hash }
    ($rec | ConvertTo-Json -Compress) | Set-Content (Join-Path $app '.build\qa-build.json') -Encoding utf8
    # the driver asks git for a commit; the Sandbox has no git, so an empty answer is the build record's commit
    $shim = Join-Path $d 'bin'; New-Item -ItemType Directory -Force $shim | Out-Null
    Set-Content (Join-Path $shim 'git.cmd') '@exit /b 1' -Encoding ascii
    $env:Path = $shim + ';' + $env:Path
    $env:SLICEAPP_QA_DATA = Join-Path $out 'qa-data'
    $json = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $app 'qa\drive-windows.ps1') launch 2>(Join-Path $out 'driver-stderr.txt')
    $r.driver_exit = $LASTEXITCODE
    ($json -join "`n") | Set-Content (Join-Path $out 'driver-launch.json') -Encoding utf8
    try { $j = ($json -join "`n") | ConvertFrom-Json; $r.driver_launch = [ordered]@{ ok = $j.ok; windowShown = $j.windowShown; windowTitle = $j.windowTitle; ready = $j.ready; rowCount = $j.rowCount; quit = $j.quit; error = $j.error } } catch { $r.driver_parse_error = $_.Exception.Message }
    Save
} catch {
    $r.error = $_.Exception.Message
}
try { Get-AppxPackage -Name OrthicLabs.SliceApp | Remove-AppxPackage -ErrorAction Stop; $r.package_removed = -not [bool](Get-AppxPackage -Name OrthicLabs.SliceApp) } catch { $r.remove_error = $_.Exception.Message }
$r.finished = (Get-Date).ToString('o')
Save
