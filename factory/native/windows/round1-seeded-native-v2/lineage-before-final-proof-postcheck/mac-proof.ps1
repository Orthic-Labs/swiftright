# Reviewed exact two-source-level proof permits source replay only; Windows compile stays mandatory.
function Assert-SeedMacProofObject($Proof,$Expected,[string]$Package,$Plan,[string]$PlanHash){
 foreach($flag in @('sourceReplayEligible','windowsCompileRequiredBeforeNative','windowsCompileValidated','frozenPlansModified')){
  if($Proof.$flag -isnot [bool] -or $Proof.$flag -ne $Expected.$flag){throw ('Mac proof boolean '+$flag)}
 }
 foreach($field in @('kind','witnessSourceScope','captureSourceScope','compilerProcessOrigin','nativeParity')){
  if($Proof.$field -isnot [string] -or $Proof.$field -cne $Expected.$field){throw ('Mac proof scope '+$field)}
 }
 if(@($Proof.cases).Count -ne 5 -or @($Expected.cases).Count -ne 5){throw 'Mac proof exact five cases'}
 foreach($wanted in $Expected.cases){
  $matches=@($Proof.cases|Where-Object{$_.block -ceq $wanted.block})
  if($matches.Count -ne 1){throw 'Mac proof unique exact case blocks'}
  $row=$matches[0]
  foreach($field in @('planHash','witnessHash','adaptedHostHash','binaryHash')){if($row.$field -isnot [string] -or $row.$field -cne $wanted.$field){throw ('Mac proof source/hash '+$field)}}
  if($row.case.id -cne $wanted.case.id -or $row.case.hash -cne $wanted.case.hash){throw 'Mac proof exact case identity'}
  if(@($row.runs).Count -ne 20){throw 'Mac proof twenty runs'}
  foreach($index in 1..20){
   $actual=@($row.runs|Where-Object{($_.run -is [int] -or $_.run -is [long]) -and $_.run -eq $index})
   $required=@($wanted.runs|Where-Object{$_.run -eq $index})
   if($actual.Count -ne 1 -or $required.Count -ne 1){throw 'Mac proof twenty unique integer runs'}
   foreach($field in @('captureHash','rawHash','rawStatus')){if($actual[0].$field -isnot [string] -or $actual[0].$field -cne $required[0].$field){throw ('Mac proof raw witness '+$field)}}
  }
 }
 $selected=@($Expected.cases|Where-Object{$_.package -ceq $Package})
 if($selected.Count -ne 1 -or $PlanHash -cnotmatch '^[0-9a-f]{64}$' -or ('sha256:'+$PlanHash) -cne $selected[0].planHash -or $Plan.sourceHash -cne $selected[0].witnessHash -or $Plan.case.id -cne $selected[0].case.id -or $Plan.case.hash -cne $selected[0].case.hash){throw 'Seed plan/source/case proof mismatch'}
 if($Plan.executionEligible -isnot [bool] -or $Plan.executionEligible -or $Plan.hostMode -cne 'renderer'){throw 'Immutable seed plan scope mismatch'}
}
function Assert-SeedProofFileHash([string]$Path,[string]$ExpectedHash){
 if($ExpectedHash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() -cne $ExpectedHash){throw 'Reviewed Mac proof file bytes drift'}
}
function Assert-SeedMacProof([string]$Package,$Plan,[string]$PlanHash){
 $proofPath=Join-Path $PSScriptRoot 'proof\source-join.json'
 $expectedPath=Join-Path $PSScriptRoot 'proof-contract.json'
 Assert-SeedProofFileHash $proofPath '9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3'
 Assert-SeedProofFileHash $expectedPath '2a2f4f64da212cb187ff893dcade8c774ef292d7618dc511c455473bb00ec0b1'
 $proof=Get-Content -Raw -LiteralPath $proofPath|ConvertFrom-Json
 $expected=Get-Content -Raw -LiteralPath $expectedPath|ConvertFrom-Json
 Assert-SeedMacProofObject $proof $expected $Package $Plan $PlanHash
 if((Get-FileHash -LiteralPath (Join-Path $Package 'plan.json')).Hash.ToLowerInvariant() -cne $PlanHash -or (Get-FileHash -LiteralPath (Join-Path $Package 'Sources\FactoryProbe\Witness.swift')).Hash.ToLowerInvariant() -cne $Plan.sourceHash.Replace('sha256:','')){throw 'Actual seed plan/witness byte drift'}
}
# Independently measured successful Windows compile is required even though Mac proof permits source replay.
function Assert-SeedWindowsCompile([string]$Package,$Plan,[string]$PlanHash,[string]$CompileReceiptHash,[string]$ExeHash){
 if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Fresh measured Windows compile pins required'}
 $receiptPath=Join-Path $Package 'build-v2-r1\observation.json'
 if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Fresh Windows receipt bytes drift'}
 $compiled=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json
 if($compiled.exitCode -ne 0 -or $compiled.timedOut -isnot [bool] -or $compiled.timedOut -or $compiled.ownedExited -isnot [bool] -or -not $compiled.ownedExited -or $compiled.planSha256 -cne $PlanHash -or $compiled.sourceHash -cne $Plan.sourceHash -or $compiled.exeSha256 -cne $ExeHash -or $compiled.runtimeSourceCommit -cne $Plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -cne $Plan.runtimeSourceTreeHash -or $compiled.rendererSha256 -cne $Plan.rendererSha256){throw 'Fresh Windows compile lineage mismatch'}
 $exePath=[IO.Path]::GetFullPath($compiled.exePath)
 if(-not $exePath.StartsWith($Package+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $exePath).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Fresh Windows executable bytes/path drift'}
}
