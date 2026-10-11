param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$factory='D:\Claude\swiftright\factory\native\windows\'
$configPath=[IO.Path]::GetFullPath($Config)
if(-not $configPath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside factory'}
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$status='hold-harness-error';$errorText=''
try{
 & (Join-Path $PSScriptRoot 'capture-corrected.ps1') -Package $c.package -LockOwner $c.owner -RunRoot $c.runRoot -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash *> (Join-Path $c.runRoot 'task.log')
 $status='captured-single-observational-uia-printwindow'
}catch{$errorText=[string]$_}
[ordered]@{status=$status;error=$errorText;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'task-result.json')
