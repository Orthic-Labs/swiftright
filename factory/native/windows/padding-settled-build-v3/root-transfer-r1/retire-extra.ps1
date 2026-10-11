$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
if(@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and $_.ExecutablePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Owned stage active'}
$from=Join-Path $root 'control-fixtures'
$dest='D:\Claude\_factory-old-DELETE-ME\padding-controls-r2-20261011\control-fixtures'
if(Test-Path $dest){throw 'Destination exists'}
if(Test-Path $from){Move-Item -LiteralPath $from -Destination $dest}
@{deleted=0;retired=$dest}|ConvertTo-Json
