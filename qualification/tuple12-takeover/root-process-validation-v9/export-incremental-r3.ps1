$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$stage=Join-Path $repo '.work\sr0-incremental-v9-evidence-r1';$zip=Join-Path $repo '.work\sr0-incremental-v9-evidence-r3.zip'
if(Test-Path -LiteralPath $zip){throw 'Fresh ZIP required'}
$manifestPath=Join-Path $stage 'manifest.json';$i=Get-Item -LiteralPath $manifestPath;if($i.Length -gt 1MB){throw 'Manifest bound'};$m=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json
if($m.kind -cne 'root-sr0-incremental-v9-export-v1' -or @($m.files).Count -ne 15){throw 'Exact source inventory required'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$z=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($r in @($m.files)+@(@{path='manifest.json';bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant()})){
 if($r.path.StartsWith('/') -or $r.path.Contains('..') -or $r.path.Contains('\') -or $r.path.Contains(':')){throw 'Unsafe ZIP path'}
 $p=Join-Path $stage $r.path;$item=Get-Item -LiteralPath $p;if($item.Length -gt 8MB -or $item.Length -ne $r.bytes -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Sealed source drift'}
 $entry=$z.CreateEntry([string]$r.path,[IO.Compression.CompressionLevel]::Optimal);$dst=$entry.Open();$src=[IO.File]::OpenRead($p);try{$src.CopyTo($dst,81920)}finally{$src.Dispose();$dst.Dispose()}
}}finally{$z.Dispose();$stream.Dispose()}
[ordered]@{zipPath=$zip;sha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $zip).Length;files=@($m.files).Count;nativeActions=0;lockActions=0;deleted=$false}|ConvertTo-Json
