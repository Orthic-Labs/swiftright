$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r6'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4'
$names=@('observer-r6.json','observer-r6.json.schedule.stdout.bin','observer-r6.json.schedule.stderr.bin')
$files=@();$total=0
foreach($n in $names){$f=Join-Path $root $n;if(Test-Path $f){$i=Get-Item -LiteralPath $f;if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt 2MB){throw 'observer export bound'};$total+=$i.Length;$files+=@{path=$n;originalPath=$f;bytes=$i.Length;sha256=(Get-FileHash $f).Hash.ToLowerInvariant()}}}
if($files.Count -eq 0 -or $total -gt 8MB){throw 'observer export inventory'}
$m=Join-Path $stage 'observer-final-export-r1.json';if(Test-Path $m){throw 'fresh observer manifest required'}
@{kind='sr0-observer-final-diagnostic-v1';files=$files;totalBytes=$total;qualification=$false}|ConvertTo-Json -Depth 10|Set-Content $m -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $stage 'observer-final-export-r1.zip';$s=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$a=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $files){$e=$a.CreateEntry($row.path);$o=$e.Open();$i=[IO.File]::OpenRead($row.originalPath);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}};$e=$a.CreateEntry('export-manifest.json');$o=$e.Open();$i=[IO.File]::OpenRead($m);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}}finally{$a.Dispose();$s.Dispose()}
@{status='exported';zipPath=$zip;zipBytes=(Get-Item $zip).Length;zipSha256=(Get-FileHash $zip).Hash.ToLowerInvariant();files=$files.Count;bytes=$total;qualification=$false}|ConvertTo-Json
