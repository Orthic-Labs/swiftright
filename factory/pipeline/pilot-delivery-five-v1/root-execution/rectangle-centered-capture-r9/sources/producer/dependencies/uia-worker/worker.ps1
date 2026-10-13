# Hidden console process only. Sole UIA assembly/element owner; writes exact scalar snapshot schema.
param([Parameter(Mandatory=$true)][string]$Config,[Parameter(Mandatory=$true)][string]$ConfigHash)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($ConfigHash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Config).Hash.ToLowerInvariant() -cne $ConfigHash){throw 'Worker config bytes drift'}
$c=Get-Content -Raw -LiteralPath $Config|ConvertFrom-Json
if([IO.Path]::GetFullPath($Config) -cne (Join-Path ([IO.Path]::GetFullPath($c.outputRoot)) 'config.json')){throw 'Worker config/output path drift'}
function Write-WorkerStage([string]$Name,[object]$Extra=$null){
 $path=Join-Path $c.outputRoot ('stage-'+$Name+'.json')
 if(Test-Path -LiteralPath $path){throw ('Worker stage already exists: '+$Name)}
 $payload=[ordered]@{kind='factory-uia-snapshot-worker-stage-v1';stage=$Name;pid=$PID;observedAt=[DateTimeOffset]::UtcNow.ToString('o');target=$c.target;extra=$Extra}
 $payload|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $path -Encoding UTF8
}
Write-WorkerStage 'config-accepted'
if(-not [IO.Path]::GetFullPath($c.outputRoot).StartsWith('D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\centered-r9\native\',[StringComparison]::OrdinalIgnoreCase)){throw 'Worker output outside factory'}
foreach($b in $c.sourceBindings){$f=Join-Path $PSScriptRoot $b.path;if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $b.sha256){throw 'Worker source drift'}}
Write-WorkerStage 'source-pins-verified' ([ordered]@{count=@($c.sourceBindings).Count})
. (Join-Path $PSScriptRoot 'schema.ps1')
. (Join-Path $PSScriptRoot 'read-uia.ps1')
if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne $c.apartment){throw 'UIA worker apartment changed'}
Write-WorkerStage 'before-ui-automation-assembly'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Write-WorkerStage 'after-ui-automation-assembly'
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class FactoryUiaSnapshotWindowV1 {
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
}
'@
function Invoke-UiaFromHandleBounded([IntPtr]$Hwnd){
 # Worker process is launched with -MTA; FromHandle is synchronous on its MTA thread.
 if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'MTA'){throw 'UIA FromHandle requires dedicated MTA worker'}
 $element=[Windows.Automation.AutomationElement]::FromHandle($Hwnd)
 if($null -eq $element){throw 'UIA FromHandle MTA returned null'}
 return $element
}
function Assert-WorkerTarget {
 $p=Get-Process -Id $c.target.pid -ErrorAction Stop
 try{
  $hwnd=[IntPtr]::new([long]$c.target.hwnd);[uint32]$wpid=0
  $thread=[FactoryUiaSnapshotWindowV1]::GetWindowThreadProcessId($hwnd,[ref]$wpid)
  if($thread -eq 0){throw 'Stale owned HWND'}
  $fg=[FactoryUiaSnapshotWindowV1]::GetForegroundWindow();[uint32]$fgpid=0
  $null=[FactoryUiaSnapshotWindowV1]::GetWindowThreadProcessId($fg,[ref]$fgpid)
  $observed=[ordered]@{pid=$p.Id;path=$p.Path;startedAt=$p.StartTime.ToUniversalTime().ToString('o');hasExited=[bool]$p.HasExited;hwnd=$hwnd.ToInt64();windowPid=[long]$wpid;foregroundHwnd=$fg.ToInt64();foregroundPid=[long]$fgpid;workerPid=$PID;lockOwner=(Get-Content -Raw -LiteralPath 'D:\Claude\desktop.lock').Trim()}
  Assert-UiaSnapshotTargetObject $c.target $observed
 }finally{$p.Dispose()}
}
$record=[ordered]@{kind='factory-uia-snapshot-worker-observation-v2';status='failed';target=$c.target;workerPid=$PID;parentApartment=$c.parentApartment;workerApartment=$c.apartment;configSha256=$ConfigHash;startedAt=[DateTimeOffset]::UtcNow.ToString('o');error='';nativeWindowsOpened=$false;rendererLoaded=$false}
try{
 Assert-WorkerTarget
 Write-WorkerStage 'before-from-handle-mta' ([ordered]@{apartment='MTA';deadline='parent-15s'})
 $element=Invoke-UiaFromHandleBounded ([IntPtr]::new([long]$c.target.hwnd))
 Write-WorkerStage 'after-from-handle-mta' ([ordered]@{elementFound=($null -ne $element);targetPid=$c.target.pid;apartment='MTA'})
 if($null -eq $element -or $element.Current.ProcessId -ne $c.target.pid){throw 'UIA root ownership mismatch'}
 Assert-WorkerTarget
 Write-WorkerStage 'before-read-uia'
 $uia=Read-UIA $element
 Write-WorkerStage 'after-read-uia'
 Assert-WorkerTarget
 # Roundtrip validates no live UIA objects cross process boundary; exact original serialization depth/encoding.
 $json=$uia|ConvertTo-Json -Depth 80
 Write-WorkerStage 'before-scalar-validation' ([ordered]@{jsonBytes=[Text.Encoding]::UTF8.GetByteCount($json)})
 Assert-UiaSnapshotScalarObject ($json|ConvertFrom-Json)
 Write-WorkerStage 'after-scalar-validation'
 $path=Join-Path $c.outputRoot 'uia.json'
 if(Test-Path -LiteralPath $path){throw 'Fresh UIA output required'}
 Write-WorkerStage 'before-uia-publication' ([ordered]@{path=$path})
 $json|Set-Content -Encoding UTF8 -LiteralPath $path
 Write-WorkerStage 'after-uia-publication' ([ordered]@{path=$path})
 $record.uiaSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();$record.status='snapshot-written'
}catch{$record.error=[string]$_;throw}
finally{$record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');$record|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $c.outputRoot 'worker-observation.json')}
