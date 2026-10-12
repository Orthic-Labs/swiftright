$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\.work\sr0-r12-workload-v1';if(-not(Test-Path -LiteralPath $base -PathType Container)){throw 'base missing'}
$files=@(Get-ChildItem -LiteralPath $base -Force|Select-Object Name,Length,PSIsContainer);if($files.Count -gt 80){throw 'top-level inventory cap'}
$bp=Join-Path $base 'build.json';if((Get-Item -LiteralPath $bp).Length -gt 2MB){throw 'build receipt cap'};$b=Get-Content -Raw $bp|ConvertFrom-Json
$paths=@([string]$b.exe,(Join-Path (Split-Path ([string]$b.exe) -Parent) 'swiftright_render.dll'));$rows=@();foreach($p in $paths){if(Test-Path -LiteralPath $p -PathType Leaf){$i=Get-Item $p;if($i.Length -gt 64MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'binary cap'};$rows+=@{path=$p;bytes=$i.Length;sha256=(Get-FileHash $p).Hash.ToLowerInvariant()}}else{$rows+=@{path=$p;missing=$true}}}
@{kind='sr0-v4-explicit-base-inspection';files=$files;build=$b;binaryRows=$rows;nativeActions=0;deletions=0}|ConvertTo-Json -Depth 16
