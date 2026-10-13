$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\factory\native\windows\.work\text-baseline-r11-v2'
$control=Join-Path $base 'control-count1-r5';$run=Join-Path $base 'native\count1-r5'
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne 'free'){throw 'diagnostic export requires released desktop'}
$r=Get-Content -Raw (Join-Path $control 'coordinator.json')|ConvertFrom-Json
if($r.lockReleased -ne $true){throw 'diagnostic ownership reconciliation missing'}
foreach($path in @((Join-Path $control 'task-start.json'),(Join-Path $run 'native-01\final-start.json'))){
 $old=Get-Content -Raw $path|ConvertFrom-Json;$live=Get-Process -Id $old.pid -ErrorAction SilentlyContinue
 if($live -and $live.Path -ceq $old.path -and $live.StartTime.ToUniversalTime().ToString('o') -ceq $old.startedAt){throw 'original owned identity still live'}
}
$files=@();$total=0
foreach($g in @(@{name='control';root=$control},@{name='native';root=$run},@{name='admission';root=(Join-Path $base 'admission-count1-r5')})){
 foreach($f in Get-ChildItem -LiteralPath $g.root -Recurse -File){if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 4MB){throw 'diagnostic export file bound'};$total+=$f.Length;if($files.Count -ge 256 -or $total -gt 16MB){throw 'diagnostic export total bound'};$files+=@{path=($g.name+'/'+$f.FullName.Substring($g.root.Length+1).Replace('\','/'));originalPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash $f.FullName).Hash.ToLowerInvariant()}}
}
$manifest=Join-Path $control 'diagnostic-export-manifest-r5.json';if(Test-Path $manifest){throw 'fresh diagnostic manifest required'}
@{kind='factory-failed-native-diagnostic-export-v1';files=$files;totalBytes=$total;count=$files.Count;qualified=$false;originalParentAtLaunchCertificate=$true;lockReleased=$true;captureStatus='failed-worker-process-lookup'}|ConvertTo-Json -Depth 12|Set-Content $manifest -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip='D:\Claude\swiftright\.factory-work\hosts\text\failed-count1-r5.zip';$s=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$a=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $files){$e=$a.CreateEntry($row.path);$o=$e.Open();$i=[IO.File]::OpenRead($row.originalPath);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}};$e=$a.CreateEntry('export-manifest.json');$o=$e.Open();$i=[IO.File]::OpenRead($manifest);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}}finally{$a.Dispose();$s.Dispose()}
@{status='diagnostic-exported';zipPath=$zip;zipBytes=(Get-Item $zip).Length;zipSha256=(Get-FileHash $zip).Hash.ToLowerInvariant();files=$files.Count;bytes=$total;qualified=$false}|ConvertTo-Json
