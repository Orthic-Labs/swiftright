# Pure actual production schema + IO hash guard controls. No process/compiler/window.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls output required'}
. (Join-Path $PSScriptRoot 'mac-proof.ps1')
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$original=Get-Content -Raw (Join-Path $PSScriptRoot 'proof\source-join.json')
$expected=Get-Content -Raw (Join-Path $PSScriptRoot 'proof-contract.json')|ConvertFrom-Json
$selected=$expected.cases[0]
$plan=[pscustomobject]@{sourceHash=$selected.witnessHash;case=$selected.case;executionEligible=$false;hostMode='renderer'}
$results=@()
foreach($mode in @('normal','wrong-kind','numeric-true','not-eligible','compile-alias','parity','compiler-origin','case-missing','case-extra','case-duplicate','wrong-case','wrong-plan','wrong-witness','wrong-host','wrong-binary','run-missing','run-duplicate','run-string','wrong-raw','wrong-capture','scroll-status','package-alias','source-alias','plan-alias')){
 $proof=$original|ConvertFrom-Json;$currentPlan=$plan|ConvertTo-Json|ConvertFrom-Json;$package=$selected.package;$planHash=$selected.planHash.Replace('sha256:','')
 switch($mode){
  'wrong-kind'{$proof.kind='old'} 'numeric-true'{$proof.sourceReplayEligible=1} 'not-eligible'{$proof.sourceReplayEligible=$false}
  'compile-alias'{$proof.windowsCompileValidated=$true} 'parity'{$proof.nativeParity='pass'} 'compiler-origin'{$proof.compilerProcessOrigin='observed'}
  'case-missing'{$proof.cases=@($proof.cases|Select-Object -Skip 1)} 'case-extra'{$proof.cases+=@($proof.cases[0])} 'case-duplicate'{$proof.cases[1]=$proof.cases[0]}
  'wrong-case'{$proof.cases[0].case.id+='wrong'} 'wrong-plan'{$proof.cases[0].planHash='sha256:'+('0'*64)} 'wrong-witness'{$proof.cases[0].witnessHash='sha256:'+('0'*64)}
  'wrong-host'{$proof.cases[0].adaptedHostHash='sha256:'+('0'*64)} 'wrong-binary'{$proof.cases[0].binaryHash='sha256:'+('0'*64)}
  'run-missing'{$proof.cases[0].runs=@($proof.cases[0].runs|Select-Object -Skip 1)} 'run-duplicate'{$proof.cases[0].runs[1]=$proof.cases[0].runs[0]} 'run-string'{$proof.cases[0].runs[0].run='1'}
  'wrong-raw'{$proof.cases[0].runs[0].rawHash='sha256:'+('0'*64)} 'wrong-capture'{$proof.cases[0].runs[0].captureHash='sha256:'+('0'*64)}
  'scroll-status'{$proof.cases[4].runs[0].rawStatus='OBSERVED'} 'package-alias'{$package+='other'} 'source-alias'{$currentPlan.sourceHash='sha256:'+('0'*64)} 'plan-alias'{$planHash='0'*64}
 }
 $rejected=$false;try{Assert-SeedMacProofObject $proof $expected $package $currentPlan $planHash}catch{$rejected=$true}
 if($rejected -ne ($mode -ne 'normal')){throw ('Actual proof control failed '+$mode)}
 $results+=[ordered]@{mode=$mode;rejected=$rejected}
}
$copy=Join-Path $OutputRoot 'proof-copy.json';Copy-Item (Join-Path $PSScriptRoot 'proof\source-join.json') $copy
Assert-SeedProofFileHash $copy '9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3'
[IO.File]::AppendAllText($copy,' ');$rejected=$false
try{Assert-SeedProofFileHash $copy '9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3'}catch{$rejected=$true}
if(-not $rejected){throw 'Actual changed-byte hash gate failed'}
$results+=[ordered]@{mode='changed-proof-bytes';rejected=$rejected}
$results|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
