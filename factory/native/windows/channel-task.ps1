param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$c=Get-Content -Raw $Config|ConvertFrom-Json
try{
 & (Join-Path $PSScriptRoot 'channel-control.ps1') -Config $Config *> (Join-Path $c.runRoot 'task.log')
 if(-not (Test-Path (Join-Path $c.runRoot 'task-result.json'))){throw 'Channel control returned without receipt'}
}catch{
 [ordered]@{status='hold-channel-task-error';error=[string]$_;scriptStackTrace=$_.ScriptStackTrace;finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'task-result.json')
 exit 1
}
