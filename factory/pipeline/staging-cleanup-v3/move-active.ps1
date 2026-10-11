$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$source='D:\Claude\factory-swiftright-module-origin-37429120-20261011'
$target='D:\Claude\swiftright\.factory-work\runtime-stage'
if(-not(Test-Path -LiteralPath $source -PathType Container)){throw 'Missing active staging source'}
if(Test-Path -LiteralPath $target){throw 'Destination exists'}
$item=Get-Item -LiteralPath $source
if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Reparse source'}
$busy=@(Get-CimInstance Win32_Process|Where-Object {($_.ExecutablePath -and $_.ExecutablePath.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) -or ($_.CommandLine -and $_.CommandLine.IndexOf($source,[StringComparison]::OrdinalIgnoreCase)-ge 0)})
if($busy.Count){throw 'Active process references runtime staging'}
foreach($task in @(Get-ScheduledTask|Where-Object {$_.State -eq 'Running'})){foreach($action in $task.Actions){$text=[string]$action.Execute+' '+[string]$action.Arguments+' '+[string]$action.WorkingDirectory;if($text.IndexOf($source,[StringComparison]::OrdinalIgnoreCase)-ge 0){throw 'Running task references runtime staging'}}}
$runtime=Join-Path $source 'runtime'
$files=@(Get-ChildItem -LiteralPath $runtime -File -Recurse|Where-Object {$_.FullName -notmatch '\\(\.build|\.git)\\'})
$before=@($files|ForEach-Object {[pscustomobject]@{path=$_.FullName.Substring($runtime.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bytes=$_.Length}})
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
Move-Item -LiteralPath $source -Destination $target
if((Test-Path -LiteralPath $source)-or -not(Test-Path -LiteralPath $target -PathType Container)){throw 'Move verification failed'}
foreach($row in $before){$actual=Join-Path (Join-Path $target 'runtime') $row.path;if((Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw 'Runtime bytes changed'}}
$git=Join-Path 'D:\Claude\swiftright' '.git'
if(Test-Path -LiteralPath $git -PathType Container){$exclude=Join-Path $git 'info\exclude';[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($exclude))|Out-Null;$old=if(Test-Path -LiteralPath $exclude){[IO.File]::ReadAllText($exclude)}else{''};if($old -notmatch '(?m)^/\.factory-work/$'){[IO.File]::AppendAllText($exclude,"`n/.factory-work/`n",(New-Object Text.UTF8Encoding($false)))}}
[pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');operation='same-volume-move';from=$source;to=$target;deletedFiles=0;verifiedRuntimeFiles=$before;lock=[IO.File]::ReadAllText('D:\Claude\desktop.lock');remainingRootFolders=@(Get-ChildItem -LiteralPath 'D:\Claude' -Directory|Where-Object {$_.Name -like 'factory-swiftright-*'}|Select-Object -ExpandProperty Name)}|ConvertTo-Json -Depth 5
