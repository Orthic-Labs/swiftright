$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\windows-replay-r11\r16';$zip='D:\Claude\swiftright\.factory-work\windows-replay-r11-r16-headless-r1.zip'
if(Test-Path -LiteralPath $zip){throw 'Fresh export required'}
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
$rows=@();$total=0;$watch=[Diagnostics.Stopwatch]::StartNew();$files=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force)
if($files.Count -gt 512){throw 'Export inventory bound'}
foreach($f in $files){if($watch.Elapsed.TotalSeconds -gt 60 -or $f.Length -gt 2MB -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Export input bound'};$total+=$f.Length;if($total -gt 16MB){throw 'Export aggregate bound'};$rows += [ordered]@{path=$f.FullName.Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();bytes=$f.Length}}
$manifest=[ordered]@{kind='root-factory-headless-v16-export-v1';files=$rows;totalBytes=$total;fileCount=$rows.Count;nativeWindowActions=0;compilerActions=0;lockActions=0;lockState=[IO.File]::ReadAllText('D:\Claude\desktop.lock').Trim()}
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($r in $rows){$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $r.path),$r.path,[IO.Compression.CompressionLevel]::Optimal)};$e=$archive.CreateEntry('manifest.json');$s=$e.Open();try{$b=[Text.UTF8Encoding]::new($false).GetBytes(($manifest|ConvertTo-Json -Depth 8));$s.Write($b,0,$b.Length)}finally{$s.Dispose()}}finally{$archive.Dispose()}
[ordered]@{zipPath=$zip;sha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $zip).Length;files=$rows.Count;totalBytes=$total;nativeWindowActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
