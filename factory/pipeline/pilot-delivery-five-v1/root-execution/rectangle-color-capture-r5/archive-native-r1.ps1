$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r5';$CountTag='count1-r1';$Zip=Join-Path $Root 'actual-native.zip';$Manifest=Join-Path $Root 'actual-native-manifest.json'
if(Test-Path -LiteralPath $Zip){throw 'fresh native archive required'}
$Co=Get-Content -LiteralPath (Join-Path $Root ('control-'+$CountTag+'\coordinator.json')) -Raw|ConvertFrom-Json
if($Co.status -cne 'completed-source-bound-observation' -or $Co.count -ne 1 -or -not $Co.lockReleased -or -not $Co.wholeBatchExitConfirmed -or @($Co.cleanupErrors).Count -or $Co.taskParentProof.kernelWait -ne 0 -or $Co.taskParentProof.kernelExitCode -ne 0 -or $Co.taskParentProof.dotNetExitCode -ne 0){throw 'fresh native completion required'}
$Rows=@();$Total=0
foreach($Rel in @('control-'+$CountTag,'native\'+$CountTag)){
 foreach($F in @(Get-ChildItem -LiteralPath (Join-Path $Root $Rel) -File -Recurse)){
  $Total+=$F.Length;if($Rows.Count -ge 1600 -or $F.Length -gt 16777216 -or $Total -gt 33554432 -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'archive size/path cap'}
  $Rows+=@{path=$F.FullName.Substring($Root.Length+1).Replace('\','/');bytes=$F.Length;sha256=(Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant()}
 }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Z=[IO.Compression.ZipFile]::Open($Zip,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($R in $Rows){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Z,(Join-Path $Root $R.path),$R.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$Z.Dispose()}
$M=[ordered]@{kind='factory-rectangle-actual-native-archive-v1';root=$Root;count=1;files=$Rows;bytes=$Total;zipBytes=(Get-Item -LiteralPath $Zip).Length;zipSha256=(Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant();sourceHash='sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d';exeHash=$Co.exeHash;compileReceiptHash=$Co.compileReceiptHash;lockReleased=$Co.lockReleased;qualified=$false}
$M|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Manifest -Encoding UTF8
[ordered]@{count=$M.count;files=$Rows.Count;bytes=$Total;manifestSha256=(Get-FileHash -LiteralPath $Manifest).Hash.ToLowerInvariant();zipSha256=$M.zipSha256;qualified=$false}|ConvertTo-Json
