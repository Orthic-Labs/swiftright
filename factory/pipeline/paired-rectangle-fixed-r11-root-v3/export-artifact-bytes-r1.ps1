$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$rows=@(
 @{role='compiler';path='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe';sha='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'},
 @{role='exe';path='D:\Claude\swiftright\.factory-work\hosts\rectangle\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe';sha='62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66'},
 @{role='renderer';path='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll';sha='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'}
)
$out=@();$total=0
foreach($r in $rows){$i=Get-Item -LiteralPath $r.path -Force;if($i.Length -gt 67108864 -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'artifact exceeds explicit bound'};$total+=$i.Length;if($total -gt 134217728){throw 'artifact total bound'};$sha=(Get-FileHash -LiteralPath $r.path).Hash.ToLowerInvariant();if($sha -cne $r.sha){throw ('artifact lineage changed '+$r.role)};$out+=@{role=$r.role;path=$r.path;bytes=$i.Length;sha256=$sha}}

$root='D:\Claude\swiftright\.factory-work\root-tools\rectangle-artifact-export-r1';if(Test-Path -LiteralPath $root){throw 'fresh artifact export required'};New-Item -ItemType Directory -Path $root|Out-Null
$files=@();foreach($r in $out){$name=if($r.role -eq 'renderer'){'artifacts/renderer.dll'}elseif($r.role -eq 'exe'){'artifacts/host.exe'}else{'artifacts/swift.exe'};$files+=@{path=$name;originalPath=$r.path;bytes=$r.bytes;sha256=$r.sha256;role=$r.role}}
$manifest=Join-Path $root 'manifest.json';@{kind='factory-rectangle-explicit-artifact-export-v1';files=$files;count=3;totalBytes=$total;qualified=$false}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $manifest -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $root 'artifact-bytes.zip';$stream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $files){$e=$archive.CreateEntry($row.path);$dst=$e.Open();$src=[IO.File]::OpenRead($row.originalPath);try{$src.CopyTo($dst,1048576)}finally{$src.Dispose();$dst.Dispose()}};$e=$archive.CreateEntry('export-manifest.json');$dst=$e.Open();$src=[IO.File]::OpenRead($manifest);try{$src.CopyTo($dst,1048576)}finally{$src.Dispose();$dst.Dispose()}}finally{$archive.Dispose();$stream.Dispose()}
$i=Get-Item -LiteralPath $zip;if($i.Length -gt 32MB){throw 'artifact zip bound'}
@{status='exported';zipPath=$zip;zipBytes=$i.Length;zipSha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();files=3;bytes=$total;qualified=$false}|ConvertTo-Json -Depth 6

