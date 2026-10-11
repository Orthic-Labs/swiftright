# Hidden console controls; no renderer, desktop, GUI or witness edits.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'cleanup.ps1')
. (Join-Path $PSScriptRoot 'stream-seal.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$exe=Join-Path $OutputRoot 'FactoryStreamChild.exe'
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'process-stream-control.cs')) -OutputAssembly $exe -OutputType ConsoleApplication
$results=@()
foreach($mode in @('volume','inherit')){
 $dir=Join-Path $OutputRoot $mode;New-Item -ItemType Directory $dir|Out-Null
 $gate=Join-Path $dir 'release';$ready=Join-Path $dir 'ready';$pidFile=Join-Path $dir 'holder.pid'
 $info=[Diagnostics.ProcessStartInfo]::new($exe);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.Arguments=if($mode -eq 'volume'){'volume'}else{'inherit "'+$gate+'" "'+$ready+'" "'+$pidFile+'"'}
 $p=$null;$holder=$null;$streams=@();$primary=$null;$cleanup=$null;$holderCleanup=$null;$initial=$null
 try{
  $p=[Diagnostics.Process]::Start($info);$start=$p.StartTime.ToUniversalTime().ToString('o');$retained=$p.Handle
  foreach($name in @('stdout','stderr')){
   $file=[IO.File]::Open((Join-Path $dir ($name+'.bin')),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
   $source=if($name -eq 'stdout'){$p.StandardOutput.BaseStream}else{$p.StandardError.BaseStream}
   $streams+=@{name=$name;file=$file;source=$source;task=$source.CopyToAsync($file);copyCompleted=$false;destinationClosed=$false;sealed=$false}
  }
  if(-not $p.WaitForExit(15000)){throw 'Console control child deadline'}
  if([FactoryProcessWaitV4]::WaitForSingleObject($retained,0) -ne 0){throw 'Process wait lacked kernel signal'}
  if($p.ExitCode -ne 0){throw 'Control child failed'}
  if($mode -eq 'inherit'){
   if(-not(Test-Path $pidFile)){throw 'Inherited writer identity absent'}
   $holder=[Diagnostics.Process]::GetProcessById([int](Get-Content -Raw $pidFile));$holderHandle=$holder.Handle;$holderStart=$holder.StartTime.ToUniversalTime().ToString('o')
   if($holder.Path -ne $exe){throw 'Inherited writer path mismatch'}
   $readyEnd=[DateTime]::UtcNow.AddSeconds(2);while(-not(Test-Path $ready)){if([DateTime]::UtcNow -gt $readyEnd){throw 'Holder readiness deadline'};Start-Sleep -Milliseconds 20}
   $completed=$streams[0].task.Wait(5000)
   $initial=[ordered]@{primaryKernelSignaled=([FactoryProcessWaitV4]::WaitForSingleObject($retained,0) -eq 0);primaryHasExited=$p.HasExited;writerKernelSignaled=([FactoryProcessWaitV4]::WaitForSingleObject($holderHandle,0) -eq 0);stdoutCompletedWithin5000=$completed;rawStreams=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})}
   if($completed -or $streams[1].task.IsCompleted -or $initial.writerKernelSignaled){throw 'Inherited writer failed to hold both EOFs'}
   $failureBefore=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})
   foreach($stream in $streams){
    Write-FactoryDiagnosticJson (Join-Path $dir ($stream.name+'.raw-copy-failure.json')) ([ordered]@{qualification='diagnostic-partial';expectedCopyFailure='Raw stream completion deadline';stream=Get-FactoryRawStreamState $stream})
    Close-FactoryRawStreamDestination $stream
    if($stream.copyCompleted -or -not $stream.destinationClosed -or $stream.sealed -or $stream.closure.flushDisposition -cne 'skipped-pending-copy' -or -not $stream.closure.completedWithinDeadline -or $stream.closure.error){throw 'Pending-copy destination disposition wrong'}
   }
   $partial1=[IO.File]::ReadAllBytes((Join-Path $dir 'stdout.bin'))
   if($partial1.Length -ne 64*1024){throw 'Held-EOF known nonempty bytes absent'}
   for($j=0;$j -lt $partial1.Length;$j++){if($partial1[$j] -ne [byte](33+$j%90)){throw 'Held-EOF known bytes mismatch'}}
   $hash1=(Get-FileHash (Join-Path $dir 'stdout.bin')).Hash.ToLowerInvariant()
   $initial.failureDisposition=[ordered]@{expectedCopyFailure='Raw stream completion deadline';before=$failureBefore;after=@($streams|ForEach-Object{Get-FactoryRawStreamState $_});diagnosticSha256=$hash1;diagnosticBytes=$partial1.Length}
   [IO.File]::WriteAllText($gate,'release')
   if(-not $holder.WaitForExit(5000)){throw 'Holder release deadline'}
  }
  if($mode -eq 'volume'){Complete-FactoryRawStreams $streams}else{
   foreach($stream in $streams){if(-not $stream.task.Wait(5000)){throw 'Released inherited writer copy-settlement deadline'};$stream.task.GetAwaiter().GetResult()}
   $hash2=(Get-FileHash (Join-Path $dir 'stdout.bin')).Hash.ToLowerInvariant()
   if($hash1 -cne $hash2 -or (Get-Item (Join-Path $dir 'stdout.bin')).Length -ne 64*1024){throw 'Diagnostic bytes changed after destination closure'}
   $initial.failureDisposition.stableAfterSourceSettlement=$true;$initial.failureDisposition.afterSourceSettlement=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})
  }
  $stdout=[IO.File]::ReadAllBytes((Join-Path $dir 'stdout.bin'));$stderr=[IO.File]::ReadAllBytes((Join-Path $dir 'stderr.bin'))
  if($stderr.Length -ne 0){throw 'Expected empty stderr'}
  if($mode -eq 'volume'){
   if($stdout.Length -ne 384*1024){throw 'High-volume byte count mismatch'}
   for($i=0;$i -lt $stdout.Length;$i++){if($stdout[$i] -ne [byte](33+$i%90)){throw 'High-volume raw bytes mismatch'}}
  }elseif($stdout.Length -ne 64*1024){throw 'Inherited writer known stdout mismatch'}
 }catch{$primary=$_}finally{
  if($mode -eq 'inherit'){[IO.File]::WriteAllText($gate,'release')}
  if($null -ne $holder){$holderCleanup=Invoke-FactoryOwnedCleanup $holder $exe $holderStart -KnownStartedIdentity}
  if($null -ne $p){$cleanup=Invoke-FactoryOwnedCleanup $p $exe $start -KnownStartedIdentity}
  foreach($stream in $streams){if(-not $stream.sealed -and -not $stream.destinationClosed){try{Complete-FactoryRawStreams @($stream)}catch{};if(-not $stream.destinationClosed){try{Close-FactoryRawStreamDestination $stream}catch{}}}}
  $results+=[ordered]@{mode=$mode;initial=$initial;primaryError=if($null -ne $primary){[string]$primary}else{''};cleanup=$cleanup;holderCleanup=$holderCleanup;rawStreams=@($streams|ForEach-Object{Get-FactoryRawStreamState $_});stdoutBytes=if(Test-Path (Join-Path $dir 'stdout.bin')){(Get-Item (Join-Path $dir 'stdout.bin')).Length}else{0};stderrBytes=if(Test-Path (Join-Path $dir 'stderr.bin')){(Get-Item (Join-Path $dir 'stderr.bin')).Length}else{0}}
  $results|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
 }
 Assert-FactoryCaptureOutcome $primary $cleanup @()
 if($null -ne $holderCleanup -and -not $holderCleanup.confirmedOwnedExit){throw 'Holder kernel exit unconfirmed'}
}
