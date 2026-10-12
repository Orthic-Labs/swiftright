$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-v5f'
$control=Join-Path $base 'control-count1-r5';$run=Join-Path $base 'native\count1-r5'
$files=@();$total=0
foreach($g in @(@{name='control';root=$control},@{name='native';root=$run},@{name='admission';root=(Join-Path $base 'admission-count1-r5')})){
 foreach($f in Get-ChildItem -LiteralPath $g.root -Recurse -File){if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 4MB){throw 'export file bound'};$total+=$f.Length;if($files.Count -ge 256 -or $total -gt 16MB){throw 'export total bound'};$files+=@{path=($g.name+'/'+$f.FullName.Substring($g.root.Length+1).Replace('\','/'));originalPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash $f.FullName).Hash.ToLowerInvariant()}}
}
$r=Get-Content -Raw (Join-Path $control 'coordinator.json')|ConvertFrom-Json
$manifest=Join-Path $control 'export-diagnostic-r1.json';if(Test-Path $manifest){throw 'fresh manifest required'}
@{kind='factory-native-observation-export-v1';files=$files;totalBytes=$total;count=$files.Count;qualified=$false;lockReleased=$r.lockReleased;captureStatus=$r.status;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim()}|ConvertTo-Json -Depth 12|Set-Content $manifest -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $control 'export-diagnostic-r1.zip';$s=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$a=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $files){$e=$a.CreateEntry($row.path);$o=$e.Open();$i=[IO.File]::OpenRead($row.originalPath);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}};$e=$a.CreateEntry('export-manifest.json');$o=$e.Open();$i=[IO.File]::OpenRead($manifest);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}}finally{$a.Dispose();$s.Dispose()}
@{status='exported';zipPath=$zip;zipBytes=(Get-Item $zip).Length;zipSha256=(Get-FileHash $zip).Hash.ToLowerInvariant();files=$files.Count;bytes=$total;qualified=$false;lockReleased=$r.lockReleased;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim()}|ConvertTo-Json
