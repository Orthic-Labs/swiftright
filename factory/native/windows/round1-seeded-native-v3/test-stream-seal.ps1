# IO-only controls use actual FileStream+CopyToAsync & production sealing helper. No child/window/compiler.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh fixture output required'}
. (Join-Path $PSScriptRoot 'stream-seal.ps1')
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$results=@()
$bytes=[Text.Encoding]::UTF8.GetBytes("raw stdout bytes`n")
$path=Join-Path $OutputRoot 'complete.bin'
$source=[IO.MemoryStream]::new($bytes)
$file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
$task=$source.CopyToAsync($file)
$stream=@{name='stdout';file=$file;task=$task;sealed=$false}
try{
 Complete-FactoryRawStreams @($stream)
 $read=[IO.File]::ReadAllBytes($path);$hash=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
 if([Convert]::ToBase64String($read) -ne [Convert]::ToBase64String($bytes) -or -not $stream.sealed -or -not $stream.copyCompleted -or -not $stream.destinationClosed){throw 'Sealed raw bytes/hash read failed'}
 Complete-FactoryRawStreams @($stream) # Actual helper idempotence, no closed-stream exception.
 $results+=[ordered]@{mode='real-copy-close-read-hash-idempotent';sha256=$hash;bytes=$read.Length}
}finally{$source.Dispose();$file.Dispose()}
foreach($mode in @('unfinished','faulted')){
 $path=Join-Path $OutputRoot ($mode+'.bin')
 $file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $file.Write($bytes,0,$bytes.Length)
 $promise=[Threading.Tasks.TaskCompletionSource[bool]]::new()
 if($mode -eq 'faulted'){$promise.SetException([IO.IOException]::new('simulated copy failure'))}
 $stream=@{name=$mode;file=$file;task=$promise.Task;sealed=$false};$failed=$false
 try{try{Complete-FactoryRawStreams @($stream) 1}catch{$failed=$true}
  if(-not $failed -or $stream.sealed -or $stream.copyCompleted -or $stream.destinationClosed){throw ('Unfinished/failing task accepted '+$mode)}
  $results+=[ordered]@{mode=$mode;rejected=$failed;sealed=$stream.sealed}
 }finally{$file.Flush($true);$file.Dispose()}
}
# Two actual streams must both seal before caller enumerates/hashes all files.
$streams=@();$sources=@()
try{
 foreach($name in @('stdout','stderr')){
  $path=Join-Path $OutputRoot ($name+'.bin');$source=[IO.MemoryStream]::new($bytes);$sources+=$source
  $file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $streams+=@{name=$name;file=$file;task=$source.CopyToAsync($file);sealed=$false}
 }
 Complete-FactoryRawStreams $streams
 $hashes=@(Get-ChildItem -LiteralPath $OutputRoot -File|ForEach-Object{Get-FileHash -LiteralPath $_.FullName})
 if($hashes.Count -ne 5){throw 'All-files raw hash enumeration failed'}
 $results+=[ordered]@{mode='both-real-streams-sealed-all-file-hashes';hashedFiles=$hashes.Count}
}finally{foreach($source in $sources){$source.Dispose()};foreach($stream in $streams){$stream.file.Dispose()}}
$results|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
