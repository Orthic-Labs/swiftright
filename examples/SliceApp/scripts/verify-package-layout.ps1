# Verifies the renderer packaging contract (F1) without launching the app.
#   -Mode Stage      -Root <flat stage dir>  (.build\msix-stage): pre-pack static check
#   -Mode Installed  (default root: the installed OrthicLabs.SliceApp InstallLocation): post-install check
# Static checks (both modes):
#   1. SliceApp.exe and swiftright_render.dll are in the same directory (the loader's default name resolves beside the exe).
#   2. The renderer is byte-identical to Windows\renderer-pin.json (sha256).
#   3. Every shipped closure entry the pin names (VCRUNTIME140.dll) sits beside it.
#   4. The loader's default name literal in packages\SwiftRightBridge ...\Loader.swift equals the pin's file name, so no
#      environment variable or PATH entry is needed (checked only when the source tree is present).
# Installed mode also (no GUI, no app launch):
#   5. In a child process with SWIFTRIGHT_RENDER_DLL removed and PATH reduced to System32/Windows only (no Swift runtime,
#      no developer tools), LoadLibraryEx(<installed dll>, LOAD_WITH_ALTERED_SEARCH_PATH) succeeds: the renderer and its
#      import closure load from the package alone. This is the closure half of the check. The name-resolution half
#      (the exe's own Bridge.load() with no path) needs the packaged exe to run; the packaged BridgeSmoke step in R5
#      does that on the Windows Sandbox / Dell desktop under the same scrubbed environment.
param(
    [ValidateSet('Stage', 'Installed')][string]$Mode = 'Stage',
    [string]$Root = '',
    [string]$PackageName = 'OrthicLabs.SliceApp'
)
$ErrorActionPreference = 'Stop'
$app = Resolve-Path (Join-Path $PSScriptRoot '..')
$pin = Get-Content (Join-Path $app 'Windows\renderer-pin.json') -Raw | ConvertFrom-Json
if (-not $Root) {
    if ($Mode -eq 'Stage') { $Root = Join-Path $app '.build\msix-stage' }
    else {
        $pkg = Get-AppxPackage -Name $PackageName | Select-Object -First 1
        if (-not $pkg) { throw "package $PackageName is not installed" }
        $Root = $pkg.InstallLocation
    }
}
$problems = New-Object System.Collections.Generic.List[string]
$exe = Join-Path $Root 'SliceApp.exe'
$dll = Join-Path $Root $pin.file
if (-not (Test-Path -LiteralPath $exe)) { $problems.Add("SliceApp.exe not found in $Root") }
if (-not (Test-Path -LiteralPath $dll)) { $problems.Add("$($pin.file) is not beside SliceApp.exe in $Root") }
else {
    $actual = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    if ($actual -ne $pin.sha256.ToUpperInvariant()) { $problems.Add("$($pin.file) sha256 $actual != pin $($pin.sha256)") }
}
foreach ($shipped in $pin.closure.shipped) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $shipped))) { $problems.Add("closure entry $shipped missing beside the exe") }
}
$loader = Join-Path $app '..\..\packages\SwiftRightBridge\Sources\SwiftRightBridge\Loader.swift'
if (Test-Path -LiteralPath $loader) {
    if ((Get-Content -LiteralPath $loader -Raw) -notmatch [regex]::Escape("?? `"$($pin.file)`"")) { $problems.Add("Loader.swift default renderer name is not `"$($pin.file)`"") }
} else { "note: Loader.swift not present here; default-name check skipped" }

if ($Mode -eq 'Installed' -and $problems.Count -eq 0) {
    $sys = Join-Path $env:SystemRoot 'System32'
    # The renderer imports comctl32 v6 entry points (Loader.swift: win32 error 127/182 without them), so the probe
    # activates a ComCtl v6 activation context first, exactly what the exe's embedded manifest provides.
    $manifestFile = Join-Path ([IO.Path]::GetTempPath()) 'sliceapp-verify-comctl6.manifest'
    Set-Content -LiteralPath $manifestFile -Encoding UTF8 -Value '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><dependency><dependentAssembly><assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/></dependentAssembly></dependency></assembly>'
    $script = @"
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct ACTCTX { public int cbSize; public uint dwFlags; public string lpSource; public ushort wProcessorArchitecture; public ushort wLangId; public string lpAssemblyDirectory; public string lpResourceName; public string lpApplicationName; public IntPtr hModule; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr CreateActCtxW(ref ACTCTX c);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ActivateActCtx(IntPtr h, out IntPtr cookie);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
}
'@
if (`$env:SWIFTRIGHT_RENDER_DLL) { Write-Output 'FAIL env var still set'; exit 3 }
`$c = New-Object W+ACTCTX; `$c.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]'W+ACTCTX'); `$c.lpSource = '$($manifestFile.Replace("'", "''"))'
`$ctx = [W]::CreateActCtxW([ref]`$c)
if (`$ctx -eq [IntPtr]::Zero -or `$ctx -eq [IntPtr](-1)) { Write-Output 'FAIL CreateActCtx'; exit 5 }
`$cookie = [IntPtr]::Zero; [void][W]::ActivateActCtx(`$ctx, [ref]`$cookie)
`$h = [W]::LoadLibraryExW('$($dll.Replace("'", "''"))', [IntPtr]::Zero, 8)
if (`$h -eq [IntPtr]::Zero) { Write-Output ('FAIL LoadLibraryEx win32 error ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); exit 4 }
Write-Output 'LOADED'
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $sys 'WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = "-NoProfile -NonInteractive -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['Path'] = "$sys;$env:SystemRoot"
    [void]$psi.EnvironmentVariables.Remove('SWIFTRIGHT_RENDER_DLL')
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd().Trim(); [void]$p.StandardError.ReadToEnd(); $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or $out -ne 'LOADED') { $problems.Add("scrubbed-environment load of the renderer failed: $out (exit $($p.ExitCode))") }
    else { "scrubbed-environment load ok (PATH=System32 only, SWIFTRIGHT_RENDER_DLL unset)" }
}
if ($problems.Count -gt 0) { $problems | ForEach-Object { "FAIL: $_" }; exit 1 }
"OK ($Mode): $($pin.file) beside SliceApp.exe in $Root, sha256 matches pin (ABI $($pin.abi))"
