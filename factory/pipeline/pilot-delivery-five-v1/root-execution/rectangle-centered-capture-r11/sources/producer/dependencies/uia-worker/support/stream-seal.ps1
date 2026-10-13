# Copy EOF & destination closure have separate explicit5s deadlines.
if(-not ('FactoryDestinationCloseV5' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
public class FactoryCloseResultV5 {
 public bool FlushRequested, FlushCompleted, DestinationClosed;
 public string Error="";
}
public static class FactoryDestinationCloseV5 {
 public static Task<FactoryCloseResultV5> Start(FileStream file, bool flush, WaitHandle gate) {
  var completion=new TaskCompletionSource<FactoryCloseResultV5>();
  var thread=new Thread(()=>{
   var result=new FactoryCloseResultV5();result.FlushRequested=flush;
   if(gate!=null && !gate.WaitOne(5000)){result.Error="control close gate deadline";completion.SetResult(result);return;}
   if(flush){try{file.Flush(true);result.FlushCompleted=true;}catch(Exception ex){result.Error="flush: "+ex.ToString();}}
   try{file.Dispose();result.DestinationClosed=true;}catch(Exception ex){result.Error+=" close: "+ex.ToString();}
   completion.SetResult(result);
  });thread.IsBackground=true;thread.Name="factory-raw-destination-close";thread.Start();return completion.Task;
 }
}
'@
}
function Get-FactoryRawStreamState($Stream){
 $task=$Stream.task
 [ordered]@{name=$Stream.name;copyCompleted=([bool]$Stream.copyCompleted);destinationClosed=([bool]$Stream.destinationClosed);sealed=([bool]$Stream.sealed);hashQualification=if($Stream.sealed){'sealed-raw'}else{'diagnostic-partial'};taskStatus=if($null -eq $task){'not-started'}else{[string]$task.Status};taskIsCompleted=if($null -eq $task){$false}else{[bool]$task.IsCompleted};taskIsFaulted=if($null -eq $task){$false}else{[bool]$task.IsFaulted};taskIsCanceled=if($null -eq $task){$false}else{[bool]$task.IsCanceled};taskException=if($null -ne $task -and $task.IsFaulted){[string]$task.Exception}else{''};sourceIsAsync=if($null -ne $Stream.source){[bool]$Stream.source.IsAsync}else{$null};closure=if($null -ne $Stream.closure){$Stream.closure|ConvertTo-Json -Depth 12|ConvertFrom-Json}else{$null};closureTaskStatus=if($null -ne $Stream.closeTask){[string]$Stream.closeTask.Status}else{'not-started'}}
}
function Close-FactoryRawStreamDestination($Stream,[ValidateRange(0,5000)][int]$WaitMilliseconds=5000,[Threading.WaitHandle]$CloseGate=$null){
 if($Stream.destinationClosed){return}
 if($null -eq $Stream.file){throw 'Raw destination setup incomplete'}
 if($null -eq $Stream.closeTask){
  $flushAllowed=($null -ne $Stream.task -and $Stream.task.IsCompleted)
  $Stream.closure=[ordered]@{deadlineMilliseconds=$WaitMilliseconds;flushDisposition=if($flushAllowed){'requested-terminal-copy'}else{'skipped-pending-copy'};flushCompleted=$false;destinationClosed=$false;completedWithinDeadline=$false;deadlineExpired=$false;error='';before=Get-FactoryRawStreamState $Stream}
  $Stream.closeTask=[FactoryDestinationCloseV5]::Start($Stream.file,$flushAllowed,$CloseGate)
 }
 if(-not $Stream.closeTask.Wait($WaitMilliseconds)){$Stream.closure.deadlineExpired=$true;$Stream.closure.error='Raw destination closure deadline';throw 'Raw destination closure deadline'}
 $result=$Stream.closeTask.GetAwaiter().GetResult()
 $Stream.closure.completedWithinDeadline=[bool](-not $Stream.closure.deadlineExpired);$Stream.closure.flushCompleted=$result.FlushCompleted;$Stream.closure.destinationClosed=$result.DestinationClosed;$Stream.closure.error=if($Stream.closure.deadlineExpired){'Raw destination closure deadline; '+$result.Error}else{$result.Error}
 $Stream.destinationClosed=[bool]$result.DestinationClosed
 $Stream.sealed=[bool]($Stream.copyCompleted -and $result.FlushCompleted -and $result.DestinationClosed -and -not $result.Error -and -not $Stream.closure.deadlineExpired)
 if($result.Error){throw $result.Error}
 if(-not $Stream.destinationClosed){throw 'Raw destination closure unconfirmed'}
}
function Complete-FactoryRawStreams([object[]]$Streams,[ValidateRange(0,5000)][int]$WaitMilliseconds=5000){
 $errors=@()
 foreach($stream in $Streams){
  if($stream.sealed){continue}
  try{
   if($null -eq $stream.task -or $null -eq $stream.file){throw 'Raw stream setup incomplete'}
   if(-not $stream.task.Wait($WaitMilliseconds)){throw 'Raw stream completion deadline'}
   $stream.task.GetAwaiter().GetResult();$stream.copyCompleted=$true
   Close-FactoryRawStreamDestination $stream
   if(-not $stream.sealed){throw 'Completed copy lacks sealed destination'}
  }catch{$errors+=($stream.name+': '+[string]$_)}
 }
 if($errors.Count -ne 0){throw ($errors -join '; ')}
}
# Failed copies get durable diagnostic receipt before destination closure.
function Write-FactoryDiagnosticJson([string]$Path,$Value){
 $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12))
 $receipt=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$receipt.Write($bytes,0,$bytes.Length);$receipt.Flush($true)}finally{$receipt.Dispose()}
}

# Gate hash invocation on closed destination authority, including coordinator receipt state.
function Test-FactoryRawDestinationClosed($State){
 return [bool](($State.destinationClosed -is [bool]) -and $State.destinationClosed -and ($State.closure.destinationClosed -is [bool]) -and $State.closure.destinationClosed -and ($State.closure.completedWithinDeadline -is [bool]) -and ($State.closureTaskStatus -is [string]) -and $State.closureTaskStatus -ceq 'RanToCompletion')
}
function Get-FactoryRawHash([string]$Path,$State,[scriptblock]$Hash={param($file) (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant()}){
 $result=[ordered]@{sha256=$null;qualification='unqualified';reason='destination-closure-unconfirmed';error=''}
 if(-not(Test-FactoryRawDestinationClosed $State)){return $result}
 try{
  $value=& $Hash $Path
  if($value -isnot [string] -or $value -cnotmatch '^[0-9a-f]{64}$'){throw 'Raw hash value invalid'}
  $result.sha256=$value;$result.qualification=if(($State.sealed -is [bool]) -and $State.sealed){'sealed-raw'}else{'diagnostic-partial'};$result.reason=if($result.qualification -eq 'sealed-raw'){'copy-and-destination-sealed'}else{'closed-destination-copy-unqualified'}
 }catch{$result.reason='hash-read-failed';$result.error=[string]$_}
 return $result
}
