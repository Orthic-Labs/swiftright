# Hash/read only after CopyToAsync completion, flush & close. State makes finally idempotent.
function Complete-FactoryRawStreams([object[]]$Streams,[int]$WaitMilliseconds=5000){
 $errors=@()
 foreach($stream in $Streams){
  if($stream.sealed){continue}
  try{
   if($null -eq $stream.task -or $null -eq $stream.file){throw 'Raw stream setup incomplete'}
   if(-not $stream.task.Wait($WaitMilliseconds)){throw 'Raw stream completion deadline'}
   $stream.task.GetAwaiter().GetResult()
   $stream.file.Flush($true)
   $stream.file.Dispose()
   $stream.sealed=$true
  }catch{$errors+=($stream.name+': '+[string]$_)}
 }
 if($errors.Count -ne 0){throw ($errors -join '; ')}
}
