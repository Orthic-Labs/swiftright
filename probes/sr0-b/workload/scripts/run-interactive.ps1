# Run a script file inside the interactive desktop session (one-shot task), wait, print its transcript. Usage: -Script <ps1> -Args '<args>' -Log <txt>
param([string]$Script, [string]$ScriptArgs = '', [string]$Log)
$tn = 'SR0W5Interactive'
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"& '$Script' $ScriptArgs *> '$Log'; 'done' | Add-Content '$Log.done'`""
Remove-Item "$Log.done" -ErrorAction SilentlyContinue
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$pri = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $tn -Action $act -Principal $pri -Force | Out-Null
Start-ScheduledTask -TaskName $tn
$d = (Get-Date).AddSeconds(120); while (-not (Test-Path "$Log.done") -and (Get-Date) -lt $d) { Start-Sleep -Seconds 1 }
Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
Get-Content $Log
