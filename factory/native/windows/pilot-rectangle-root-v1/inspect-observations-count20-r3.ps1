$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$f='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\native\count20-r3\native-observation.json'
if((Get-Item $f).Length -gt 1MB){throw 'observation bound'}
$d=Get-Content -Raw $f|ConvertFrom-Json
$d|Select-Object -First 2|ConvertTo-Json -Depth 8
@{count=@($d).Count;invalid=@($d|Where-Object{$_.hostValid -ne $true}).Count;foreground=@($d|Where-Object{$_.probeForegroundAtCapture -ne $false}).Count;backgroundAbsent=@($d|Where-Object{$_.backgroundPlacementRequested -ne $true}).Count}|ConvertTo-Json
