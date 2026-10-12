$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$s='D:\Claude\swiftright\.factory-work\hosts\rectangle'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne 'free'){throw 'desktop not free for stage reuse'}
foreach($v in @(@('plan-final-v4.json','980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8'),@('build-owned-v4.ps1','f88932bcaaeb536f3dd7103b8401221cf1a27384fec75e928ebfd397dac53c7d'))){$f=Join-Path $s $v[0];if((Get-FileHash $f).Hash.ToLowerInvariant() -cne $v[1]){throw 'stage pin drift'}}
$dest=Join-Path $s 'package\plan-final-v4.json';if(Test-Path $dest){throw 'fresh final plan required'};Copy-Item -LiteralPath (Join-Path $s 'plan-final-v4.json') -Destination $dest
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $s 'build-owned-v4.ps1'),[ref]$t,[ref]$e);if($e.Count){throw ($e|Out-String)}
& (Join-Path $s 'build-owned-v4.ps1') -PlanPath $dest -PlanSha256 '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8' -Phase final -Attempt 2
Get-Content -Raw (Join-Path $s 'final-r2\observation.json')
