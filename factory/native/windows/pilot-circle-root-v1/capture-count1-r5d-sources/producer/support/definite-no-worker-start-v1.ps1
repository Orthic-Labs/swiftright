# Admission for a definite pre-Process.Start worker contract failure.
# This validates source/error/artifact lineage; it performs no lock or native action.
Set-StrictMode -Version Latest

function Read-FactoryNoStartBounded([string]$Path,[int64]$Limit=2097152){
 if([string]::IsNullOrWhiteSpace($Path)){throw 'Bounded path required'}
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -gt $Limit){throw ('Bounded regular file required: '+$Path)}
 return [IO.File]::ReadAllText($item.FullName)
}
function Get-FactoryNoStartHash([string]$Path,[int64]$Limit=2097152){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -gt $Limit){throw ('Bounded regular file required: '+$Path)}
 $stream=$null;$sha=$null
 try{
  $stream=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $sha=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 1048576;$total=0L
  while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){$sha.TransformBlock($buffer,0,$read,$buffer,0)|Out-Null;$total+=$read;if($total -gt $Limit){throw 'Bounded hash limit exceeded'}}
  $sha.TransformFinalBlock($buffer,0,0)|Out-Null
  return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()
 }finally{if($null -ne $sha){$sha.Dispose()};if($null -ne $stream){$stream.Dispose()}}
}
function Test-FactoryNoStartHash([string]$Actual,[string]$Expected){
 if($Actual -isnot [string] -or $Expected -isnot [string]){return $false}
 return $Actual.ToLowerInvariant() -ceq (($Expected -replace '^sha256:','').ToLowerInvariant())
}
function Assert-FactoryDefiniteNoWorkerStart {
 param(
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$FailureText,
  [Parameter(Mandatory=$true)][string]$WorkerRoot,
  [Parameter(Mandatory=$true)][string]$WorkerSourceRoot,
  [Parameter(Mandatory=$true)][string]$WorkerInvokerPath,
  [Parameter(Mandatory=$true)][string]$WorkerContractPath,
  [Parameter(Mandatory=$true)][string]$ExpectedInvokerHash,
  [Parameter(Mandatory=$true)][string]$ExpectedWorkerContractHash,
  [Parameter(Mandatory=$true)][string]$Owner
 )
 $receipt=Read-FactoryNoStartBounded $ReceiptPath|ConvertFrom-Json
 if($receipt.kind -cne 'factory-uia-slot-no-start-v1' -or $receipt.root -cne $WorkerRoot -or $receipt.lockOwner -cne $Owner -or $receipt.processStartReached -ne $false -or $receipt.contractFailureBeforeWorkerStart -ne $true){throw 'Definite no-worker-start receipt fields invalid'}
 if($receipt.PSObject.Properties.Name -notcontains 'attempted' -or $receipt.PSObject.Properties.Name -notcontains 'noInvocationConfirmed' -or $receipt.noInvocationConfirmed -ne (-not [bool]$receipt.attempted)){throw 'No-start attempted/invocation lineage mismatch'}
 if($FailureText -notmatch '(?i)(worker-contract\.json).*(cannot find|does not exist|not found|missing)|(cannot find|does not exist|not found|missing).*(worker-contract\.json)'){throw 'Exact pre-start contract failure absent'}
 foreach($path in @($WorkerRoot,(Join-Path $WorkerRoot 'worker-launch-attempt.json'),(Join-Path $WorkerRoot 'config.json'),(Join-Path $WorkerRoot 'owned-worker.json'),(Join-Path $WorkerRoot 'final-start.json'))){if(Test-Path -LiteralPath $path){throw ('Worker-start artifact present: '+$path)}}
 $invokerText=Read-FactoryNoStartBounded $WorkerInvokerPath;$contractText=Read-FactoryNoStartBounded $WorkerContractPath
 if(-not (Test-FactoryNoStartHash (Get-FactoryNoStartHash $WorkerInvokerPath) $ExpectedInvokerHash) -or -not (Test-FactoryNoStartHash (Get-FactoryNoStartHash $WorkerContractPath) $ExpectedWorkerContractHash)){throw 'Pinned worker source drift'}
 $contractMatch=[regex]::Match($invokerText,'(?m)Get-Content[^\r\n]*worker-contract\.json');$startIndex=$invokerText.IndexOf('[Diagnostics.Process]::Start',[StringComparison]::Ordinal)
 if(-not $contractMatch.Success -or $startIndex -lt 0 -or $contractMatch.Index -ge $startIndex -or $invokerText -notmatch '\$SourceRoot' -or $contractText -notmatch 'sourceBindings'){throw 'Pinned worker contract read-before-start proof absent'}
 [ordered]@{kind='factory-uia-definite-no-worker-start-v1';status='admitted-prestart-failure';attempted=[bool]$receipt.attempted;processStartReached=$false;owner=$Owner;receiptPath=$ReceiptPath;workerRoot=$WorkerRoot;failure=$FailureText;workerInvokerHash=(Get-FactoryNoStartHash $WorkerInvokerPath);workerContractHash=(Get-FactoryNoStartHash $WorkerContractPath);artifactAbsence=$true;qualification='release-only; no native worker or capture qualification'}
}
