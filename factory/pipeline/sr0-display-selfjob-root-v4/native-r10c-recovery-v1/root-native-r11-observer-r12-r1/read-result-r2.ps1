$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11'
$p=Join-Path $root 'native-observer-r12.json'
$f=Get-Item -LiteralPath $p -Force
if($f.Length -gt 2097152 -or $f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'observer receipt bound'}
$d=[IO.File]::ReadAllText($p)|ConvertFrom-Json
$run=Join-Path $root 'run'
$files=@(Get-ChildItem -LiteralPath $run -Recurse -File -Force)
if($files.Count -gt 256){throw 'run inventory bound'}
$streams=@()
foreach($field in @('scheduleStdout','scheduleStderr')) {
 $ref=$d.$field
 if($ref) {
  $i=Get-Item -LiteralPath $ref.path -Force
  if($i.Length -le 65536) {
   $streams+=,[pscustomobject]@{name=$field;path=$ref.path;text=[IO.File]::ReadAllText($ref.path)}
  }
 }
}
[pscustomobject]@{path=$p;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();receipt=$d;streams=$streams;lockOwner=[IO.File]::ReadAllText('D:\Claude\desktop.lock').Trim();files=@($files|ForEach-Object{[pscustomobject]@{path=$_.FullName;bytes=$_.Length}})}|ConvertTo-Json -Depth 20
