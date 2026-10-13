# Pure path gate used before any capture directory, renderer, lock, or worker action.
function Assert-FreshFactoryWorkerOutputPlan {
 param(
  [Parameter(Mandatory=$true)][string]$NamespaceRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][ValidateRange(1,20)][int]$Count
 )
 $factoryWindowsRoot='D:\Claude\swiftright\factory\native\windows'
 $namespace=[IO.Path]::GetFullPath($NamespaceRoot)
 $run=[IO.Path]::GetFullPath($RunRoot)
 if($namespace -match '[\r\n"]' -or $run -match '[\r\n"]'){throw 'Worker output path contains unsafe control characters'}
 if(-not $namespace.StartsWith($factoryWindowsRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Worker output namespace must be under factory/native/windows'}
 if($namespace -eq $factoryWindowsRoot){throw 'Worker output namespace must be fresh child namespace'}
 if(-not $run.StartsWith($namespace+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Worker run root outside output namespace'}
 if(Test-Path -LiteralPath $run){throw 'Worker run root must be fresh'}
 for($i=1;$i -le $Count;$i++){
  $capture=Join-Path $run ('native-{0:d2}' -f $i)
  $worker=[IO.Path]::GetFullPath((Join-Path $capture 'uia-worker'))
  if(-not $worker.StartsWith($run+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Planned worker path escapes run root'}
  if($worker -match '[\r\n"]' -or $worker -match '\.\.\\'){throw 'Planned worker path is unsafe'}
  if(Test-Path -LiteralPath $worker){throw ('Planned worker output must be absent: '+$worker)}
 }
 return $true
}
