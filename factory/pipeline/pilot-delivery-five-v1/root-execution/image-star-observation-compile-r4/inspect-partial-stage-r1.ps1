$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
$saved=Join-Path $stage 'source-before-retry-r4'
$rows=@()
foreach($p in @((Join-Path $stage 'build-owned-pilot-v1.ps1'),(Join-Path $stage 'Sr0OwnedJobProcess.cs'),(Join-Path $saved 'build-owned-pilot-v1-r2.ps1'),(Join-Path $saved 'Sr0OwnedJobProcess-r2.cs'),(Join-Path $saved 'archive-manifest.json'))){
 $f=Get-Item -LiteralPath $p; if($f.Length -gt 131072 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded file required'}
 $rows+=@{path=$p;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))}
}
@{kind='factory-image-partial-stage-readonly-v1';rows=$rows;lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();processes=@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue|Select-Object Id,ProcessName)}|ConvertTo-Json -Depth 7
