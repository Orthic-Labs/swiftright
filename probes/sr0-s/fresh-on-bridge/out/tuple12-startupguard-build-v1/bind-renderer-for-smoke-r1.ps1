$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$source='D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll'
$bin='D:\Claude\swiftright\.work\sr0-r12-typecheck\src\scratch\out\Products\Release-windows-x86_64'
$dest=Join-Path $bin 'swiftright_render.dll';$exe=Join-Path $bin 'FreshOnBridge.exe'
if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' -or (Get-Item -LiteralPath $source).Length -ne 11887616){throw 'admitted renderer source drift'}
if((Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne '87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374' -or (Get-Item -LiteralPath $exe).Length -ne 4758016){throw 'actual compiled fixture drift'}
$busy=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -ieq $exe -or $_.CommandLine -like '*sr0-r12-typecheck*swift build*'});if($busy.Count){throw 'candidate native/build process active'}
if(Test-Path -LiteralPath $dest){if((Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2'){throw 'existing same-bin renderer differs'}}else{[IO.File]::Copy($source,$dest,$false)}
@{kind='root-sr0-actual-same-bin-binding-v1';exe=@{path=$exe;bytes=(Get-Item -LiteralPath $exe).Length;sha256=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()};renderer=@{path=$dest;bytes=(Get-Item -LiteralPath $dest).Length;sha256=(Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant()};ownedProcesses=0;nativeActions=0}|ConvertTo-Json -Depth 8
