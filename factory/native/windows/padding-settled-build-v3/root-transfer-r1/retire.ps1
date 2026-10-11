$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$owned=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) })
if($owned.Count){throw 'Owned stage has active process'}
$old='D:\Claude\_factory-old-DELETE-ME\padding-controls-r2-20261011'
if(Test-Path -LiteralPath $old){throw 'Retirement destination exists'}
New-Item -ItemType Directory -Path $old | Out-Null
$moved=@()
foreach($name in @('control-results','stream-control-results','stream-parse.json','stream-admission-faults','json-array-controls')){
 $from=Join-Path $root $name
 if(Test-Path -LiteralPath $from){Move-Item -LiteralPath $from -Destination (Join-Path $old $name);$moved+=$name}
}
@{stage=$root;retired=$old;moved=$moved;activeOwnedProcesses=0;deleted=0}|ConvertTo-Json -Depth 5
