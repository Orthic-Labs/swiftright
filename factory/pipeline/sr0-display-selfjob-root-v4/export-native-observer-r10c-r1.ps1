$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r10'
$out='D:\Claude\swiftright\.factory-work\root-tools\sr0-native-r10c-export-r1';if(Test-Path $out){throw 'fresh export required'};[IO.Directory]::CreateDirectory($out)|Out-Null
$rows=[Collections.Generic.List[object]]::new();$files=[Collections.Generic.List[object]]::new();$total=[long]0
function AddFile([string]$source,[string]$rel){
 $i=Get-Item -LiteralPath $source -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt 8388608){throw 'bounded regular export file required'}
 $script:total+=$i.Length;if($script:total -gt 33554432 -or $files.Count -ge 1024){throw 'export total bound'}
 $files.Add([pscustomobject]@{source=$i.FullName;path=$rel;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $i.FullName).Hash.ToLowerInvariant()})
}
foreach($name in @('native-observer-r10c.json','native-observer-r10c.json.schedule.stdout.bin','native-observer-r10c.json.schedule.stderr.bin','one-shot-manifest.json','drain-controls-r10.json','staged-controls-gate-r10c.json')){$p=Join-Path $root $name;if(Test-Path $p -PathType Leaf){AddFile $p ('control/'+$name)}}
AddFile 'D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r10\one-run-plan-r8.json' 'control/plan.json'
AddFile 'D:\Claude\desktop.lock' 'control/desktop.lock'
$run=Join-Path $root 'run';if(Test-Path $run -PathType Container){foreach($i in @(Get-ChildItem -LiteralPath $run -File -Recurse|Sort-Object FullName)){$rel=$i.FullName.Substring($run.Length).TrimStart('\').Replace('\','/');AddFile $i.FullName ('run/'+$rel)}}
$manifest=[ordered]@{totalBytes=$total;files=@($files|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})}
$mf=Join-Path $out 'export-manifest.json';$manifest|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $mf -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zp=Join-Path $out 'raw.zip';$zip=[IO.Compression.ZipFile]::Open($zp,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($f in $files){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.source,$f.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null;if((Get-Item $f.source).Length -ne $f.bytes -or (Get-FileHash $f.source).Hash.ToLowerInvariant() -cne $f.sha256){throw 'source drift during export'}};[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$mf,'export-manifest.json')|Out-Null}finally{$zip.Dispose()}
$zi=Get-Item -LiteralPath $zp;if($zi.Length -gt 33554432){throw 'zip bound'}
[ordered]@{status='exported';files=$files.Count;bytes=$total;zipPath=$zp;zipBytes=$zi.Length;zipSha256=(Get-FileHash $zp).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8
