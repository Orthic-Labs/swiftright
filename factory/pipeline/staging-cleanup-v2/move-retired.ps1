$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$source='D:\Claude\swiftright\.factory-archive\staging-20261011'
$target='D:\Claude\_factory-old-DELETE-ME'
if(-not(Test-Path -LiteralPath $source -PathType Container)){throw 'Missing archived source'}
if(Test-Path -LiteralPath $target){throw 'Destination exists'}
$item=Get-Item -LiteralPath $source
if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Reparse point source'}
$manifest=Get-Content -LiteralPath (Join-Path $source 'relocation.json') -Raw | ConvertFrom-Json
$children=@(Get-ChildItem -LiteralPath $source -Directory)
if($children.Count -ne 23 -or @($manifest.moved).Count -ne 23){throw 'Unexpected archive contents'}
foreach($child in $children){if(@($manifest.moved|Where-Object {$_.to -ceq $child.FullName}).Count -ne 1){throw 'Unknown archive child'}}
foreach($proc in @(Get-CimInstance Win32_Process)){if(($proc.ExecutablePath -and $proc.ExecutablePath.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) -or ($proc.CommandLine -and $proc.CommandLine.IndexOf($source,[StringComparison]::OrdinalIgnoreCase)-ge 0)){throw 'Active archive reference'}}
Move-Item -LiteralPath $source -Destination $target
if((Test-Path -LiteralPath $source)-or -not(Test-Path -LiteralPath $target -PathType Container)){throw 'Move verification failed'}
[pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');operation='same-volume-move';from=$source;to=$target;retiredDirectories=23;deletedFiles=0;lock=[IO.File]::ReadAllText('D:\Claude\desktop.lock');remainingRootFolders=@(Get-ChildItem -LiteralPath 'D:\Claude' -Directory|Where-Object {$_.Name -like 'factory-swiftright-*'}|Select-Object -ExpandProperty Name)}|ConvertTo-Json -Depth 4
