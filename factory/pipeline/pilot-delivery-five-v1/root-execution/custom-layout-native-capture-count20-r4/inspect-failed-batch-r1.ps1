$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors\captures\count20-r4'
$run=Join-Path $root 'native\count20-r1';$dirs=@(Get-ChildItem -LiteralPath $run -Directory|Where-Object{$_.Name -match '^native-\d{2}$'}|Sort-Object Name)
if($dirs.Count -gt 20){throw 'run directory cap'}
$paths=@((Join-Path $root 'control-count20-r4\coordinator.json'),(Join-Path $root 'control-count20-r4\task-result.json'),(Join-Path $run 'observation.json'))
foreach($d in @($dirs|Select-Object -Last 2)){foreach($name in @('capture-outcome.json','native-observation.json','launch-observation.json','lifecycle-timing.json','final-exit-certificate.json','host.stdout.txt','host.stderr.txt','native.pixels.json')){$p=Join-Path $d.FullName $name;if(Test-Path -LiteralPath $p){$paths+=@($p)}}}
$rows=@();$total=0
foreach($p in $paths){if(-not(Test-Path -LiteralPath $p)){continue};$f=Get-Item -LiteralPath $p;$total+=$f.Length;if($f.Length -gt 262144 -or $total -gt 1048576 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'diagnostic file budget'};$rows+=@{path=$p;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))}}
@{kind='factory-failed-native-batch-diagnostic-v1';runDirectories=@($dirs.Name);lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();processes=@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue|Select-Object Id,ProcessName);rows=$rows;qualified=$false}|ConvertTo-Json -Depth 8
