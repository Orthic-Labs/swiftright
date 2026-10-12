# Source-only controls for Circle runtimeProof. Root may run after staging.
param(
 [Parameter(Mandatory=$true)][string]$IntegrationSource,
 [Parameter(Mandatory=$true)][string]$CaptureSource,
 [Parameter(Mandatory=$true)][string]$IssuerSource,
 [string]$ControlRoot=(Join-Path $PSScriptRoot '.runtime-closure-controls-v1')
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Read-Bounded([string]$Path,[int64]$Max=2097152){
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or $i.LinkType -or $i.Length -gt $Max){throw 'bounded regular source required'}
 return Get-Content -Raw -LiteralPath $i.FullName
}
foreach($p in @($IntegrationSource,$CaptureSource,$IssuerSource)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw 'Circle runtime closure source missing'}}
$integration=Read-Bounded $IntegrationSource;$capture=Read-Bounded $CaptureSource;$issuer=Read-Bounded $IssuerSource
if($integration -notmatch 'function Assert-CircleRuntimeProofFields' -or $integration -notmatch 'Assert-CircleRuntimeProofFields \$SourceInputs'){throw 'production runtime proof predicate missing'}
foreach($marker in @('Assert-CircleRuntimeClosure','runtimeAssets','. \$runtimeVerifier','. \$hostInputs')){if($capture -notmatch [regex]::Escape($marker)){throw ('capture closure marker missing: '+$marker)}}
foreach($marker in @('runtimeProof','runtimeSourceTreeRef','runtimeSourceReceiptRef','runtimeVerifierRef','hostInputsRef')){if($issuer -notmatch [regex]::Escape($marker)){throw ('issuer runtime proof marker missing: '+$marker)}}
if($capture -match 'plan\.runtimeVerifierHash' -or $issuer -match 'plan\.runtimeVerifierHash'){throw 'absent plan runtimeVerifierHash consumed'}
. $IntegrationSource
$root=[IO.Path]::GetFullPath($ControlRoot)
if(Test-Path -LiteralPath $root){throw 'fresh control root required'}
New-Item -ItemType Directory -Path $root -Force|Out-Null
$tree=Join-Path $root 'runtime-source-tree.json';$receipt=Join-Path $root 'runtime-source-receipt.json';$verifier=Join-Path $root 'verify-runtime-source.ps1';$host=Join-Path $root 'host-inputs.ps1'
$utf8=New-Object Text.UTF8Encoding($false);[IO.File]::WriteAllText($tree,'[]',$utf8);[IO.File]::WriteAllText($receipt,'{}',$utf8);[IO.File]::WriteAllText($verifier,'# verifier',$utf8);[IO.File]::WriteAllText($host,'# host',$utf8)
function Ref([string]$Path){$i=Get-Item -LiteralPath $Path -Force;[pscustomobject]@{path=$i.FullName;sha256=('sha256:'+((Get-CircleHash $i.FullName)));bytes=[int64]$i.Length}}
$positive=[pscustomobject]@{runtimeSourceCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b';runtimeSourceTreeHash='sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e';runtimeSourceReceiptHash='sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7';runtimeSourceTreeRef=(Ref $tree);runtimeSourceReceiptRef=(Ref $receipt);runtimeVerifierRef=(Ref $verifier);hostInputsRef=(Ref $host)}
function Invoke-Production([object]$Proof){Assert-CircleRuntimeProofFields ([pscustomobject]@{runtimeProof=$Proof})|Out-Null}
Invoke-Production $positive
$faults=@('missing-verifier-ref','wrong-verifier-hash','wrong-verifier-bytes','missing-tree-ref','wrong-receipt-path','wrong-commit','wrong-tree-hash','wrong-receipt-hash')
foreach($name in $faults){$f=ConvertFrom-Json (ConvertTo-Json -Depth 12 $positive);switch($name){'missing-verifier-ref'{$f.runtimeVerifierRef=$null};'wrong-verifier-hash'{$f.runtimeVerifierRef.sha256='sha256:'+('f'*64)};'wrong-verifier-bytes'{$f.runtimeVerifierRef.bytes=[int64]$f.runtimeVerifierRef.bytes+1};'missing-tree-ref'{$f.runtimeSourceTreeRef=$null};'wrong-receipt-path'{$f.runtimeSourceReceiptRef.path=$verifier};'wrong-commit'{$f.runtimeSourceCommit='0'*40};'wrong-tree-hash'{$f.runtimeSourceTreeHash='sha256:'+('a'*64)};'wrong-receipt-hash'{$f.runtimeSourceReceiptHash='sha256:'+('b'*64)}};$accepted=$false;try{Invoke-Production $f;$accepted=$true}catch{};if($accepted){throw ('fault accepted: '+$name)}}
[ordered]@{kind='factory-circle-runtime-closure-controls-v2';status='SOURCE_CONTROLS_PASS';nativeActions=0;compilerActions=0;positive='production Assert-CircleRuntimeProofFields + bounded refs';faultsRejected=$faults}|ConvertTo-Json -Depth 8
