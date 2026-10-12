# Explicit runtime/helper closure for Circle successor source inputs.
# Caller must dot-source after Assert-CircleRef, Assert-FactoryRuntimeSource,
# & Assert-HostCompilerInputs definitions are available.
function Assert-CircleRuntimeClosure([object]$Plan,[object]$SourceInputs,[string]$PackagePath,[string]$Root) {
 if($null -eq $SourceInputs.runtimeProof){throw 'Circle runtime proof block missing'}
 $proof=$SourceInputs.runtimeProof
 foreach($field in @('runtimeSourceCommit','runtimeSourceTreeHash','runtimeSourceReceiptHash','runtimeSourceTreeRef','runtimeSourceReceiptRef','runtimeVerifierRef','hostInputsRef')){
  if([string]::IsNullOrWhiteSpace([string]$proof.$field) -and $field -notlike '*Ref'){throw ('Circle runtime proof field missing: '+$field)}
  if($field -like '*Ref' -and $null -eq $proof.$field){throw ('Circle runtime proof reference missing: '+$field)}
 }
 if($Plan.runtimeSourceCommit -cne $proof.runtimeSourceCommit){throw 'Circle runtime commit proof mismatch'}
 if($Plan.runtimeSourceTreeHash -cne $proof.runtimeSourceTreeHash -or $Plan.runtimeSourceReceiptHash -cne $proof.runtimeSourceReceiptHash){throw 'Circle runtime receipt/tree proof mismatch'}
 $treePath=Assert-CircleRef $proof.runtimeSourceTreeRef 'runtime source tree'
 $receiptPath=Assert-CircleRef $proof.runtimeSourceReceiptRef 'runtime source receipt'
 $verifierPath=Assert-CircleRef $proof.runtimeVerifierRef 'runtime verifier'
 $hostInputsPath=Assert-CircleRef $proof.hostInputsRef 'host inputs'
 $bindingsPath=Assert-CircleRef $SourceInputs.integrationBindingsRef 'integration bindings'
 $bindings=Get-CircleJson $bindingsPath
 foreach($pair in @(@{suffix='verify-runtime-source.ps1';path=$verifierPath;hash=$proof.runtimeVerifierRef.sha256.Substring(7)},@{suffix='host-inputs.ps1';path=$hostInputsPath;hash=$proof.hostInputsRef.sha256.Substring(7)})){
  $rows=@($bindings.files|Where-Object{[string]$_.path -match ([regex]::Escape([string]$pair.suffix))})
  if($rows.Count -ne 1){throw ('Circle integration binding row missing: '+$pair.suffix)}
  $expected=[IO.Path]::GetFullPath((Join-Path $Root ([string]$rows[0].path)))
  if([IO.Path]::GetFullPath([string]$pair.path) -cne $expected -or [string]$rows[0].sha256 -cne [string]$pair.hash -or [int64]$rows[0].bytes -ne [int64](Get-Item -LiteralPath $pair.path).Length){throw ('Circle integration binding helper mismatch: '+$pair.suffix)}
 }
 if((Get-CircleHash $treePath) -cne $proof.runtimeSourceTreeHash.Substring(7)){throw 'Circle runtime tree bytes/hash mismatch'}
 if((Get-CircleHash $receiptPath) -cne $proof.runtimeSourceReceiptHash.Substring(7)){throw 'Circle runtime receipt bytes/hash mismatch'}
 $verifierHash=(Get-CircleHash $verifierPath)
 $hostInputsHash=(Get-CircleHash $hostInputsPath)
 . $verifierPath
 . $hostInputsPath
 Assert-FactoryRuntimeSource $Plan $PackagePath
 Assert-HostCompilerInputs $PackagePath $Plan.sourceBindings
 return [ordered]@{runtimeSourceTreePath=$treePath;runtimeSourceReceiptPath=$receiptPath;runtimeVerifierPath=$verifierPath;runtimeVerifierHash=$verifierHash;hostInputsPath=$hostInputsPath;hostInputsHash=$hostInputsHash}
}
