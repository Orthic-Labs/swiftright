# Strict Count20 admission from prior coordinator-single-r1 evidence.
function Test-PaddingInteger($Value){return [bool]($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64])}
function Assert-PaddingFileBinding($RowFiles,[string]$Name,[string]$Directory,[string]$ExpectedHash) {
 $bindings=@($RowFiles|Where-Object{$_.path -ceq $Name})
 if($bindings.Count -ne 1){throw ('First proof file binding cardinality failed: '+$Name)}
 $path=Join-Path $Directory $Name
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('First proof file missing: '+$path)}
 $actual=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
 if($ExpectedHash -and $actual -cne ([string]$ExpectedHash).ToLowerInvariant()){throw ('First proof file hash mismatch: '+$Name)}
 if($bindings[0].sha256 -cne $actual){throw ('First proof row file hash mismatch: '+$Name)}
 return $actual
}
function Assert-PaddingFirstCaptureProof {
 param([Parameter(Mandatory=$true)][string]$CaptureRoot,[Parameter(Mandatory=$true)][string]$CompiledReceiptPath,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[Parameter(Mandatory=$true)][string]$ExpectedRunRoot)
 $firstControl=Join-Path $CaptureRoot 'coordinator-single-r1\coordinator.json'
 $firstRoot=Join-Path $CaptureRoot 'actual-single-r1'
 if($firstRoot -cne $ExpectedRunRoot){throw 'First proof output namespace mismatch'}
 $firstObservation=Join-Path $firstRoot 'native-observation.json';$firstDir=Join-Path $firstRoot 'native-01'
 $firstOutcomePath=Join-Path $firstDir 'capture-outcome.json';$ownedPath=Join-Path $firstDir 'owned-process.json';$closePath=Join-Path $firstDir 'owned-close.json';$uiaPath=Join-Path $firstDir 'native.uia.json';$pixelsPath=Join-Path $firstDir 'native.pixels.json';$stdoutPath=Join-Path $firstDir 'host.stdout.txt';$stderrPath=Join-Path $firstDir 'host.stderr.txt'
 foreach($path in @($firstControl,$firstObservation,$firstOutcomePath,$ownedPath,$closePath,$uiaPath,$pixelsPath,$stdoutPath,$stderrPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('First proof file missing: '+$path)}}
 $receiptHash=(Get-FileHash -LiteralPath $CompiledReceiptPath).Hash.ToLowerInvariant()
 if($receiptHash -cne $CompileReceiptHash.ToLowerInvariant()){throw 'First proof compile receipt bytes drift'}
 $control=Get-Content -Raw $firstControl|ConvertFrom-Json
 if($control.status -cne 'completed-source-bound-observation' -or $control.count -isnot [int] -and $control.count -isnot [long] -or $control.count -ne 1 -or $control.runRoot -cne $firstRoot -or $control.owner -isnot [string] -or [string]::IsNullOrEmpty($control.owner) -or $control.lockReleased -isnot [bool] -or -not $control.lockReleased -or $control.wholeBatchExitConfirmed -isnot [bool] -or -not $control.wholeBatchExitConfirmed -or $control.compileReceiptHash -cne $CompileReceiptHash -or $control.exeHash -cne $ExeHash){throw 'First coordinator lineage/release proof failed'}
 $decoded=Get-Content -Raw $firstObservation|ConvertFrom-Json;$rows=@($decoded)
 $outcome=Get-Content -Raw $firstOutcomePath|ConvertFrom-Json;$owned=Get-Content -Raw $ownedPath|ConvertFrom-Json;$close=Get-Content -Raw $closePath|ConvertFrom-Json;$uia=Get-Content -Raw $uiaPath|ConvertFrom-Json;$pixels=Get-Content -Raw $pixelsPath|ConvertFrom-Json;$receipt=Get-Content -Raw $CompiledReceiptPath|ConvertFrom-Json
 if($rows.Count -ne 1){throw 'First observation cardinality mismatch'}
 $row=$rows[0]
 if($row.hostValid -isnot [bool] -or -not $row.hostValid -or -not(Test-PaddingInteger $row.exitCode) -or $row.exitCode -ne 0 -or $row.compileReceiptHash -cne $CompileReceiptHash -or $row.exeSha256 -cne $ExeHash){throw 'First observation identity/validity proof failed'}
 $stdoutText=[IO.File]::ReadAllText($stdoutPath)
 if($stdoutText -notmatch 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' -or $stdoutText -notmatch 'FACTORY_RENDERER_READY' -or $stdoutText -notmatch 'FACTORY_COMMIT' -or $stdoutText -match 'FACTORY_(RENDER|STARTUP)_ERROR'){throw 'First host stdout predicate failed'}
 if($outcome.primaryError -isnot [string] -or $outcome.primaryError.Length -ne 0 -or $outcome.lockOwner -cne $control.owner -or $outcome.compileReceiptHash -cne $CompileReceiptHash -or $outcome.exeHash -cne $ExeHash){throw 'First capture control receipt mismatch'}
 if(-not(Test-FactoryKernelExitCertificate $outcome.cleanup)){throw 'First capture lacks numeric kernel exit certificate'}
 if($outcome.rawHashesQualification -cne 'sealed-raw' -or @($outcome.rawStreams).Count -ne 2){throw 'First capture raw stream cardinality/qualification failed'}
 foreach($name in @('stdout','stderr')){
  $stream=@($outcome.rawStreams|Where-Object{$_.name -ceq $name});if($stream.Count -ne 1 -or -not(Test-FactoryRawDestinationClosed $stream[0]) -or $stream[0].sealed -isnot [bool] -or -not $stream[0].sealed){throw 'First capture raw closure proof failed'}
  $path=Join-Path $firstDir ('host.'+$name+'.txt');$hash=Get-FactoryRawHash $path $stream[0];if($hash.qualification -cne 'sealed-raw' -or $hash.sha256 -notmatch '^[0-9a-f]{64}$'){throw 'First capture raw hash authority failed'}
  $field=if($name -ceq 'stdout'){$outcome.stdoutSha256}else{$outcome.stderrSha256};if($field -cne $hash.sha256){throw 'First capture raw hash join failed'}
 }
 $rowFiles=@($row.files)
 foreach($requiredName in @('owned-process.json','owned-close.json','capture-outcome.json','native.uia.json','native.pixels.json','host.stdout.txt','host.stderr.txt','native.printwindow.png','native.screen.png','native.printwindow.repeat.png','native.screen.repeat.png')){Assert-PaddingFileBinding $rowFiles $requiredName $firstDir|Out-Null}
 $rowUiaHash=Assert-PaddingFileBinding $rowFiles 'native.uia.json' $firstDir
 $rowPixelsHash=Assert-PaddingFileBinding $rowFiles 'native.pixels.json' $firstDir
 $sampleRows=@($pixels.samples|Where-Object{$null -ne $_.path -and $_.path -match '\.png$'})
 if($sampleRows.Count -ne 4 -or @($sampleRows|Select-Object -ExpandProperty path -Unique).Count -ne 4){throw 'First pixel sample cardinality failed'}
 $expectedSamples=@(
  [ordered]@{repeat=1;method='printwindow';path='native.printwindow.png'},
  [ordered]@{repeat=1;method='screen';path='native.screen.png'},
  [ordered]@{repeat=2;method='printwindow';path='native.printwindow.repeat.png'},
  [ordered]@{repeat=2;method='screen';path='native.screen.repeat.png'}
 )
 foreach($expected in $expectedSamples){
  $matches=@($sampleRows|Where-Object{(Test-PaddingInteger $_.repeat) -and $_.repeat -eq $expected.repeat -and $_.method -ceq $expected.method -and $_.path -ceq $expected.path})
  if($matches.Count -ne 1){throw ('First pixel method/repeat binding failed: '+$expected.path)}
  if($matches[0].sha256 -notmatch '^[0-9a-f]{64}$'){throw ('First pixel sample hash malformed: '+$expected.path)}
  Assert-PaddingFileBinding $rowFiles $expected.path $firstDir ([string]$matches[0].sha256)|Out-Null
 }
 $pwFirst=($sampleRows|Where-Object{$_.path -ceq 'native.printwindow.png'}).sha256;$pwRepeat=($sampleRows|Where-Object{$_.path -ceq 'native.printwindow.repeat.png'}).sha256
 $screenFirst=($sampleRows|Where-Object{$_.path -ceq 'native.screen.png'}).sha256;$screenRepeat=($sampleRows|Where-Object{$_.path -ceq 'native.screen.repeat.png'}).sha256
 $pwStable=($pwFirst -ceq $pwRepeat);$screenStable=($screenFirst -ceq $screenRepeat)
 if($pixels.printWindowRepeatStable -isnot [bool] -or $pixels.printWindowRepeatStable -ne $pwStable -or $pixels.screenRepeatStable -isnot [bool] -or $pixels.screenRepeatStable -ne $screenStable -or -not $pwStable -or -not $screenStable){throw 'First pixel repeat stability proof failed'}
 if($owned.pid -isnot [int] -and $owned.pid -isnot [long] -or $owned.pid -le 0 -or $owned.path -cne $receipt.exePath -or [string]::IsNullOrEmpty($owned.startedAt) -or $outcome.ownedIdentity.pid -ne $owned.pid -or $outcome.ownedIdentity.path -cne $owned.path -or $outcome.ownedIdentity.startedAt -cne $owned.startedAt){throw 'First owned-process identity join failed'}
 if($close.posted -isnot [bool] -or -not $close.posted -or $close.pid -ne $owned.pid -or $close.hwnd -le 0){throw 'First owned-close join failed'}
 if($pixels.pid -ne $owned.pid -or $pixels.hwnd -ne $close.hwnd -or $uia -eq $null -or $rowUiaHash -notmatch '^[0-9a-f]{64}$' -or $rowPixelsHash -notmatch '^[0-9a-f]{64}$'){throw 'First UIA/pixel observation join failed'}
}
