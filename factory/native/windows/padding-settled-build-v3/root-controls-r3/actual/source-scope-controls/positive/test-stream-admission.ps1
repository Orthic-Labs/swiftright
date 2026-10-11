# Synthetic coherent mutations of completed actual controls; no child/compiler/window calls.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh fault namespace required'}
. (Join-Path $PSScriptRoot 'stream-control-admission.ps1')
Assert-CompilerStreamControls $PSScriptRoot
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$rows=@()
foreach($mode in @('positive','kernel-bool','kernel-timeout','unsealed','unclosed','writer-unconfirmed','writer-unstable','missing-raw-binding','stale-source','missing-mode','io-omission','empty-streams','duplicate-streams','inherit-string-bool','inherit-held-string','inherit-writer-signaled','io-empty-objects','io-equal-count-wrong','io-duplicate-mode','io-false-pass','io-timeout-callback','io-string-bool','raw-known-byte-drift')){
 $dir=Join-Path $OutputRoot $mode;New-Item -ItemType Directory -Path $dir|Out-Null
 foreach($name in @('stream-control-inputs.json','stream-seal.ps1','cleanup.ps1','test-stream-seal.ps1','test-process-streams-bounded.ps1','process-stream-control.cs')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $dir $name)}
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'stream-control-results') -Destination $dir -Recurse
 $console=Join-Path $dir 'stream-control-results\console\controls.json';$io=Join-Path $dir 'stream-control-results\io\controls.json';$receiptPath=Join-Path $dir 'stream-control-results\receipt.json'
 $ioValues=Read-CompilerControlRows $io
 $values=Read-CompilerControlRows $console;$receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json
 $volume=$values|Where-Object{$_.mode -ceq 'volume'};$inherit=$values|Where-Object{$_.mode -ceq 'inherit'}
 switch($mode){
  'kernel-bool' {$volume.cleanup.kernelWaitResult=$false}
  'kernel-timeout' {$volume.cleanup.kernelWaitResult=258}
  'unsealed' {$volume.rawStreams[0].sealed=$false}
  'unclosed' {$volume.rawStreams[0].destinationClosed=$false}
  'writer-unconfirmed' {$inherit.holderCleanup.confirmedOwnedExit=$false}
  'writer-unstable' {$inherit.initial.failureDisposition.stableAfterSourceSettlement=$false}
  'missing-mode' {$values=@($volume)}
  'io-omission' {$ioValues=@()}
  'empty-streams' {$volume.rawStreams=@()}
  'duplicate-streams' {$volume.rawStreams[1].name='stdout'}
  'inherit-string-bool' {$inherit.initial.failureDisposition.stableAfterSourceSettlement='false'}
  'inherit-held-string' {$inherit.initial.writerKernelSignaled='false'}
  'inherit-writer-signaled' {$inherit.initial.writerKernelSignaled=$true}
  'io-empty-objects' {$ioValues=@(@{},@{},@{},@{})}
  'io-equal-count-wrong' {$ioValues[0].mode='synthetic-wrong'}
  'io-duplicate-mode' {$ioValues[1].mode=$ioValues[0].mode}
  'io-false-pass' {$ioValues[1].rejected=$false}
  'io-timeout-callback' {$ioValues[4].hashCallbackCalls=1}
  'io-string-bool' {$ioValues[4].timedOut='true'}
  'raw-known-byte-drift' {[IO.File]::WriteAllBytes((Join-Path $dir 'stream-control-results\console\volume\stdout.bin'),[byte[]]@(1,2,3))}
  'stale-source' {Add-Content -LiteralPath (Join-Path $dir 'stream-seal.ps1') -Value '# synthetic drift'}
 }
 ConvertTo-Json -InputObject @($ioValues) -Depth 20|Set-Content -Encoding UTF8 $io
 ConvertTo-Json -InputObject @($values) -Depth 20|Set-Content -Encoding UTF8 $console
 # Coherent raw rehash means semantic guard, not stale byte hash, must reject.
 foreach($binding in $receipt.files){$binding.sha256=(Get-FileHash -LiteralPath (Join-Path $dir $binding.path)).Hash.ToLowerInvariant()}
 if($mode -ceq 'missing-raw-binding'){$receipt.files=@($receipt.files|Where-Object{$_.path -cne 'stream-control-results\console\controls.json'})}
 $receipt|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 $receiptPath
 $rejected=$false;try{Assert-CompilerStreamControls $dir}catch{$rejected=$true}
 if(($mode -ceq 'positive' -and $rejected) -or ($mode -cne 'positive' -and -not $rejected)){throw ('Admission fault wrong disposition: '+$mode)}
 $rows+=@{mode=$mode;rejected=$rejected;synthetic=$true}
}
ConvertTo-Json -InputObject @($rows) -Depth 12|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
