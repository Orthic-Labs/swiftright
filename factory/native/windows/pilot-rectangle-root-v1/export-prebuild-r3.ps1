$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$exe=Join-Path $root 'package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe'
if((Get-FileHash $exe).Hash.ToLowerInvariant() -cne '62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66'){throw 'exact measured executable required'}
$zip='D:\Claude\swiftright\.factory-work\rectangle-prebuild-r3-evidence.zip'
$temp=Join-Path $root 'export-prebuild-r3'
if((Test-Path $zip) -or (Test-Path $temp)){throw 'fresh export required'}
New-Item -ItemType Directory $temp|Out-Null
$names=@('prebuild-r1/observation.json','prebuild-r1/compile.stdout.bin','prebuild-r1/compile.stderr.bin','prebuild-r2/observation.json','prebuild-r2/compile.stdout.bin','prebuild-r2/compile.stderr.bin','prebuild-r3/observation.json','prebuild-r3/compile.stdout.bin','prebuild-r3/compile.stderr.bin','package/build-bound-r1/scratch/out/Products/Release-windows-x86_64/FactoryProbe.exe','package/plan-prebuild-v3.json')
$rows=@();$total=0
foreach($name in $names){$src=Join-Path $root $name;$i=Get-Item -LiteralPath $src;$total+=$i.Length;if($i.Length -gt 8388608 -or $total -gt 16777216 -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'explicit export cap'};$dst=Join-Path $temp $name;New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($dst)) -Force|Out-Null;Copy-Item -LiteralPath $src -Destination $dst;$rows+=@{path=$name;bytes=$i.Length;sha256=(Get-FileHash $dst).Hash.ToLowerInvariant()}}
@{kind='root-explicit-rectangle-prebuild-archive-v1';files=$rows;totalBytes=$total;nativeActions=0}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $temp 'manifest.json') -Encoding UTF8
Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zip
@{zipPath=$zip;bytes=(Get-Item $zip).Length;sha256=(Get-FileHash $zip).Hash.ToLowerInvariant();fileCount=$names.Count;nativeActions=0}|ConvertTo-Json
