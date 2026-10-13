# Source controls for generic Rectangle integration guard. No native or file mutation.
param([Parameter(Mandatory=$true)][string]$GuardPath,[Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$SourceInputsPath)
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath($GuardPath))
$source=Get-Content -Raw -LiteralPath $SourceInputsPath|ConvertFrom-Json
function Copy-Source($Value){$Value|ConvertTo-Json -Depth 30|ConvertFrom-Json}
function Expect-Reject([string]$Name,[scriptblock]$Action){try{& $Action;throw "fault accepted: $Name"}catch{if($_.Exception.Message -like "fault accepted:*"){throw};[ordered]@{name=$Name;rejected=$true}}}
Assert-FactoryIntegrationSources $Root $source|Out-Null
$faults=@()
$tuple=Get-RectangleJson (Assert-RectangleRef $source.tupleRef 'tuple')
$context=Get-RectangleJson (Assert-RectangleRef $source.contextRef 'context')
$wrongContextHash=Copy-Source $source;$wrongContextHash.contextRef.sha256='sha256:'+'3'*64;$faults+=Expect-Reject 'wrong-context-hash' {Assert-FactoryIntegrationSources $Root $wrongContextHash|Out-Null}
$wrongContextBytes=Copy-Source $source;$wrongContextBytes.contextRef.bytes=[int64]$source.contextRef.bytes+1;$faults+=Expect-Reject 'wrong-context-bytes' {Assert-FactoryIntegrationSources $Root $wrongContextBytes|Out-Null}
$missingContextIdentity=Copy-Source $context;$missingContextIdentity.tupleID=$null;$faults+=Expect-Reject 'missing-context-identity' {Assert-RectangleContextIdentity $missingContextIdentity $source $tuple|Out-Null}
$wrongSource=Copy-Source $source;$wrongSource.sourceHash='sha256:'+'0'*64;$faults+=Expect-Reject 'wrong-source' {Assert-FactoryIntegrationSources $Root $wrongSource|Out-Null}
$wrongHost=Copy-Source $source;$wrongHost.exeHash='0'*64;$faults+=Expect-Reject 'wrong-host' {Assert-FactoryIntegrationSources $Root $wrongHost|Out-Null}
$wrongCase=Copy-Source $source;$wrongCase.caseID='wrong-rectangle-case';$faults+=Expect-Reject 'wrong-case' {Assert-FactoryIntegrationSources $Root $wrongCase|Out-Null}
$wrongReceipt=Copy-Source $source;$wrongReceipt.compileReceiptHash='1'*64;$faults+=Expect-Reject 'wrong-receipt' {Assert-FactoryIntegrationSources $Root $wrongReceipt|Out-Null}
$wrongRenderer=Copy-Source $source;$wrongRenderer.rendererSha256='2'*64;$faults+=Expect-Reject 'wrong-renderer' {Assert-FactoryIntegrationSources $Root $wrongRenderer|Out-Null}
$doubleRenderer=Copy-Source $source;$doubleRenderer.rendererSha256='sha256:sha256:' + ('3'*64);$faults+=Expect-Reject 'double-renderer-prefix' {Assert-FactoryIntegrationSources $Root $doubleRenderer|Out-Null}
$malformedRenderer=Copy-Source $source;$malformedRenderer.rendererSha256='sha256:' + ('g'*64);$faults+=Expect-Reject 'malformed-renderer-prefix' {Assert-FactoryIntegrationSources $Root $malformedRenderer|Out-Null}
$wrongCount=Copy-Source $source;$wrongCount.count=if($source.count -eq 20){1}else{20};$faults+=Expect-Reject 'wrong-count' {Assert-FactoryIntegrationSources $Root $wrongCount|Out-Null}
if($source.captures){$wrongIDs=Copy-Source $source;$wrongIDs.captures[0].captureID='capture/not-32-hex';$faults+=Expect-Reject 'wrong-capture-id' {Assert-FactoryIntegrationSources $Root $wrongIDs|Out-Null}}
@{kind='factory-rectangle-integration-controls-v1';status='SOURCE_CONTROLS_DEFINED';faultControls=$faults}|ConvertTo-Json -Depth 8
