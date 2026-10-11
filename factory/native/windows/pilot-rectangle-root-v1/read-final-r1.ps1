$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$rows=@();$total=0
foreach($name in @('final-r1/observation.json','final-r1/compile.stdout.bin','final-r1/compile.stderr.bin')) {
 $p=Join-Path $root $name;$i=Get-Item -LiteralPath $p
 $total+=$i.Length
 if($i.Length -gt 1MB -or $total -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Exact final receipt export bound'}
 $rows+=@{path=$name;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))}
}
@{kind='factory-rectangle-final-explicit-byte-export-v1';files=$rows;nativeActions=0;compilerActions=0;lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim()}|ConvertTo-Json -Depth 8
