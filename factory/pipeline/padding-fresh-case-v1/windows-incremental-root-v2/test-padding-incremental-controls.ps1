# Production preflight controls; root runs this on Dell with no native actions.
param(
 [Parameter(Mandatory=$true)][string]$BuilderPath,
 [Parameter(Mandatory=$true)][string]$FreshPlanPath,
 [Parameter(Mandatory=$true)][string]$FreshInputRoot,
 [Parameter(Mandatory=$true)][string]$OperationalPackage,
 [Parameter(Mandatory=$true)][string]$OperationalScratch,
 [Parameter(Mandatory=$true)][string]$OperationalPlanPath,
 [Parameter(Mandatory=$true)][string]$OperationalReceiptPath,
 [Parameter(Mandatory=$true)][string]$CompilerPath,
 [Parameter(Mandatory=$true)][string]$RendererPath,
 [Parameter(Mandatory=$true)][string]$JobHelperPath,
 [Parameter(Mandatory=$true)][string]$BridgeRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath($ControlRoot);if(Test-Path -LiteralPath $root){throw 'ControlRoot must be fresh'};New-Item -ItemType Directory -Path $root|Out-Null
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function Json([string]$p){Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}
function CopyPlan([string]$name,[scriptblock]$Mutate){$dst=Join-Path $root ($name+'.json');$d=Json $FreshPlanPath;&$Mutate $d;[IO.File]::WriteAllText($dst,($d|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false));return $dst}
$base=@{FreshPlanPath=$FreshPlanPath;FreshInputRoot=$FreshInputRoot;OperationalPackage=$OperationalPackage;OperationalScratch=$OperationalScratch;OperationalPlanPath=$OperationalPlanPath;OperationalReceiptPath=$OperationalReceiptPath;CompilerPath=$CompilerPath;RendererPath=$RendererPath;JobHelperPath=$JobHelperPath;BridgeRoot=$BridgeRoot;Phase='preflight';PreflightOnly=$true}
$rows=@()
function Case([string]$Name,[hashtable]$Args,[bool]$Accept){$ok=$false;$detail='';try{& $BuilderPath @Args|Out-Null;$ok=$true}catch{$detail=[string]$_.Exception.Message};$pass=($ok -eq $Accept);$script:rows+=[pscustomobject]@{name=$Name;accepted=$ok;expectedAccepted=$Accept;passed=$pass;detail=$detail};if(-not $pass){throw "control failed: $Name ($detail)"}}
$basePlanHash=Hash $FreshPlanPath
$a=@{}+$base;$a.FreshPlanSha256=$basePlanHash;$a.OutputRoot=(Join-Path $root 'positive');Case 'positive-preflight' $a $true
$a=@{}+$base;$a.FreshPlanSha256=('0'*64);$a.OutputRoot=(Join-Path $root 'wrong-plan-hash');Case 'wrong-plan-hash' $a $false
$p=CopyPlan 'wrong-source-hash' {[array]$this=$args[0];$this.sourceBindings[0].sha256='sha256:'+('0'*64)};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-source-hash-out');Case 'wrong-source-hash' $a $false
$p=CopyPlan 'wrong-case' {$args[0].case.id='swiftui.padding-frame.recipe.wrong'};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-case-out');Case 'wrong-case-identity' $a $false
$p=CopyPlan 'wrong-host' {$args[0].expectedHostHashes.windows='0'*64};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-host-out');Case 'wrong-host-hash' $a $false
$p=CopyPlan 'wrong-memory' {$args[0].memoryBudget.bytes=536870912};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-memory-out');Case 'wrong-memory-cap' $a $false
$a=@{}+$base;$a.FreshPlanSha256=$basePlanHash;$a.OperationalPackage=(Join-Path $root 'missing-package');$a.OutputRoot=(Join-Path $root 'wrong-package-out');Case 'wrong-operational-package' $a $false
$a=@{}+$base;$a.FreshPlanSha256=$basePlanHash;$a.OperationalScratch=(Join-Path $root 'missing-scratch');$a.OutputRoot=(Join-Path $root 'wrong-scratch-out');Case 'wrong-operational-cache' $a $false
$p=CopyPlan 'wrong-kind' {$args[0].kind='factory-padding-capture-lease-source-plan'};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-kind-out');Case 'wrong-plan-kind' $a $false
$p=CopyPlan 'wrong-job-flag' {$args[0].memoryBudget.jobLimitFlags=256};$a=@{}+$base;$a.FreshPlanPath=$p;$a.FreshPlanSha256=(Hash $p);$a.OutputRoot=(Join-Path $root 'wrong-job-flag-out');Case 'wrong-job-flags' $a $false
$receipt=[ordered]@{kind='factory-padding-incremental-preflight-controls-v1';status='SOURCE_CONTROLS_PASS';cases=$rows.Count;rows=$rows;nativeActions=0;controlRoot=$root};$receipt|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $root 'controls.json') -Encoding UTF8;Write-Output ($receipt|ConvertTo-Json -Depth 16)
