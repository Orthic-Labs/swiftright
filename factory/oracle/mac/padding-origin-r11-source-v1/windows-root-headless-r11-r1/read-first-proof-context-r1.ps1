$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$producer=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
$issued=Join-Path $producer 'coordinator-single-r1\issued-metadata.json'
function Read-Bounded([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe JSON input'};return [IO.File]::ReadAllText($p)|ConvertFrom-Json}
$m=Read-Bounded $issued;$tuple=Read-Bounded $m.candidateTuple.path;$context=Read-Bounded $m.candidateContext.path
$rows=@()
foreach($r in @($context.macContext.sourceRefs)){
 $observed=@()
 foreach($base in @($repo,$producer,(Join-Path $repo '.factory-work\windows-replay-r11'))){
  $p=if([IO.Path]::IsPathRooted($r.path)){$r.path}else{[IO.Path]::GetFullPath((Join-Path $base ($r.path -replace '/','\')))}
  $exists=Test-Path -LiteralPath $p -PathType Leaf;$ref=$null
  if($exists){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe context ref'};$ref=@{path=$p;bytes=$i.Length;sha256=('sha256:'+(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant())}}
  $observed+=@{base=$base;path=$p;exists=$exists;actual=$ref}
 }
 $rows+=@{expected=$r;observed=$observed}
}
[ordered]@{kind='root-first-proof-context-observation-v1';issuedPath=$issued;issuedHash=(Get-FileHash -LiteralPath $issued).Hash.ToLowerInvariant();tuplePath=$m.candidateTuple.path;contextPath=$m.candidateContext.path;rows=$rows;nativeWindowActions=0;compilerActions=0;guiActions=0;lockActions=0}|ConvertTo-Json -Depth 16
