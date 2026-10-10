# Read-only targeted stage inventory: no windows, lock mutation, stage mutation or DLL loading.
$ErrorActionPreference = 'Stop'
$root = 'D:\Claude\sr0-r09'
$relative = @('renderer\swiftright_render.dll','src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe','smoke\bin\BridgePixels.exe','workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe','src\probes\sr0-s\fresh-runtime\Package.swift','src\packages\SwiftRightBridge\Package.swift','src\render\swiftright-abi\include\swiftright.h')
$os = Get-CimInstance Win32_OperatingSystem
[ordered]@{
 kind='windows-stage-inventory';version='0.1';observedAt=[DateTimeOffset]::UtcNow.ToString('o');stage=$root
 sourceCommit=(& git -C (Join-Path $root 'src') rev-parse HEAD).Trim()
 desktopLock=[ordered]@{path='D:\Claude\desktop.lock';state=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim();acquired=$false}
 os=[ordered]@{caption=$os.Caption;version=$os.Version;build=$os.BuildNumber}
 session=[ordered]@{collectorSessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;query=@(& qwinsta | ForEach-Object {[string]$_});dpi='not-measured-services-session'}
 files=@($relative|ForEach-Object{$p=Join-Path $root $_;if(Test-Path -LiteralPath $p){$f=Get-Item -LiteralPath $p;[ordered]@{path=$p;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}}})
 tools=@('swift','clang','clang-cl','python','rightkit'|ForEach-Object{$c=Get-Command $_ -ErrorAction SilentlyContinue;if($c){[ordered]@{name=$_;path=$c.Source}}})
 swiftVersion=(& swift --version | Out-String).Trim()
 windowedRunPerformed=$false;stageModified=$false
} | ConvertTo-Json -Depth 8
