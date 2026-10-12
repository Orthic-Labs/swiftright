# Prospective Count1 lifecycle overlay. Existing native assertions stay in dispatch/capture/release helpers.
param(
 [Parameter(Mandatory=$true)][string]$Template,
 [Parameter(Mandatory=$true)][string]$TemplateHash,
 [string]$InteractiveTaskPath,
 [int]$SetupSeconds=20,
 [int]$CaptureSeconds=100,
 [int]$CleanupSeconds=20,
 [switch]$PreflightOnly
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Read-BoundedJson([string]$Path){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 2097152){throw 'bounded regular JSON required'}
 return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
}
function Hash([string]$Path){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 2097152){throw 'bounded source required'}
 return (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Write-FreshJson([string]$Path,[object]$Value){
 if(Test-Path -LiteralPath $Path){throw "fresh receipt required: $Path"}
 $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
 if([string]::IsNullOrWhiteSpace($parent) -or -not(Test-Path -LiteralPath $parent -PathType Container)){throw 'receipt parent missing'}
 $tmp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
 try{[IO.File]::WriteAllText($tmp,(($Value|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$Path)}catch{throw} 
}
function Require-Budget([int]$Value,[string]$Name){if($Value -lt 1 -or $Value -gt 600){throw "$Name budget out of bounds"}}
Require-Budget $SetupSeconds 'setup';Require-Budget $CaptureSeconds 'capture';Require-Budget $CleanupSeconds 'cleanup'
$templatePath=[IO.Path]::GetFullPath($Template)
if((Hash $templatePath)-cne $TemplateHash){throw 'template pin mismatch'}
$c=Read-BoundedJson $templatePath
$control=[IO.Path]::GetFullPath([string]$c.controlRoot);$overlay=[IO.Path]::GetFullPath([string]$c.overlayRoot)
if([IO.Path]::GetFullPath($templatePath) -cne (Join-Path $control 'config-template.json')){throw 'template must be fresh Count1 config'}
if($c.count -ne 1){throw 'exact Count1 required'}
if([string]::IsNullOrWhiteSpace($InteractiveTaskPath)){$InteractiveTaskPath=Join-Path $overlay 'interactive-task-rectangle-single-atomic-v2.ps1'}
$interactive=[IO.Path]::GetFullPath($InteractiveTaskPath)
if((Hash $interactive)-ne [string]$c.interactiveTaskHash){throw 'interactive task source drift'}
if($PreflightOnly){
 & (Join-Path $overlay 'dispatch-rectangle-single.ps1') -Package $c.package -LockOwner 'preflight-no-lock' -ProducerRoot $c.producerRoot -AdmissionRoot $c.admissionRoot -ControlRoot $c.controlRoot -OutputRoot $c.outputRoot -IntegrationGuardPath $c.integrationGuardPath -IntegrationGuardHash $c.integrationGuardHash -SourceInputsPath $c.sourceInputsPath -SourceInputsHash $c.sourceInputsHash -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count 1 -RunRoot $c.runRoot -IssuedMetadataPath $c.issuedMetadataPath -IssuedMetadataHash $c.issuedMetadataHash -PreflightOnly
 Write-FreshJson (Join-Path $control 'lifecycle-preflight.json') ([ordered]@{kind='factory-rectangle-count1-lifecycle-preflight-v1';status='passed-source-only';setupSeconds=$SetupSeconds;captureSeconds=$CaptureSeconds;cleanupSeconds=$CleanupSeconds;nativeActions=0;lockActions=0})
 return
}
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class RectangleLifecycleWait { [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h,uint ms); [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h,out uint code); }
'@
$owner='factory-rectangle-'+[Guid]::NewGuid().ToString('N')+' '+[DateTimeOffset]::UtcNow.ToString('o')
$lockPath='D:\Claude\desktop.lock';$taskName='FactoryRectangle-'+[Guid]::NewGuid().ToString('N');$registered=$false;$acquired=$false;$taskParent=$null;$parentHandle=[IntPtr]::Zero;$taskResult=$null;$errorText=$null;$cleanup=@();$phase='setup'
function CAS([string]$Expected,[string]$Replacement){
 try{$s=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false}
 try{if($s.Length -gt 4096){throw 'lock bound'};$reader=[IO.StreamReader]::new($s,[Text.Encoding]::UTF8,$true,1024,$true);try{$old=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()};if($old -cne $Expected){return $false};$bytes=[Text.Encoding]::UTF8.GetBytes($Replacement);$s.Position=0;$s.SetLength(0);$s.Write($bytes,0,$bytes.Length);$s.Flush($true);return $true}finally{$s.Dispose()}
}
try{
 $setupDeadline=[DateTime]::UtcNow.AddSeconds($SetupSeconds);do{$acquired=CAS 'free' $owner;if(-not $acquired){if([DateTime]::UtcNow -gt $setupDeadline){throw 'setup budget exceeded waiting for desktop lock'};Start-Sleep -Milliseconds 250}}until($acquired)
 $c.owner=$owner;$config=Join-Path $control 'config.json';if(Test-Path -LiteralPath $config){throw 'fresh coordinator config required'};Write-FreshJson $config $c
 $argv='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$interactive+'" -Config "'+$config+'"';$vbs=Join-Path $control 'hidden-task.vbs';[IO.File]::WriteAllText($vbs,'Set sh = CreateObject("WScript.Shell")'+[Environment]::NewLine+'rc = sh.Run("powershell.exe '+$argv.Replace('"','""')+'", 0, True)'+[Environment]::NewLine+'WScript.Quit rc',[Text.Encoding]::ASCII)
 $action=New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\wscript.exe') -Argument ('"'+$vbs+'"');$principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest;$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds ($SetupSeconds+$CaptureSeconds+$CleanupSeconds)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings|Out-Null;$registered=$true;Start-ScheduledTask -TaskName $taskName;$phase='capture';$captureDeadline=[DateTime]::UtcNow.AddSeconds($CaptureSeconds)
 do{
  $start=Join-Path $control 'task-start.json';if($null -eq $taskParent -and (Test-Path -LiteralPath $start)){$s=Read-BoundedJson $start;if($s.owner -cne $owner -or $s.issuedMetadataHash -cne $c.issuedMetadataHash -or $s.sourceInputsHash -cne $c.sourceInputsHash){throw 'task start lineage mismatch'};$taskParent=Get-Process -Id $s.pid -ErrorAction Stop;if($taskParent.Path -cne $s.path -or $taskParent.StartTime.ToUniversalTime().ToString('o') -cne $s.startedAt){throw 'task parent identity mismatch'};$parentHandle=$taskParent.Handle}
  $resultPath=Join-Path $control 'task-result.json';if(Test-Path -LiteralPath $resultPath){$taskResult=Read-BoundedJson $resultPath;break};if([DateTime]::UtcNow -gt $captureDeadline){throw 'capture budget exceeded waiting for task result'};Start-Sleep -Milliseconds 100
 }until($false)
 if($null -eq $taskParent -or $parentHandle -eq [IntPtr]::Zero){throw 'original parent handle missing'}
 if($taskResult.owner -cne $owner -or $taskResult.count -ne 1 -or $taskResult.issuedMetadataHash -cne $c.issuedMetadataHash -or $taskResult.compileReceiptHash -cne $c.compileReceiptHash -or $taskResult.exeHash -cne $c.exeHash){throw 'task result identity mismatch'}
 if($taskResult.status -cne 'completed-source-bound-observation'){throw ('capture failed: '+$taskResult.error)}
}catch{$errorText=[string]$_}
finally{
 $phase='cleanup';$cleanupDeadline=[DateTime]::UtcNow.AddSeconds($CleanupSeconds)
 try{if($registered){Disable-ScheduledTask -TaskName $taskName|Out-Null;do{$state=(Get-ScheduledTask -TaskName $taskName).State;if($state -notin @('Running','Queued')){break};if([DateTime]::UtcNow -gt $cleanupDeadline){throw 'cleanup budget exceeded stopping scheduler task'};Start-Sleep -Milliseconds 100}until($false)}}catch{$cleanup+=('scheduler: '+[string]$_)}
 try{if($null -ne $taskParent -and $parentHandle -ne [IntPtr]::Zero){$wait=[RectangleLifecycleWait]::WaitForSingleObject($parentHandle,5000);[uint32]$exit=259;if($wait -ne 0 -or -not[RectangleLifecycleWait]::GetExitCodeProcess($parentHandle,[ref]$exit) -or $exit -eq 259){throw 'original parent kernel terminal proof missing'}}elseif($registered){throw 'task parent proof missing'}}catch{$cleanup+=('parent: '+[string]$_)}
 $canRelease=$acquired -and $null -ne $taskParent -and $cleanup.Count -eq 0
 if($canRelease){try{if(-not(CAS $owner 'free')){$cleanup+='desktop lock release compare-and-swap failed'}}catch{$cleanup+=('lock: '+[string]$_)}}
 $receipt=[ordered]@{kind='factory-rectangle-count1-lifecycle-v1';status=if($errorText -or $cleanup.Count){'failed'}else{'completed-source-bound-observation'};phase=$phase;owner=$owner;lockAcquired=$acquired;lockReleased=($canRelease -and $cleanup.Count -eq 0);setupSeconds=$SetupSeconds;captureSeconds=$CaptureSeconds;cleanupSeconds=$CleanupSeconds;taskParentPid=if($null -ne $taskParent){$taskParent.Id}else{$null};parentHandleRetained=($parentHandle -ne [IntPtr]::Zero);taskResult=$taskResult;error=$errorText;cleanupErrors=$cleanup;nativeActions=if($PreflightOnly){0}else{1};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')};Write-FreshJson (Join-Path $control 'coordinator-lifecycle.json') $receipt
 if($null -ne $taskParent){$taskParent.Dispose()}
}
if($errorText -or $cleanup.Count){throw (($errorText+' '+($cleanup -join '; ')).Trim())}
