$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-r4'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r6'
$terminal=Get-Content -Raw (Join-Path $root 'collector-receipt.json')|ConvertFrom-Json
if(-not $terminal.lockReleased -or -not $terminal.activeSelfOnly -or -not $terminal.presentMonSessionAbsent -or -not $terminal.workloadTerminal -or -not $terminal.presentMonTerminal){throw 'terminal diagnostic release required'}
$rows=@();$total=0
foreach($f in Get-ChildItem -LiteralPath $root -Recurse -File){
 if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 8MB -or $rows.Count -ge 256){throw 'bounded diagnostic export'}
 $total+=$f.Length;if($total -gt 32MB){throw 'diagnostic total bound'}
 $rows+=@{path=$f.FullName.Substring($root.Length+1).Replace('\','/');bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();originalPath=$f.FullName}
}
$m=Join-Path $stage 'diagnostic-r4-manifest.json';if(Test-Path $m){throw 'fresh manifest required'}
@{kind='sr0-display-native-diagnostic-raw-export-v1';qualification=$false;files=$rows;totalBytes=$total;lockReleased=$true;nativeActions=0}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $m -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $stage 'diagnostic-r4.zip';$s=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$a=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $rows){$e=$a.CreateEntry($row.path);$o=$e.Open();$i=[IO.File]::OpenRead($row.originalPath);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}};$e=$a.CreateEntry('export-manifest.json');$o=$e.Open();$i=[IO.File]::OpenRead($m);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}}finally{$a.Dispose();$s.Dispose()}
@{status='exported';zipPath=$zip;zipBytes=(Get-Item $zip).Length;zipSha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();files=$rows.Count;bytes=$total;qualification=$false}|ConvertTo-Json
