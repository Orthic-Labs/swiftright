# Runs actual production admission after real pure-control & AST output generation; no compiler/native calls.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$results=Join-Path $root 'control-results'
$fixtures=Join-Path $root 'control-fixtures'
if((Test-Path -LiteralPath $results) -or (Test-Path -LiteralPath $fixtures)){throw 'Fresh seeded v2 control directories required'}
New-Item -ItemType Directory -Path $results|Out-Null
New-Item -ItemType Directory -Path $fixtures|Out-Null
& (Join-Path $root 'pure-controls\test-cleanup.ps1') -Output (Join-Path $results 'cleanup-controls.json')
& (Join-Path $root 'pure-controls\test-host-inputs.ps1') -OutputRoot (Join-Path $results 'host-fixtures')
Copy-Item -LiteralPath (Join-Path $results 'host-fixtures\controls.json') -Destination (Join-Path $results 'host-input-controls.json')
& (Join-Path $root 'pure-controls\parse-controls.ps1') -Output (Join-Path $results 'parse-controls.json')
& (Join-Path $root 'pure-controls\test-integer-admission.ps1') -Output (Join-Path $results 'integer-controls.json')
& (Join-Path $root 'pure-controls\reserved-assignment-lint.ps1') -Output (Join-Path $results 'reserved-lint.json')
. (Join-Path $root 'control-admission.ps1')
$hostHelper=[IO.Path]::GetFullPath((Join-Path $root 'shared\host-inputs.ps1'))
# This is actual production function on actual generated control results, before any fixture mutation.
Assert-CompletedBuildControls $root $hostHelper
$actualPassed=$true
function New-AdmissionFixture([string]$name) {
 $dir=Join-Path $fixtures $name
 New-Item -ItemType Directory -Path (Join-Path $dir 'control-results')|Out-Null
 New-Item -ItemType Directory -Path (Join-Path $dir 'pure-controls')|Out-Null
 foreach($rel in @('build-hosts-v2.ps1','cleanup-decision.ps1','control-admission.ps1','pure-controls\test-cleanup.ps1','pure-controls\test-host-inputs.ps1','run-controls.ps1','pure-controls\reserved-assignment-lint.ps1','pure-controls\parse-controls.ps1','pure-controls\test-integer-admission.ps1')){
  Copy-Item -LiteralPath (Join-Path $root $rel) -Destination (Join-Path $dir $rel)
 }
 foreach($nameFile in @('cleanup-controls.json','host-input-controls.json')){
  Copy-Item -LiteralPath (Join-Path $results $nameFile) -Destination (Join-Path $dir ('control-results\'+$nameFile))
 }
 $decodedRows=Get-Content -LiteralPath (Join-Path $results 'parse-controls.json') -Raw|ConvertFrom-Json
 $parseRows=@($decodedRows)
 foreach($row in $parseRows){
  $relative=$row.path.Substring($root.Length+1)
  $row.path=Join-Path $dir $relative
 }
 ConvertTo-Json -InputObject @($parseRows) -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'control-results\parse-controls.json')
 return $dir
}
function Write-Control([string]$path,$value){ConvertTo-Json -InputObject $value -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $path}
$positive=New-AdmissionFixture 'positive'
Assert-CompletedBuildControls $positive $hostHelper
$faultRows=@()
foreach($name in @('missing-cleanup','stale-cleanup','failed-cleanup','failed-host','failed-parser','stale-parser','bool-positive-count')){
 $dir=New-AdmissionFixture $name
 $cleanupFile=Join-Path $dir 'control-results\cleanup-controls.json'
 $hostFile=Join-Path $dir 'control-results\host-input-controls.json'
 $parseFile=Join-Path $dir 'control-results\parse-controls.json'
 if($name -eq 'missing-cleanup'){
  # No delete: rename original to retained evidence; production path becomes missing.
  Move-Item -LiteralPath $cleanupFile -Destination (Join-Path $dir 'control-results\cleanup-controls.retained.json')
 } elseif($name -in @('stale-cleanup','failed-cleanup','bool-positive-count')){
  $value=Get-Content -LiteralPath $cleanupFile -Raw|ConvertFrom-Json
  if($name -eq 'stale-cleanup'){$value.helperSha256='0'*64}
  if($name -eq 'failed-cleanup'){$value.faults[0].rejected=$false}
  if($name -eq 'bool-positive-count'){$value.positiveCases=$true}
  Write-Control $cleanupFile $value
 } elseif($name -eq 'failed-host'){
  $value=Get-Content -LiteralPath $hostFile -Raw|ConvertFrom-Json;$value.pass=$false;Write-Control $hostFile $value
 } else {
  $decodedFaultRows=Get-Content -LiteralPath $parseFile -Raw|ConvertFrom-Json
  $value=@($decodedFaultRows)
  if($name -eq 'failed-parser'){$value[0].errors=@('synthetic parse failure')}
  if($name -eq 'stale-parser'){$value[0].sha256='0'*64}
  Write-Control $parseFile @($value)
 }
 $caught=$false;$reason=$null
 try{Assert-CompletedBuildControls $dir $hostHelper}catch{$caught=$true;$reason=[string]$_}
 if(-not $caught){throw ('Production admission accepted fault: '+$name)}
 $faultRows+=@{name=$name;rejected=$true;reason=$reason}
}
@{kind='actual-production-admission-controls-v3';actualGeneratedOutputsPassed=$actualPassed;fixturePositivePassed=$true;faults=$faultRows;admissionHelperSha256=(Get-FileHash -LiteralPath (Join-Path $root 'control-admission.ps1')).Hash.ToLowerInvariant();compilerInvocations=0;nativeCalls=0;fixturesRetained=$true}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $results 'admission-controls.json')

Assert-AdmissionInvocationProof $root
