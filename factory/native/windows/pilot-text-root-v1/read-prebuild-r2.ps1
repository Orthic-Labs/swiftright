$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
foreach($n in @('observation.json','compile.stdout.bin','compile.stderr.bin')){$f=Join-Path $stage ('prebuild-r2\'+$n);if((Get-Item $f).Length -gt 2MB){throw 'diagnostic bound'};Write-Output $n;Get-Content -Raw $f}
