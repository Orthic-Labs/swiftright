# File closure & complete raw copy are distinct; only successful EOF copy can seal raw.
function Get-FactoryRawStreamState($Stream){
 $task=$Stream.task
 [ordered]@{name=$Stream.name;copyCompleted=([bool]$Stream.copyCompleted);destinationClosed=([bool]$Stream.destinationClosed);sealed=([bool]$Stream.sealed);hashQualification=if($Stream.sealed){'sealed-raw'}else{'diagnostic-partial'};taskStatus=if($null -eq $task){'not-started'}else{[string]$task.Status};taskIsCompleted=if($null -eq $task){$false}else{[bool]$task.IsCompleted};taskIsFaulted=if($null -eq $task){$false}else{[bool]$task.IsFaulted};taskIsCanceled=if($null -eq $task){$false}else{[bool]$task.IsCanceled};taskException=if($null -ne $task -and $task.IsFaulted){[string]$task.Exception}else{''};sourceIsAsync=if($null -ne $Stream.source){[bool]$Stream.source.IsAsync}else{$null}}
}
function Complete-FactoryRawStreams([object[]]$Streams,[int]$WaitMilliseconds=5000){
 $errors=@()
 foreach($stream in $Streams){
  if($stream.sealed){continue}
  try{
   if($null -eq $stream.task -or $null -eq $stream.file){throw 'Raw stream setup incomplete'}
   if(-not $stream.task.Wait($WaitMilliseconds)){throw 'Raw stream completion deadline'}
   $stream.task.GetAwaiter().GetResult();$stream.copyCompleted=$true
   $stream.file.Flush($true);$stream.file.Dispose();$stream.destinationClosed=$true;$stream.sealed=$true
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
