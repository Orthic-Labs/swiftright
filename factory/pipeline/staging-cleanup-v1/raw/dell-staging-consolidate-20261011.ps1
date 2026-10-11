$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$paths=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('WyJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtYXBpLTA4ZDZjZTZiLTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1hcGktMjIxNzJmZjItMjAyNjEwMTEiLCAiRDpcXENsYXVkZVxcZmFjdG9yeS1zd2lmdHJpZ2h0LWFwaS1mNzc0NWQ0NS0yMDI2MTAxMSIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtYmFzZWxpbmUtOGU0N2I4OS0yMDI2MTAxMSIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtY29weWNvc3QtaW5wdXQtNDZlMDM5YWJiNzQ2IiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1jb3B5Y29zdC1vYnNlcnZlLTQ2ZTAzOWFiYjc0NiIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtY29weWNvc3QtcnVuLTQ2ZTAzOWFiYjc0NiIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtZmluYWwtNjdiODQxZmItMjAyNjEwMTEiLCAiRDpcXENsYXVkZVxcZmFjdG9yeS1zd2lmdHJpZ2h0LWZpbmFsLTkwNjAzNDVhLTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1mb250LTM3NDI5MTIwLTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1ob3RwYXRoLWExZWMxZmUzLTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1wZXJmcGhhc2UtaW5wdXQtdjEtMjAyNjEwMTEiLCAiRDpcXENsYXVkZVxcZmFjdG9yeS1zd2lmdHJpZ2h0LXBlcmZwaGFzZS1pbnB1dC12My0yMDI2MTAxMSIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtcGVyZnBoYXNlLWlucHV0LXY0LTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC1wZXJmcGhhc2UtcGFpci12MS0yMDI2MTAxMSIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtcGVyZnBoYXNlLXBhaXItdjItMjAyNjEwMTEiLCAiRDpcXENsYXVkZVxcZmFjdG9yeS1zd2lmdHJpZ2h0LXNoYXBlLWJiY2ViNWExLTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC10YXNraWQtYmFzZWxpbmUtOGU0Ny0yMDI2MTAxMSIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtdGFza2lkLXRocmVlLWlucHV0LTIwMjYxMDExIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC10YXNraWQtdGhyZWUtaW5wdXQtZGlyZWN0LXNjcC0yMDI2MTAxMS0xMTUzIiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC10YXNraWQtdGhyZWUtaW5wdXQtZGlyZWN0LXNjcC12Mi0yMDI2MTAxMS0xMjA3IiwgIkQ6XFxDbGF1ZGVcXGZhY3Rvcnktc3dpZnRyaWdodC10YXNraWQtdGhyZWUtcnVuLWRpcmVjdC1zY3AtdjItMjAyNjEwMTEtMTIwNyIsICJEOlxcQ2xhdWRlXFxmYWN0b3J5LXN3aWZ0cmlnaHQtdGFza2lkLXRyYWNlLTIwMjYxMDExIl0=')))
$archive='D:\Claude\swiftright\.factory-archive\staging-20261011'
$processes=@(Get-CimInstance Win32_Process)
$tasks=@(Get-ScheduledTask)
foreach($p in $paths){
 if(-not(Test-Path -LiteralPath $p -PathType Container)){throw "Missing owned source $p"}
 $item=Get-Item -LiteralPath $p
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse point $p"}
 $dest=Join-Path $archive $item.Name
 if(Test-Path -LiteralPath $dest){throw "Archive collision $dest"}
 foreach($proc in $processes){if(($proc.ExecutablePath -and $proc.ExecutablePath.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase)) -or ($proc.CommandLine -and $proc.CommandLine.IndexOf($p,[StringComparison]::OrdinalIgnoreCase)-ge 0)){throw "Active process references $p"}}
 foreach($task in $tasks){foreach($action in $task.Actions){$s=[string]$action.Execute+' '+[string]$action.Arguments+' '+[string]$action.WorkingDirectory;if($task.State -eq 'Running' -and $s.IndexOf($p,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "Running task references $p"}}}
}
[IO.Directory]::CreateDirectory($archive)|Out-Null
$rows=@()
foreach($p in $paths){$dest=Join-Path $archive ([IO.Path]::GetFileName($p));[IO.Directory]::Move($p,$dest);if((Test-Path -LiteralPath $p)-or -not(Test-Path -LiteralPath $dest -PathType Container)){throw "Move verification failed $p"};$rows+=[pscustomobject]@{from=$p;to=$dest;status='moved-preserving-bytes'}}
$receipt=[pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');operation='same-volume-directory-move';deletedFiles=0;moved=$rows;retainedActiveRuntime='D:\Claude\factory-swiftright-module-origin-37429120-20261011';remainingRootFolders=@(Get-ChildItem -LiteralPath 'D:\Claude' -Directory | Where-Object {$_.Name -like 'factory-swiftright-*'}|Select-Object -ExpandProperty Name)}
$json=$receipt|ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $archive 'relocation.json'),$json,(New-Object Text.UTF8Encoding($false)))
$json
