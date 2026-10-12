$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\prebuild-r1'
$out='D:\Claude\swiftright\.factory-work\root-tools\circle-close-prebuild-r1-export';if(Test-Path $out){throw 'fresh export required'};[IO.Directory]::CreateDirectory($out)|Out-Null
$files=[Collections.Generic.List[object]]::new();$total=[long]0
foreach($name in @('observation.json','compile.stdout.bin','compile.stderr.bin')){
 $p=Join-Path $root $name;$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt 8388608){throw 'bounded regular export file required'}
 $total+=$i.Length;if($total -gt 33554432){throw 'export total bound'}
 $files.Add([pscustomobject]@{source=$i.FullName;path=$name;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $i.FullName).Hash.ToLowerInvariant()})
}
$manifest=[ordered]@{totalBytes=$total;files=@($files|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})}
$mf=Join-Path $out 'export-manifest.json';$manifest|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $mf -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zp=Join-Path $out 'raw.zip';$zip=[IO.Compression.ZipFile]::Open($zp,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($f in $files){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.source,$f.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null;if((Get-Item $f.source).Length -ne $f.bytes -or (Get-FileHash $f.source).Hash.ToLowerInvariant() -cne $f.sha256){throw 'source drift during export'}};[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$mf,'export-manifest.json')|Out-Null}finally{$zip.Dispose()}
$zi=Get-Item -LiteralPath $zp;if($zi.Length -gt 33554432){throw 'zip bound'}
[ordered]@{status='exported';files=$files.Count;bytes=$total;zipPath=$zp;zipBytes=$zi.Length;zipSha256=(Get-FileHash $zp).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8
