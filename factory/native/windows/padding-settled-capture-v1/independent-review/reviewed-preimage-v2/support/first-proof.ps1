# Strict Count20 admission from prior coordinator-single-r1 evidence.
function Test-PaddingInteger($Value){return [bool]($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64])}
function Assert-PaddingFirstCaptureProof {
 param([Parameter(Mandatory=$true)][string]$CaptureRoot,[Parameter(Mandatory=$true)][string]$CompiledReceiptPath,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[Parameter(Mandatory=$true)][string]$ExpectedRunRoot)
 $firstControl=Join-Path $CaptureRoot 'coordinator-single-r1\coordinator.json'
 $firstRoot=Join-Path $CaptureRoot 'actual-single-r1'
 if($firstRoot -cne $ExpectedRunRoot){throw 'First proof output namespace mismatch'}
 $firstObservation=Join-Path $firstRoot 'native-observation.json';$firstDir=Join-Path $firstRoot 'native-01'
 $firstOutcomePath=Join-Path $firstDir 'capture-outcome.json';$ownedPath=Join-Path $firstDir 'owned-process.json';$closePath=Join-Path $firstDir 'owned-close.json';$uiaPath=Join-Path $firstDir 'native.uia.json';$pixelsPath=Join-Path $firstDir 'native.pixels.json'
 foreach($path in @($firstControl,$firstObservation,$firstOutcomePath,$ownedPath,$closePath,$uiaPath,$pixelsPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('First proof file missing: '+$path)}}
 $control=Get-Content -Raw $firstControl|ConvertFrom-Json
 if($control.status -cne 'completed-source-bound-observation' -or $control.count -isnot [int] -and $control.count -isnot [long] -or $control.count -ne 1 -or $control.runRoot -cne $firstRoot -or $control.owner -isnot [string] -or [string]::IsNullOrEmpty($control.owner) -or $control.lockReleased -isnot [bool] -or -not $control.lockReleased -or $control.wholeBatchExitConfirmed -isnot [bool] -or -not $control.wholeBatchExitConfirmed -or $control.compileReceiptHash -cne $CompileReceiptHash -or $control.exeHash -cne $ExeHash){throw 'First coordinator lineage/release proof failed'}
 $decoded=Get-Content -Raw $firstObservation|ConvertFrom-Json;$rows=@($decoded)
 $outcome=Get-Content -Raw $firstOutcomePath|ConvertFrom-Json;$owned=Get-Content -Raw $ownedPath|ConvertFrom-Json;$close=Get-Content -Raw $closePath|ConvertFrom-Json;$uia=Get-Content -Raw $uiaPath|ConvertFrom-Json;$pixels=Get-Content -Raw $pixelsPath|ConvertFrom-Json;$receipt=Get-Content -Raw $CompiledReceiptPath|ConvertFrom-Json
 if($rows.Count -ne 1){throw 'First observation cardinality mismatch'}
 $row=$rows[0]
 if($row.hostValid -isnot [bool] -or -not $row.hostValid -or -not(Test-PaddingInteger $row.exitCode) -or $row.exitCode -ne 0 -or $row.compileReceiptHash -cne $CompileReceiptHash -or $row.exeSha256 -cne $ExeHash){throw 'First observation identity/validity proof failed'}
 if($outcome.primaryError -isnot [string] -or $outcome.primaryError.Length -ne 0 -or $outcome.lockOwner -cne $control.owner -or $outcome.compileReceiptHash -cne $CompileReceiptHash -or $outcome.exeHash -cne $ExeHash){throw 'First capture control receipt mismatch'}
 if(-not(Test-FactoryKernelExitCertificate $outcome.cleanup)){throw 'First capture lacks numeric kernel exit certificate'}
 if($outcome.rawHashesQualification -cne 'sealed-raw' -or @($outcome.rawStreams).Count -ne 2){throw 'First capture raw stream cardinality/qualification failed'}
 foreach($name in @('stdout','stderr')){
  $stream=@($outcome.rawStreams|Where-Object{$_.name -ceq $name});if($stream.Count -ne 1 -or -not(Test-FactoryRawDestinationClosed $stream[0]) -or $stream[0].sealed -isnot [bool] -or -not $stream[0].sealed){throw 'First capture raw closure proof failed'}
  $path=Join-Path $firstDir ('host.'+$name+'.txt');$hash=Get-FactoryRawHash $path $stream[0];if($hash.qualification -cne 'sealed-raw' -or $hash.sha256 -notmatch '^[0-9a-f]{64}$'){throw 'First capture raw hash authority failed'}
  $field=if($name -ceq 'stdout'){$outcome.stdoutSha256}else{$outcome.stderrSha256};if($field -cne $hash.sha256){throw 'First capture raw hash join failed'}
 }
 if($owned.pid -isnot [int] -and $owned.pid -isnot [long] -or $owned.pid -le 0 -or $owned.path -cne $receipt.exePath -or [string]::IsNullOrEmpty($owned.startedAt) -or $outcome.ownedIdentity.pid -ne $owned.pid -or $outcome.ownedIdentity.path -cne $owned.path -or $outcome.ownedIdentity.startedAt -cne $owned.startedAt){throw 'First owned-process identity join failed'}
 if($close.posted -isnot [bool] -or -not $close.posted -or $close.pid -ne $owned.pid -or $close.hwnd -le 0){throw 'First owned-close join failed'}
 if($pixels.pid -ne $owned.pid -or $pixels.hwnd -ne $close.hwnd -or $uia -eq $null){throw 'First UIA/pixel observation join failed'}
}
