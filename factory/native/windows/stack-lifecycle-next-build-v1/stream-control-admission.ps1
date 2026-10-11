# PS5 emits a JSON array as one pipeline object; assign first, then enumerate variable.
function Read-CompilerControlRows([string]$Path){
 $raw=Get-Content -Raw -LiteralPath $Path
 if(-not $raw.TrimStart().StartsWith('[')){throw 'Control JSON root must be array'}
 $decoded=$raw|ConvertFrom-Json
 $rows=@($decoded)
 if($rows.Count -eq 0){throw 'Control array empty'}
 foreach($row in $rows){if($row -isnot [pscustomobject]){throw 'Control row must be object'}}
 return ,$rows
}
# Exact control facts, consumed raw bytes & typed states; coherent rehash does not bypass semantics.
function Assert-ControlBool($Value,[bool]$Expected){if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Control Boolean fact invalid'}}
function Assert-ControlInteger($Value,[long]$Expected){if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -ne $Expected){throw 'Control integer fact invalid'}}
function Assert-ControlStreamPair($Streams){
 $rows=@($Streams)
 if($rows.Count -ne 2 -or @($rows|Where-Object{$_.name -ceq 'stdout'}).Count -ne 1 -or @($rows|Where-Object{$_.name -ceq 'stderr'}).Count -ne 1){throw 'Exactly stdout/stderr states required'}
}
function Assert-ControlStreamState($State,[bool]$CopyCompleted,[bool]$Closed,[bool]$Sealed,[bool]$Terminal){
 Assert-ControlBool $State.copyCompleted $CopyCompleted;Assert-ControlBool $State.destinationClosed $Closed;Assert-ControlBool $State.sealed $Sealed
 Assert-ControlBool $State.taskIsCompleted $Terminal;Assert-ControlBool $State.taskIsFaulted $false;Assert-ControlBool $State.taskIsCanceled $false
 if($State.taskException -isnot [string] -or $State.taskException){throw 'Control task exception'}
 if($Terminal -and $State.taskStatus -cne 'RanToCompletion'){throw 'Control task not terminal'}
 if($Closed){
  Assert-ControlBool $State.closure.destinationClosed $true;Assert-ControlBool $State.closure.completedWithinDeadline $true;Assert-ControlBool $State.closure.deadlineExpired $false
  if($State.closureTaskStatus -cne 'RanToCompletion' -or $State.closure.error -isnot [string] -or $State.closure.error){throw 'Control closure not terminal'}
  Assert-ControlBool $State.closure.flushCompleted $Sealed
  $expectedFlush=if($Sealed){'requested-terminal-copy'}else{'skipped-pending-copy'}
  if($State.closure.flushDisposition -cne $expectedFlush){throw 'Control flush disposition invalid'}
 }
}
function Assert-ControlRaw([string]$Path,[int]$Count,[switch]$Pattern){
 $raw=[IO.File]::ReadAllBytes($Path)
 if($raw.Length -ne $Count){throw 'Control raw length invalid'}
 if($Pattern){for($i=0;$i -lt $raw.Length;$i++){if($raw[$i] -ne [byte](33+$i%90)){throw 'Control known raw pattern invalid'}}}
 else{if($Count -gt 0 -and [Convert]::ToBase64String($raw) -cne [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("raw stdout bytes`n"))){throw 'Control known IO bytes invalid'}}
 return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Assert-CompilerStreamControls([string]$Root){
 if((Get-FileHash -LiteralPath (Join-Path $Root 'stream-control-inputs.json')).Hash.ToLowerInvariant() -cne '640ee89a374b1615fd96661f6b510835232f0a318221f8f16696d7c64c82fe5c'){throw 'Exact stream input pins required'}
 $pins=Get-Content -Raw -LiteralPath (Join-Path $Root 'stream-control-inputs.json')|ConvertFrom-Json
 foreach($prop in $pins.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $Root $prop.Name)).Hash.ToLowerInvariant() -cne $prop.Value){throw 'Stream control source drift'}}
 . (Join-Path $Root 'cleanup.ps1')
 $dir=Join-Path $Root 'stream-control-results';$receipt=Get-Content -Raw -LiteralPath (Join-Path $dir 'receipt.json')|ConvertFrom-Json
 if($receipt.kind -cne 'actual-compiler-stream-controls-v2'){throw 'Actual stream controls missing'}
 Assert-ControlBool $receipt.completed $true;Assert-ControlInteger $receipt.compilerInvocations 0;Assert-ControlInteger $receipt.nativeWindows 0
 $required=@('stream-control-results\console\controls.json','stream-control-results\io\controls.json')
 foreach($path in $required){if(@($receipt.files|Where-Object{$_.path -ceq $path}).Count -ne 1){throw 'Control raw binding missing'}}
 $paths=@()
 foreach($binding in $receipt.files){
  if($binding.path -isnot [string] -or $binding.path -cnotmatch '^stream-control-results\\[A-Za-z0-9_.\\-]+$' -or $binding.path.Split('\') -contains '..' -or $paths -ccontains $binding.path){throw 'Control raw path invalid'}
  $paths+=$binding.path
  if((Get-FileHash -LiteralPath (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'Stream control raw drift'}
 }
 $actual=@(Get-ChildItem -LiteralPath $dir -Recurse -File|Where-Object{$_.FullName -cne (Join-Path $dir 'receipt.json')}|ForEach-Object{$_.FullName.Substring($Root.Length+1)})
 if($actual.Count -ne $paths.Count -or @($actual|Where-Object{$paths -cnotcontains $_}).Count){throw 'Control raw membership incomplete'}
 foreach($prop in $pins.PSObject.Properties){if($receipt.inputs.($prop.Name) -cne $prop.Value){throw 'Stream control invocation source drift'}}
 $rows=Read-CompilerControlRows (Join-Path $dir 'console\controls.json')
 if($rows.Count -ne 2 -or @($rows|Where-Object{$_.mode -ceq 'volume'}).Count -ne 1 -or @($rows|Where-Object{$_.mode -ceq 'inherit'}).Count -ne 1){throw 'Stream modes incomplete'}
 foreach($row in $rows){
  if($row.primaryError -isnot [string] -or $row.primaryError -or -not (Test-FactoryKernelExitCertificate $row.cleanup)){throw 'Stream child exit control failed'}
  Assert-ControlStreamPair $row.rawStreams
  $count=if($row.mode -ceq 'volume'){384*1024}else{64*1024}
  Assert-ControlInteger $row.stdoutBytes $count;Assert-ControlInteger $row.stderrBytes 0
  $rawHash=Assert-ControlRaw (Join-Path $dir ('console\'+$row.mode+'\stdout.bin')) $count -Pattern
  $null=Assert-ControlRaw (Join-Path $dir ('console\'+$row.mode+'\stderr.bin')) 0
  if($row.mode -ceq 'volume'){foreach($state in $row.rawStreams){Assert-ControlStreamState $state $true $true $true $true};continue}
  if(-not (Test-FactoryKernelExitCertificate $row.holderCleanup)){throw 'Inherited holder exit unconfirmed'}
  $initial=$row.initial;$failure=$initial.failureDisposition
  Assert-ControlBool $initial.primaryKernelSignaled $true;Assert-ControlBool $initial.primaryHasExited $true;Assert-ControlBool $initial.writerKernelSignaled $false;Assert-ControlBool $initial.stdoutCompletedWithin5000 $false
  Assert-ControlBool $failure.stableAfterSourceSettlement $true
  if($failure.expectedCopyFailure -cne 'Raw stream completion deadline' -or $failure.diagnosticSha256 -cne $rawHash){throw 'Held EOF failure/raw hash invalid'}
  Assert-ControlInteger $failure.diagnosticBytes $count
  foreach($set in @($initial.rawStreams,$failure.before)){Assert-ControlStreamPair $set;foreach($state in $set){Assert-ControlStreamState $state $false $false $false $false}}
  Assert-ControlStreamPair $failure.after
  foreach($state in $failure.after){Assert-ControlStreamState $state $false $true $false $false}
  foreach($set in @($failure.afterSourceSettlement,$row.rawStreams)){Assert-ControlStreamPair $set;foreach($state in $set){Assert-ControlStreamState $state $false $true $false $true}}
 }
 $io=Read-CompilerControlRows (Join-Path $dir 'io\controls.json')
 $modes=@('real-copy-close-read-hash-idempotent','unfinished','faulted','failed-flush-successful-dispose-reject-seal','actual-close-timeout-capture-coordinator-hash-gate','both-real-streams-sealed-all-file-hashes')
 if($io.Count -ne 6){throw 'Exactly six IO modes required'}
 foreach($mode in $modes){if(@($io|Where-Object{$_.mode -ceq $mode}).Count -ne 1){throw 'IO mode omitted/duplicate/misbound'}}
 foreach($name in @('complete','unfinished','faulted','close-timeout','stdout','stderr')){$null=Assert-ControlRaw (Join-Path $dir ('io\'+$name+'.bin')) 17}
 $null=Assert-ControlRaw (Join-Path $dir 'io\failed-flush.bin') 0
 if(@(Get-ChildItem -LiteralPath (Join-Path $dir 'io') -File -Filter '*.bin').Count -ne 7){throw 'Exact IO raw membership required'}
 $success=$io|Where-Object{$_.mode -ceq $modes[0]};Assert-ControlInteger $success.bytes 17
 if($success.sha256 -cne (Get-FileHash -LiteralPath (Join-Path $dir 'io\complete.bin')).Hash.ToLowerInvariant()){throw 'IO sealed raw hash invalid'}
 foreach($mode in @('unfinished','faulted')){$row=$io|Where-Object{$_.mode -ceq $mode};Assert-ControlBool $row.rejected $true;Assert-ControlBool $row.sealed $false}
 $failure=$io|Where-Object{$_.mode -ceq $modes[3]};Assert-ControlBool $failure.rejected $true
 $state=$failure.state;Assert-ControlBool $state.sealed $false;Assert-ControlBool $state.destinationClosed $true;Assert-ControlBool $state.copyCompleted $true;Assert-ControlBool $state.taskIsCompleted $true;Assert-ControlBool $state.taskIsFaulted $false;Assert-ControlBool $state.taskIsCanceled $false
 Assert-ControlBool $state.closure.flushCompleted $false;Assert-ControlBool $state.closure.destinationClosed $true;Assert-ControlBool $state.closure.completedWithinDeadline $true;Assert-ControlBool $state.closure.deadlineExpired $false
 if($state.closure.flushDisposition -cne 'requested-terminal-copy' -or $state.hashQualification -cne 'diagnostic-partial'){throw 'Failed flush disposition invalid'}
 if($state.taskStatus -cne 'RanToCompletion' -or $state.closureTaskStatus -cne 'RanToCompletion' -or $state.closure.error -isnot [string] -or -not $state.closure.error){throw 'Failed flush facts invalid'}
 $timeout=$io|Where-Object{$_.mode -ceq $modes[4]};Assert-ControlBool $timeout.timedOut $true;Assert-ControlInteger $timeout.hashCallbackCalls 0
 foreach($hash in @($timeout.captureHash,$timeout.coordinatorHash)){if($null -ne $hash.sha256 -or $hash.qualification -cne 'unqualified' -or $hash.reason -cne 'destination-closure-unconfirmed' -or $hash.error -isnot [string] -or $hash.error){throw 'Unclosed hash callback proof invalid'}}
 Assert-ControlBool $timeout.state.copyCompleted $true;Assert-ControlBool $timeout.state.taskIsCompleted $true;Assert-ControlBool $timeout.state.taskIsFaulted $false;Assert-ControlBool $timeout.state.taskIsCanceled $false
 if($timeout.state.taskStatus -cne 'RanToCompletion' -or $timeout.state.taskException -isnot [string] -or $timeout.state.taskException -or $timeout.state.closureTaskStatus -cne 'WaitingForActivation'){throw 'Timeout copy/closure task facts invalid'}
 Assert-ControlInteger $timeout.state.closure.deadlineMilliseconds 1;Assert-ControlBool $timeout.state.closure.flushCompleted $false;Assert-ControlBool $timeout.state.closure.destinationClosed $false
 if($timeout.state.closure.flushDisposition -cne 'requested-terminal-copy' -or $timeout.state.closure.error -cne 'Raw destination closure deadline'){throw 'Timeout closure facts invalid'}
 Assert-ControlBool $timeout.state.destinationClosed $false;Assert-ControlBool $timeout.state.sealed $false;Assert-ControlBool $timeout.state.closure.deadlineExpired $true;Assert-ControlBool $timeout.state.closure.completedWithinDeadline $false
 Assert-ControlInteger ($io|Where-Object{$_.mode -ceq $modes[5]}).hashedFiles 7
}
