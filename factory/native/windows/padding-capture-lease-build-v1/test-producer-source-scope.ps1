# Production source membership controls; file fixtures only, no child/compiler/native calls.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh source-scope fixture required'}
. (Join-Path $PSScriptRoot 'producer-source-scope.ps1')
$actual=@(Get-FactoryProducerScripts $PSScriptRoot)
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$rows=@()
foreach($mode in @('positive','generated-output','missing','extra','equal-count-wrong')){
 $dir=Join-Path $OutputRoot $mode;New-Item -ItemType Directory -Path $dir|Out-Null
 foreach($file in $actual){$relative=$file.FullName.Substring($PSScriptRoot.Length+1);$to=Join-Path $dir $relative;New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force|Out-Null;Copy-Item -LiteralPath $file.FullName -Destination $to}
 switch($mode){
  'generated-output' {$generated=Join-Path $dir 'stream-admission-faults\example';New-Item -ItemType Directory $generated|Out-Null;[IO.File]::WriteAllText((Join-Path $generated 'generated.ps1'),'# synthetic fixture')}
  'missing' {Move-Item -LiteralPath (Join-Path $dir 'preflight.ps1') -Destination (Join-Path $dir 'retained-preflight.txt')}
  'extra' {[IO.File]::WriteAllText((Join-Path $dir 'extra.ps1'),'# synthetic')}
  'equal-count-wrong' {Move-Item -LiteralPath (Join-Path $dir 'preflight.ps1') -Destination (Join-Path $dir 'wrong.ps1')}
 }
 $rejected=$false;try{$set=@(Get-FactoryProducerScripts $dir)}catch{$rejected=$true}
 $expectedReject=$mode -cin @('missing','extra','equal-count-wrong')
 if($rejected -ne $expectedReject){throw ('Source membership fault wrong disposition '+$mode)}
 $rows+=@{mode=$mode;rejected=$rejected;synthetic=$true}
}
ConvertTo-Json -InputObject @($rows) -Depth 12|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
