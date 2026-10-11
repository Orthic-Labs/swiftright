# Offline Count20 proof controls. Requires completed Count1 evidence; never launches native host.
param(
 [Parameter(Mandatory=$true)][string]$CaptureRoot,
 [Parameter(Mandatory=$true)][string]$CompiledReceiptPath,
 [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
 [Parameter(Mandatory=$true)][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$ScratchRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'cleanup.ps1')
. (Join-Path $PSScriptRoot 'stream-seal.ps1')
. (Join-Path $PSScriptRoot 'first-proof.ps1')
function New-PaddingProofFixture([string]$Name) {
 $root=Join-Path $ScratchRoot $Name
 New-Item -ItemType Directory -Force -Path $root|Out-Null
 Copy-Item -LiteralPath (Join-Path $CaptureRoot 'coordinator-single-r1') -Destination $root -Recurse
 Copy-Item -LiteralPath (Join-Path $CaptureRoot 'actual-single-r1') -Destination $root -Recurse
 $controlPath=Join-Path $root 'coordinator-single-r1\coordinator.json';$control=Get-Content -Raw $controlPath|ConvertFrom-Json
 $control.runRoot=Join-Path $root 'actual-single-r1';$control|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 $controlPath
 return $root
}
function Invoke-PaddingProof([string]$Root,[string]$Receipt) {
 Assert-PaddingFirstCaptureProof -CaptureRoot $Root -CompiledReceiptPath $Receipt -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -ExpectedRunRoot (Join-Path $Root 'actual-single-r1')
}
function Expect-PaddingReject([string]$Name,[scriptblock]$Action,[string]$ExpectedMessage='') {
 try { & $Action; throw ('Fault control unexpectedly accepted: '+$Name) } catch {
  if($_.Exception.Message -like 'Fault control unexpectedly accepted:*'){throw}
  if($ExpectedMessage -and $_.Exception.Message -cne $ExpectedMessage){throw ('Fault control rejected '+$Name+' at unexpected gate: '+$_.Exception.Message)}
 }
}
if(Test-Path -LiteralPath $ScratchRoot){throw 'Scratch root must be fresh; no deletion permitted'}
New-Item -ItemType Directory -Force -Path $ScratchRoot|Out-Null
$baseline=$null
try {
 $baseline=New-PaddingProofFixture 'baseline'
 Invoke-PaddingProof $baseline $CompiledReceiptPath
 $sampleFault=New-PaddingProofFixture 'fault-pixel-bytes'
 $samplePath=Join-Path $sampleFault 'actual-single-r1\native-01\native.printwindow.repeat.png'
 $bytes=[IO.File]::ReadAllBytes($samplePath);[IO.File]::WriteAllBytes($samplePath,[byte[]]($bytes + [byte]0))
 Expect-PaddingReject 'pixel sample raw bytes' {Invoke-PaddingProof $sampleFault $CompiledReceiptPath}
 $processFault=New-PaddingProofFixture 'fault-owned-process'
 $processPath=Join-Path $processFault 'actual-single-r1\native-01\owned-process.json';$process=Get-Content -Raw $processPath|ConvertFrom-Json;$process.pid=[int64]$process.pid+1;$process|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $processPath
 Expect-PaddingReject 'owned process row binding' {Invoke-PaddingProof $processFault $CompiledReceiptPath}
 $semanticFault=New-PaddingProofFixture 'fault-rehashed-pixel-repeat'
 $semanticDir=Join-Path $semanticFault 'actual-single-r1\native-01';$repeatPng=Join-Path $semanticDir 'native.printwindow.repeat.png'
 $repeatBytes=[IO.File]::ReadAllBytes($repeatPng);[IO.File]::WriteAllBytes($repeatPng,[byte[]]($repeatBytes + [byte]0));$repeatHash=(Get-FileHash -LiteralPath $repeatPng).Hash.ToLowerInvariant()
 $pixelPath=Join-Path $semanticDir 'native.pixels.json';$pixel=Get-Content -Raw $pixelPath|ConvertFrom-Json;@($pixel.samples|Where-Object{$_.path -ceq 'native.printwindow.repeat.png'})[0].sha256=$repeatHash;$pixel|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 $pixelPath;$pixelHash=(Get-FileHash -LiteralPath $pixelPath).Hash.ToLowerInvariant()
 $obsPath=Join-Path $semanticFault 'actual-single-r1\native-observation.json';$obsDecoded=Get-Content -Raw $obsPath|ConvertFrom-Json;$obsRows=@($obsDecoded);$obsFiles=@($obsRows[0].files);(@($obsFiles|Where-Object{$_.path -ceq 'native.printwindow.repeat.png'})[0]).sha256=$repeatHash;(@($obsFiles|Where-Object{$_.path -ceq 'native.pixels.json'})[0]).sha256=$pixelHash;$obsRows[0].files=$obsFiles;$obsRows|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 $obsPath
 Expect-PaddingReject 'coherent rehashed pixel repeat' {Invoke-PaddingProof $semanticFault $CompiledReceiptPath} 'First pixel repeat stability proof failed'
 $stdoutFault=New-PaddingProofFixture 'fault-host-predicate'
 [IO.File]::WriteAllText((Join-Path $stdoutFault 'actual-single-r1\native-01\host.stdout.txt'),'FACTORY_RENDERER_READY')
 Expect-PaddingReject 'host stdout predicate' {Invoke-PaddingProof $stdoutFault $CompiledReceiptPath}
 $receiptFault=Join-Path $ScratchRoot 'fault-receipt.json';Copy-Item -LiteralPath $CompiledReceiptPath -Destination $receiptFault
 $receiptBytes=[IO.File]::ReadAllBytes($receiptFault);[IO.File]::WriteAllBytes($receiptFault,[byte[]]($receiptBytes + [byte]0))
 Expect-PaddingReject 'compile receipt bytes' {Invoke-PaddingProof $baseline $receiptFault}
 [ordered]@{kind='padding-settled-first-proof-controls-v2';baseline='accepted';faults=@('pixel sample raw bytes','owned process row binding','coherent rehashed pixel repeat','host stdout predicate','compile receipt bytes');nativeLaunches=0;retries=0;pass=$true}|ConvertTo-Json -Depth 8
} finally {
 if(Test-Path -LiteralPath $ScratchRoot){
  $retirementRoot='D:\Claude\_factory-old-DELETE-ME';New-Item -ItemType Directory -Force -Path $retirementRoot|Out-Null
  $retained=Join-Path $retirementRoot ('padding-settled-first-proof-controls-'+[Guid]::NewGuid().ToString('N'));Move-Item -LiteralPath $ScratchRoot -Destination $retained
 }
}
