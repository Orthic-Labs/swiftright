[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$IntegrationScript,
 [Parameter(Mandatory=$true)][string]$MetadataPath,
 [Parameter(Mandatory=$true)][string]$MetadataHash,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$CompileHash,
 [Parameter(Mandatory=$true)][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SerializerHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot
)
$ErrorActionPreference='Stop'
. (Get-Item -LiteralPath $IntegrationScript).FullName
$nativeActions=0
function Write-ControlJson($Value,[string]$Path){$Value|ConvertTo-Json -Depth 64 -Compress|Set-Content -LiteralPath $Path -Encoding utf8}
function Expect-Reject([string]$Name,[scriptblock]$Call){
 try{& $Call;throw ('control accepted fault: '+$Name)}catch{if($_.Exception.Message -like 'control accepted fault:*'){throw};[ordered]@{name=$Name;rejected=$true;reason=$_.Exception.Message}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('factory-v6-headless-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
 $positive=Assert-LeaseIssuedMetadata -Path $MetadataPath -Hash $MetadataHash -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot
 $faults=[System.Collections.Generic.List[object]]::new()
 $m=Get-Content -Raw -LiteralPath $MetadataPath|ConvertFrom-Json
 $p=Join-Path $temp 'raw-ref.json';$m.plan.sha256='sha256:'+('0'*64);Write-ControlJson $m $p
 $faults.Add((Expect-Reject 'mutated-plan-raw-ref' {Assert-LeaseIssuedMetadata -Path $p -Hash (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot}))|Out-Null
 $m=Get-Content -Raw -LiteralPath $MetadataPath|ConvertFrom-Json;$m.case.id='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258';$p=Join-Path $temp 'old-case.json';Write-ControlJson $m $p
 $faults.Add((Expect-Reject 'historical-case-id' {Assert-LeaseIssuedMetadata -Path $p -Hash (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot}))|Out-Null
 $m=Get-Content -Raw -LiteralPath $MetadataPath|ConvertFrom-Json;$m.captures[0].captureID='0123456789abcdef0123456789abcdef';$p=Join-Path $temp 'old-capture-id.json';Write-ControlJson $m $p
 $faults.Add((Expect-Reject 'unprefixed-capture-id' {Assert-LeaseIssuedMetadata -Path $p -Hash (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot}))|Out-Null
 $m=Get-Content -Raw -LiteralPath $MetadataPath|ConvertFrom-Json;$m.captures[0].run=21;$p=Join-Path $temp 'wrong-run-index.json';Write-ControlJson $m $p
 $faults.Add((Expect-Reject 'wrong-run-index' {Assert-LeaseIssuedMetadata -Path $p -Hash (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot}))|Out-Null
 $faults.Add((Expect-Reject 'wrong-executable-hash' {Assert-LeaseIssuedMetadata -Path $MetadataPath -Hash $MetadataHash -RunRoot $RunRoot -Count 20 -CompileHash $CompileHash -ExeHash ('0'*64) -SerializerHash $SerializerHash -ProducerRoot $ProducerRoot}))|Out-Null
 [ordered]@{schema='factory-windows-r11-source-v6-headless-controls';status='PASS';baselineAccepted=$true;faultControls=@($faults);nativeWindowActions=$nativeActions;compilerActions=0;lockActions=0;remoteActions=0}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
