param([Parameter(Mandatory=$true)][string]$Config,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
function Publish-Atomic([string]$Path,[object]$Value){if(Test-Path -LiteralPath $Path){throw 'fresh receipt required'};$tmp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp';$bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 16));$f=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()};[IO.File]::Move($tmp,$Path)}
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$configPath=[IO.Path]::GetFullPath($Config)
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$here=[IO.Path]::GetFullPath([string]$c.producerRoot)
$controlRoot=[IO.Path]::GetFullPath([string]$c.controlRoot)
$runRoot=[IO.Path]::GetFullPath([string]$c.runRoot)
$admissionRoot=[IO.Path]::GetFullPath([string]$c.admissionRoot)
if(-not(Test-Path -LiteralPath $admissionRoot -PathType Container)){throw 'Explicit admission root missing'}
if(-not $configPath.StartsWith($controlRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside fresh coordinator lane'}
if($c.count -ne 1){throw 'Exact Count1 Rectangle capture required'}
if($configPath -cne (Join-Path $controlRoot 'config.json') -or $c.controlRoot -cne $controlRoot -or $c.runRoot -cne $runRoot -or [string]::IsNullOrWhiteSpace($c.outputRoot) -or [string]::IsNullOrWhiteSpace($c.package) -or [string]::IsNullOrWhiteSpace($c.sourceInputsPath) -or $c.sourceInputsHash -notmatch '^[0-9a-f]{64}$'){throw 'Exact Count1 Rectangle coordinator config required'}
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RectangleInteractiveDesktopProbe {
 [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetThreadDesktop(uint id);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll", SetLastError=true)] public static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder data, int length, out int needed);
 [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
 [DllImport("user32.dll", SetLastError=true)] public static extern bool CloseDesktop(IntPtr h);
}
'@
function Assert-InteractiveDesktop([string]$Root){
 $tid=[RectangleInteractiveDesktopProbe]::GetCurrentThreadId();$thread=[RectangleInteractiveDesktopProbe]::GetThreadDesktop($tid);$threadName='';$threadReadable=$false;$input=[IntPtr]::Zero;$inputName='';$inputReadable=$false;$inputError=0
 if($thread -ne [IntPtr]::Zero){$need=0;$sb=[Text.StringBuilder]::new(256);$threadReadable=[RectangleInteractiveDesktopProbe]::GetUserObjectInformation($thread,2,$sb,$sb.Capacity,[ref]$need);if($threadReadable){$threadName=$sb.ToString()}}
 $input=[RectangleInteractiveDesktopProbe]::OpenInputDesktop(0,$false,1);$inputError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();if($input -ne [IntPtr]::Zero){$need2=0;$sb2=[Text.StringBuilder]::new(256);$inputReadable=[RectangleInteractiveDesktopProbe]::GetUserObjectInformation($input,2,$sb2,$sb2.Capacity,[ref]$need2);$inputError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();if($inputReadable){$inputName=$sb2.ToString()};[void][RectangleInteractiveDesktopProbe]::CloseDesktop($input)}
 $receipt=[ordered]@{kind='factory-interactive-desktop-availability-v1';threadId=$tid;threadDesktopName=$threadName;threadDesktopReadable=$threadReadable;inputDesktopName=$inputName;inputDesktopReadable=$inputReadable;inputDesktopLastWin32Error=$inputError;observedAt=[DateTimeOffset]::UtcNow.ToString('o');status=if($threadReadable -and $inputReadable -and $inputName -ieq 'Default'){'available'}else{'unavailable'}}
 $receipt|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Root 'desktop-availability.json') -Encoding UTF8
 if($receipt.status -cne 'available'){throw ('Interactive desktop unavailable: name='+$inputName+' win32='+$inputError)}
}
$status='hold-harness-error';$primaryError=$null;$job=$null;$memoryReceipt=$null
try{
 if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive desktop session required'}
 if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $c.owner){throw 'Coordinator lock ownership lost'}
 $issued=Get-Content -Raw ([IO.Path]::GetFullPath([string]$c.issuedMetadataPath))|ConvertFrom-Json
 $runId=[string]$issued.runID
 if([string]::IsNullOrWhiteSpace($runId)){throw 'Issued metadata runID required for memory receipt'}
 Add-Type -Path (Join-Path $overlayRoot 'Sr0OwnedJobProcess-v15.cs')
 $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824)
 $initial=$job.QueryPeakJobMemory()
 if($initial.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $initial.JobMemoryLimitBytes -ne 1073741824 -or $initial.ActiveProcessCount -ne 1){throw 'Memory job admission proof failed'}
 $taskStart=[ordered]@{kind='factory-rectangle-interactive-task-start-v1';pid=[Diagnostics.Process]::GetCurrentProcess().Id;path=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;startedAt=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o');observedAt=[DateTimeOffset]::UtcNow.ToString('o');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;owner=$c.owner;jobMemoryLimitBytes=$initial.JobMemoryLimitBytes;limitFlags=$initial.LimitFlags;activeProcessCount=$initial.ActiveProcessCount;sourceInputsHash=$c.sourceInputsHash;issuedMetadataHash=$c.issuedMetadataHash;runID=$runId;status='self-job-admitted'}
 Publish-Atomic (Join-Path $controlRoot 'task-start.json') $taskStart
 Assert-InteractiveDesktop $controlRoot
 & (Join-Path $overlayRoot 'dispatch-rectangle-single-v3.ps1') -Package $c.package -LockOwner $c.owner -ProducerRoot $c.producerRoot -AdmissionRoot $admissionRoot -ControlRoot $c.controlRoot -OutputRoot $c.outputRoot -IntegrationGuardPath $c.integrationGuardPath -IntegrationGuardHash $c.integrationGuardHash -SourceInputsPath $c.sourceInputsPath -SourceInputsHash $c.sourceInputsHash -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count $c.count -RunRoot $c.runRoot -IssuedMetadataPath $c.issuedMetadataPath -IssuedMetadataHash $c.issuedMetadataHash -PreflightOnly:$PreflightOnly *> (Join-Path $controlRoot 'task.log')
 $final=$job.WaitForOnlyCurrent(3000)
 [Sr0OwnedJobProcess]::RequireOnlyCurrent($final)
 $memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=$runId;issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$final.JobMemoryLimitBytes;limitFlags=$final.LimitFlags;peakJobMemoryUsedBytes=$final.PeakJobMemoryUsedBytes;activeProcessCount=$final.ActiveProcessCount;status='passed';killOnJobClose=$false}
 $status='completed-source-bound-observation'
}catch{$primaryError=$_;if($null -ne $job){try{$s=$job.QueryPeakJobMemory();$memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=if($null -ne $runId){$runId}else{''};issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$s.JobMemoryLimitBytes;limitFlags=$s.LimitFlags;peakJobMemoryUsedBytes=$s.PeakJobMemoryUsedBytes;activeProcessCount=$s.ActiveProcessCount;status='rejected';killOnJobClose=$false;error=[string]$primaryError}}catch{}}}
$nativeDirs=@();if(Test-Path -LiteralPath $c.runRoot){$nativeDirs=@(Get-ChildItem -LiteralPath $c.runRoot -Directory|Where-Object{$_.Name -like 'native-*'})}
$inventories=@($nativeDirs|ForEach-Object{$path=Join-Path $_.FullName 'owned-worker-inventory.json';[ordered]@{directory=$_.FullName;path=$path;sha256=if(Test-Path -LiteralPath $path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}else{$null}}})
$result=[ordered]@{issuedMetadataHash=$c.issuedMetadataHash;workerInventories=$inventories;status=$status;owner=$c.owner;count=$c.count;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;serializerControlSha256=$c.serializerControlSha256;memoryReceipt=$memoryReceipt;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
Publish-Atomic (Join-Path $controlRoot 'task-result.json') $result
if($null -ne $job){$job.Dispose();$job=$null}
if($null -ne $primaryError){throw $primaryError}
