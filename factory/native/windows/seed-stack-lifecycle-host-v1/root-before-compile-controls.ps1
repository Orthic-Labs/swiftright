# Actual Windows AST & pure controls only. No compiler, executable or native launch.
$ErrorActionPreference='Stop'
$repoRoot='D:\Claude\swiftright'
$expectedRoot=Join-Path $repoRoot 'factory\native\windows\seed-stack-lifecycle-host-v1'
if([IO.Path]::GetFullPath($PSScriptRoot) -cne $expectedRoot){throw 'Exact lifecycle control directory required'}
$stagePath=Join-Path $PSScriptRoot 'root-stage-manifest.json'
$stageSha='fada5ea5455bce12333823d51760563eaf5855c26613bc90710fb4e1edb27d10'
function Assert-LifecycleControlInputs {
 if((Get-FileHash -LiteralPath $stagePath).Hash.ToLowerInvariant() -cne $stageSha){throw 'Frozen lifecycle stage drift'}
 $stage=Get-Content -LiteralPath $stagePath -Raw|ConvertFrom-Json
 $members=@($stage.files)
 if($members.Count -ne 35){throw 'Frozen lifecycle membership drift'}
 $seen=@{}
 foreach($member in $members){
  if($member.path -isnot [string] -or $seen.ContainsKey($member.path)){throw 'Invalid/duplicate lifecycle input'}
  $seen[$member.path]=$true
  $path=[IO.Path]::GetFullPath((Join-Path $repoRoot $member.path))
  if(-not $path.StartsWith($repoRoot+'\',[StringComparison]::Ordinal)){throw 'Lifecycle input escapes repository'}
  if(($member.bytes -isnot [int] -and $member.bytes -isnot [long]) -or $member.bytes -lt 0){throw 'Invalid lifecycle input size'}
  if((Get-Item -LiteralPath $path).Length -ne $member.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $member.sha256.Replace('sha256:','')){throw ('Lifecycle stage input drift: '+$member.path)}
 }
}
Assert-LifecycleControlInputs
$controlRoot=Join-Path $repoRoot 'factory\native\windows\round1-seeded-build-v2'
$hostHelper=Join-Path $repoRoot 'factory\native\windows\round1-seeded-hosts-v1\shared\host-inputs.ps1'
$ownHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
$out=Join-Path $PSScriptRoot 'root-before-compile-controls-r1'
if(Test-Path -LiteralPath $out){throw 'Fresh lifecycle control output required'}
New-Item -ItemType Directory -Path $out|Out-Null
$receiptPath=Join-Path $out 'receipt.json'
$record=[ordered]@{kind='actual-lifecycle-before-compile-controls-v1';entrySha256=$ownHash;stageSha256=$stageSha;startedAt=[DateTimeOffset]::UtcNow.ToString('o');finishedAt=$null;passed=$false;error=$null;astPassed=$false;cleanupPassed=$false;hostInputsPassed=$false;integerPassed=$false;productionAdmissionPassed=$false;productionInvocationProofPassed=$false;compilerInvocations=0;nativeCalls=0;oldControlOutputsOverwritten=$false;files=@()}
function Save-LifecycleControlReceipt {$record|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 -LiteralPath $receiptPath}
Save-LifecycleControlReceipt
try {
 $astRows=@()
 foreach($name in @('build-lifecycle.ps1','run-compile.ps1','root-before-compile-controls.ps1')){
  $path=Join-Path $PSScriptRoot $name;$tokens=$null;$parseErrors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  $astRows+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();errors=@($parseErrors|ForEach-Object{[string]$_})}
 }
 ConvertTo-Json -InputObject @($astRows) -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'ast-controls.json')
 if(@($astRows|Where-Object{$_.errors.Count -ne 0}).Count -ne 0){throw 'Lifecycle PowerShell AST errors'}
 $record.astPassed=$true;Save-LifecycleControlReceipt
 & (Join-Path $controlRoot 'pure-controls\test-cleanup.ps1') -Output (Join-Path $out 'cleanup-controls.json')
 $record.cleanupPassed=$true;Save-LifecycleControlReceipt
 & (Join-Path $controlRoot 'pure-controls\test-host-inputs.ps1') -OutputRoot (Join-Path $out 'host-fixtures')
 $record.hostInputsPassed=$true;Save-LifecycleControlReceipt
 & (Join-Path $controlRoot 'pure-controls\test-integer-admission.ps1') -Output (Join-Path $out 'integer-controls.json')
 $record.integerPassed=$true;Save-LifecycleControlReceipt
 # Actual immutable production admission & proof; outputs remain in original control directory.
 . (Join-Path $controlRoot 'control-admission.ps1')
 Assert-CompletedBuildControls $controlRoot $hostHelper
 $record.productionAdmissionPassed=$true;Save-LifecycleControlReceipt
 Assert-AdmissionInvocationProof $controlRoot
 $record.productionInvocationProofPassed=$true;Save-LifecycleControlReceipt
 Assert-LifecycleControlInputs
 if((Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant() -cne $ownHash){throw 'Lifecycle control entry drift'}
 $record.passed=$true
} catch {$record.error=[string]$_}
finally {
 $record.files=@(Get-ChildItem -LiteralPath $out -Recurse -File|Where-Object{$_.FullName -ne $receiptPath}|ForEach-Object{@{path=$_.FullName.Substring($out.Length+1);bytes=[long]$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
 $record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save-LifecycleControlReceipt
}
if(-not $record.passed){throw 'Lifecycle precompile controls failed; preserve raw outputs; compiler remains unrun'}
