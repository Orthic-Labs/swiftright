[CmdletBinding()]
param([Parameter(Mandatory)][string]$CoordinatorPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $OutputPath) ("coordinator-faults-"+[guid]::NewGuid().ToString('N'))));[IO.Directory]::CreateDirectory($root)|Out-Null
function New-Receipt([string]$Path,[object]$Value){$b=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12)+"`r`n");$s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()}}
function Run-Case([string]$Name,[bool]$WriteStart){
  $case=Join-Path $root $Name;[IO.Directory]::CreateDirectory($case)|Out-Null;$start=Join-Path $case 'start.json';$final=Join-Path $case 'final.json';$out=Join-Path $case 'verdict.json';$lock=Join-Path $case 'lock.txt';New-Receipt $lock @{state='owned'}
  if($WriteStart){New-Receipt $start ([ordered]@{kind='sr0-display-collector-v4-start';status='admitted';taskName='fault';parentPid=0;parentPath='C:\invalid\parent.exe';parentStartTimeUtc='2000-01-01T00:00:00.0000000+00:00';parentHandle=0;parentHandleRetained=$true;sessionMatch=$true;currentSession=1;activeConsoleSession=1;jobMemoryLimitBytes=1073741824;activeProcessCount=1;noActivate=$true})}
  $ps=Join-Path $PSHOME 'powershell.exe';& $ps -NoProfile -ExecutionPolicy Bypass -File $CoordinatorPath -StartReceiptPath $start -FinalReceiptPath $final -OutputPath $out -LockPath $lock -TaskName fault -MaxWaitSeconds 1 -PollSeconds 1 | Out-Null
  if($LASTEXITCODE -eq 0){throw "coordinator fault case unexpectedly passed: $Name"}
  $v=Get-Content -LiteralPath $out -Raw|ConvertFrom-Json;if([string]$v.status -ne 'held'){throw "coordinator fault case not held: $Name"};return [ordered]@{name=$Name;status=[string]$v.status;errors=@($v.errors)}
}
$cases=@((Run-Case 'missing-start' $false),(Run-Case 'invalid-parent' $true))
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out=[ordered]@{kind='sr0-display-coordinator-v4-receipt-controls';status='passed';cases=$cases;nativeActions=0;lockActions=0;guiActions=0;deletions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};$out|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputPath -Encoding UTF8
