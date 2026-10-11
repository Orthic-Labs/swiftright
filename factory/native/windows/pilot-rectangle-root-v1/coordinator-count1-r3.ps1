# Root-owned Rectangle one-shot coordinator v2. Lock release uses ownership proofs separately from capture verdict.
param([Parameter(Mandatory=$true)][string]$Template,[Parameter(Mandatory=$true)][string]$TemplateHash,[switch]$PreflightOnly)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function J([string]$f){$i=Get-Item -LiteralPath $f;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded JSON required'};Get-Content -LiteralPath $f -Raw|ConvertFrom-Json}
if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -cne $TemplateHash){throw 'template pin mismatch'}
$c=J $Template;$overlay=[string]$c.overlayRoot;$control=[string]$c.controlRoot
foreach($row in $c.sourceBindings){$f=Join-Path $overlay $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'coordinator source drift'}}
. $c.integrationGuardPath
$si=J $c.sourceInputsPath
if((Get-FileHash $c.sourceInputsPath).Hash.ToLowerInvariant() -cne $c.sourceInputsHash){throw 'source inputs drift'}
Assert-FactoryIntegrationSources $c.producerRoot $si|Out-Null
$issued=Assert-LeaseIssuedMetadata $c.issuedMetadataPath $c.issuedMetadataHash $c.runRoot $c.count $c.compileReceiptHash $c.exeHash $c.serializerControlSha256 $c.producerRoot $si
$argsDispatch=@{}
foreach($key in @('Package','CompileReceiptHash','ExeHash','SerializerControlSha256','ProducerRoot','AdmissionRoot','ControlRoot','OutputRoot','IntegrationGuardPath','IntegrationGuardHash','SourceInputsPath','SourceInputsHash','RunRoot','IssuedMetadataPath','IssuedMetadataHash')){$argsDispatch[$key]=$c.$key}
if($PreflightOnly){& (Join-Path $overlay 'dispatch-rectangle-single.ps1') @argsDispatch -LockOwner 'preflight-no-lock' -Count 1 -PreflightOnly;return}
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class RectangleTaskWait { [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h,uint ms); [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h,out uint code); }
'@
. (Join-Path $c.producerRoot 'support\all-owned-release.ps1')
$lock='D:\Claude\desktop.lock';$owner='factory-rectangle-'+[Guid]::NewGuid().ToString('N')+' '+[DateTimeOffset]::UtcNow.ToString('o')
function CAS([string]$expected,[string]$replacement){try{$s=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false};try{if($s.Length -gt 4096){throw 'lock bound'};$reader=[IO.StreamReader]::new($s,[Text.Encoding]::UTF8,$true,1024,$true);try{$old=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()};if($old -cne $expected){return $false};$b=[Text.Encoding]::UTF8.GetBytes($replacement);$s.Position=0;$s.SetLength(0);$s.Write($b,0,$b.Length);$s.Flush($true);return $true}finally{$s.Dispose()}}
$taskName='FactoryRectangle-'+[Guid]::NewGuid().ToString('N');$registered=$false;$started=$false;$acquired=$false;$release=$false;$released=$false;$err=$null;$cleanup=@();$task=$null;$taskParent=$null;$parentHandle=[IntPtr]::Zero;$parentProof=$null
try{
 $waitLimit=[DateTime]::UtcNow.AddSeconds(90)
 do{$acquired=CAS 'free' $owner;if(-not $acquired){if([DateTime]::UtcNow -gt $waitLimit){throw 'desktop busy'};Start-Sleep -Seconds 2}}until($acquired)
 $c.owner=$owner;$config=Join-Path $control 'config.json';if(Test-Path $config){throw 'fresh coordinator config required'};$c|ConvertTo-Json -Depth 32|Set-Content -LiteralPath $config -Encoding UTF8
 $argv='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $overlay 'interactive-task-rectangle-single.ps1')+'" -Config "'+$config+'"'
 $vbs=Join-Path $control 'hidden-task.vbs';[IO.File]::WriteAllText($vbs,'Set sh = CreateObject("WScript.Shell")'+[Environment]::NewLine+'rc = sh.Run("powershell.exe '+$argv.Replace('"','""')+'", 0, True)'+[Environment]::NewLine+'WScript.Quit rc',[Text.Encoding]::ASCII)
 $action=New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\wscript.exe') -Argument ('"'+$vbs+'"');$principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest;$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings|Out-Null;$registered=$true;$started=$true;Start-ScheduledTask -TaskName $taskName
 $deadline=[DateTime]::UtcNow.AddSeconds(100)
 do{
  $start=Join-Path $control 'task-start.json'
  if($null -eq $taskParent -and (Test-Path $start)){$s=J $start;if($s.owner -cne $owner -or $s.issuedMetadataHash -cne $c.issuedMetadataHash -or $s.sourceInputsHash -cne $c.sourceInputsHash){throw 'task start lineage'};$taskParent=Get-Process -Id $s.pid -ErrorAction Stop;if($taskParent.Path -cne $s.path -or $taskParent.StartTime.ToUniversalTime().ToString('o') -cne $s.startedAt){throw 'task parent identity mismatch'};$parentHandle=$taskParent.Handle}
  $result=Join-Path $control 'task-result.json'
  if(Test-Path $result){$task=J $result;if($null -eq $taskParent){throw 'missing original task handle'};break}
  if([DateTime]::UtcNow -gt $deadline){throw 'native task deadline'};Start-Sleep -Milliseconds 100
 }until($false)
 if($task.owner -cne $owner -or $task.count -ne 1 -or $task.compileReceiptHash -cne $c.compileReceiptHash -or $task.exeHash -cne $c.exeHash -or $task.issuedMetadataHash -cne $c.issuedMetadataHash){throw 'task result identity'}
 if($task.status -cne 'completed-source-bound-observation'){throw ('capture failed: '+$task.error)}
}catch{$err=[string]$_}
finally{
 try{
  if($registered){Disable-ScheduledTask -TaskName $taskName|Out-Null;$until=[DateTime]::UtcNow.AddSeconds(15);do{$state=(Get-ScheduledTask $taskName).State;if($state -notin @('Running','Queued')){break};if([DateTime]::UtcNow -gt $until){throw 'scheduler task still running'};Start-Sleep -Milliseconds 100}until($false);Get-ScheduledTaskInfo $taskName|Select-Object LastRunTime,LastTaskResult|ConvertTo-Json|Set-Content (Join-Path $control 'scheduled-task-receipt.json') -Encoding UTF8}
  if($started){if($null -eq $task -or $null -eq $taskParent -or $parentHandle -eq [IntPtr]::Zero){throw 'task terminal proof missing'};$wait=[RectangleTaskWait]::WaitForSingleObject($parentHandle,5000);[uint32]$exit=259;if($wait -ne 0 -or -not [RectangleTaskWait]::GetExitCodeProcess($parentHandle,[ref]$exit) -or $exit -eq 259){throw 'original parent kernel exit unconfirmed'};$parentProof=@{pid=$taskParent.Id;retainedHandle=$parentHandle.ToInt64();kernelWait=$wait;exitCode=$exit};$mr=$task.memoryReceipt;if($mr.status -notin @('passed','rejected') -or $mr.parentPid -ne $taskParent.Id -or $mr.runID -cne $issued.runID -or $mr.issuedMetadataHash -cne $c.issuedMetadataHash -or $mr.killOnJobClose -ne $false -or $mr.peakJobMemoryUsedBytes -le 0 -or $mr.activeProcessCount -ne 1 -or $mr.limitFlags -ne 512 -or $mr.jobMemoryLimitBytes -ne 1073741824 -or $mr.peakJobMemoryUsedBytes -gt 1073741824){throw 'task memory/child quiescence rejected'};$native=@();if(Test-Path $c.runRoot){$native=@(Get-ChildItem -LiteralPath $c.runRoot -Directory|Where-Object{$_.Name -like 'native-*'})};if($native.Count -gt 1 -or ($task.status -ceq 'completed-source-bound-observation' -and $native.Count -ne 1)){throw 'native inventory count mismatch'};foreach($d in $native){if($d.Name -cne 'native-01'){throw 'native namespace'};Assert-FactoryAllOwnedRelease $d.FullName $owner $si.compileReceiptPath $c.compileReceiptHash $issued.exe.path $c.exeHash $si.sourceHash}}
  $release=$true
 }catch{$cleanup+=([string]$_)}
 if($acquired -and $release){$released=CAS $owner 'free'}
 $receipt=@{kind='root-rectangle-count1-coordinator-v2';status=if($err){'failed'}else{'completed-source-bound-observation'};owner=$owner;count=1;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;issuedMetadataHash=$c.issuedMetadataHash;sourceInputsHash=$c.sourceInputsHash;lockAcquired=$acquired;lockReleased=$released;wholeBatchExitConfirmed=$release;taskParentProof=$parentProof;error=$err;cleanupErrors=$cleanup;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')};$receipt|ConvertTo-Json -Depth 16|Set-Content (Join-Path $control 'coordinator.json') -Encoding UTF8
 if($null -ne $taskParent){$taskParent.Dispose()}
}
if($err -or ($acquired -and -not $released)){throw ($err+' '+($cleanup -join '; '))}
