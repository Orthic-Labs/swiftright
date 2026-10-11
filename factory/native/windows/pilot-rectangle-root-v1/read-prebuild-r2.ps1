$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle\prebuild-r2'
$out=[ordered]@{kind='root-rectangle-prebuild-raw-read-v1';files=@();compilerActions=0;nativeActions=0}
foreach($name in @('observation.json','compile.stdout.bin','compile.stderr.bin')){$p=Join-Path $root $name;$item=Get-Item -LiteralPath $p;if($item.Length -gt 131072){throw 'bounded raw read limit'};$b=[IO.File]::ReadAllBytes($p);$out.files+=@{name=$name;bytes=$b.Length;sha256=(Get-FileHash $p).Hash.ToLowerInvariant();base64=[Convert]::ToBase64String($b)}}
$out|ConvertTo-Json -Depth 10
