$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.work\sr0-f1-smoke-v1'
$src='D:\Claude\swiftright\.work\sr0-stage-inputs\drive-fixture-noactivate-focus-r1.ps1';$driver=Join-Path $stage 'drive-fixture-noactivate-focus-r1.ps1'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '1e102040d1c4c8de647a1e6d7880ec2b60d174479e355b03327db50e0fb02780'){throw 'focus overlay source drift'}
if(Test-Path -LiteralPath $driver){throw 'exclusive focus overlay exists'}
[IO.File]::Copy($src,$driver,$false)
foreach($pair in @(@('worker.ps1','e0ae2397352cfee0090303e9cf3231bab26e110aa6b0125eed779806f8e383ae'),@('coordinator.ps1','8b5be32797507a5b54745b8e0b9da52d3d5942529f2756c0236149dcf83bbbfe'),@('drive-fixture-noactivate-focus-r1.ps1','1e102040d1c4c8de647a1e6d7880ec2b60d174479e355b03327db50e0fb02780'))){$f=Join-Path $stage $pair[0];if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $pair[1]){throw 'smoke source drift'};$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw 'actual smoke parser failed'}}
& (Join-Path $stage 'coordinator.ps1') -Base 'D:\Claude\swiftright\.work\sr0-r12-typecheck\src' -Worker (Join-Path $stage 'worker.ps1') -Driver $driver -ExpectExe '87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374' -ExpectDll '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' -OutRoot 'D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v2'
