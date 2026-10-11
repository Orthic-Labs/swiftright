# Pure object gates + observed source-file byte faults. No compiler/process/renderer/window calls.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh lifecycle controls namespace required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
. (Join-Path $PSScriptRoot 'lifecycle-proof.ps1')
$package='D:\Claude\swiftright\factory\native\windows\seed-stack-lifecycle-host-v1\package'
$originalPlan=Get-Content -Raw -LiteralPath (Join-Path $package 'plan.json')
$originalMainHash=(Get-FileHash -LiteralPath (Join-Path $package 'Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant()
$originalAdapterHash=(Get-FileHash -LiteralPath (Join-Path (Split-Path $package -Parent) 'adapt-host.py')).Hash.ToLowerInvariant()
$planHash=(Get-FileHash -LiteralPath (Join-Path $package 'plan.json')).Hash.ToLowerInvariant()
$rows=@()
foreach($mode in @('normal','old-package','old-plan','wrong-main','wrong-adapter','wrong-scope','wrong-witness','wrong-case','eligible','tuple','numeric-lineage','old-parent-plan','old-parent-main','duplicate-main-binding','wrong-main-binding')){
 $plan=$originalPlan|ConvertFrom-Json;$p=$package;$ph=$planHash;$mh=$originalMainHash;$ah=$originalAdapterHash
 switch($mode){
  'old-package'{$p='D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\stack-overlay\package'}
  'old-plan'{$ph='4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b'}
  'wrong-main'{$mh='0'*64} 'wrong-adapter'{$ah='0'*64} 'wrong-scope'{$plan.diagnosticScope='seed-replay'}
  'wrong-witness'{$plan.sourceHash='sha256:'+('0'*64)} 'wrong-case'{$plan.case.id+='alias'}
  'eligible'{$plan.executionEligible=$true} 'tuple'{$plan.frozenTupleBound=$true}
  'numeric-lineage'{$plan.diagnosticLineage.witnessUnchanged=1} 'old-parent-plan'{$plan.diagnosticLineage.parentPlanSha256='sha256:'+('0'*64)}
  'old-parent-main'{$plan.diagnosticLineage.parentMainSha256='sha256:'+('0'*64)}
  'duplicate-main-binding'{$plan.sourceBindings+=@($plan.sourceBindings|Where-Object{$_.path -ceq 'Sources/FactoryProbe/main.swift'})}
  'wrong-main-binding'{($plan.sourceBindings|Where-Object{$_.path -ceq 'Sources/FactoryProbe/main.swift'}).sha256='sha256:'+('0'*64)}
 }
 $rejected=$false;try{Assert-LifecyclePlanObject $p $plan $ph $mh $ah}catch{$rejected=$true}
 if($rejected -ne ($mode -ne 'normal')){throw ('Lifecycle source control failed: '+$mode)}
 $rows+=[ordered]@{mode=$mode;rejected=$rejected;gate='production-plan-object'}
}
$plan=$originalPlan|ConvertFrom-Json;$exeHash='a'*64
$fixture=[ordered]@{kind='factory-lifecycle-diagnostic-compile-only-owned-handle-v1';diagnosticScope=$plan.diagnosticScope;diagnosticLineage=$plan.diagnosticLineage;exitCode=0;exeSubsystem=2;ownedExited=$true;streamDrainComplete=$true;timedOut=$false;nativeWindowOpened=$false;frozenTupleBound=$false;error=$null;cleanupError=$null;planSha256=$planHash;exeSha256=$exeHash;exePath=($package+'\build-lifecycle-v1-r1\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe');sourceHash=$plan.sourceHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;rendererSha256=$plan.rendererSha256;compilerHash=$plan.compilerHash}
$originalFixture=$fixture|ConvertTo-Json -Depth 20
foreach($mode in @('normal','old-compiler-kind','old-compiler-plan','wrong-compiler','wrong-exe','old-exe-route','exit-bool','pe-string','stream-incomplete','exit-numeric','timedout','cleanup-error','native-launched','wrong-compiled-scope','wrong-compiled-lineage','compiled-lineage-string')){
 $compiled=$originalFixture|ConvertFrom-Json
 switch($mode){
  'old-compiler-kind'{$compiled.kind='factory-compile-only-owned-handle-v2'} 'old-compiler-plan'{$compiled.planSha256='4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b'}
  'wrong-compiler'{$compiled.compilerHash='0'*64} 'wrong-exe'{$compiled.exeSha256='0'*64}
  'old-exe-route'{$compiled.exePath=$package+'\build-v2-r1\scratch\release\FactoryProbe.exe'} 'exit-bool'{$compiled.exitCode=$false} 'pe-string'{$compiled.exeSubsystem='2'}
  'stream-incomplete'{$compiled.streamDrainComplete=$false} 'exit-numeric'{$compiled.ownedExited=1} 'timedout'{$compiled.timedOut=$true} 'cleanup-error'{$compiled.cleanupError='failed'}
  'native-launched'{$compiled.nativeWindowOpened=$true} 'wrong-compiled-scope'{$compiled.diagnosticScope='seed-replay'}
  'wrong-compiled-lineage'{$compiled.diagnosticLineage.parentMainSha256='sha256:'+('0'*64)} 'compiled-lineage-string'{$compiled.diagnosticLineage.quitThresholdUnchanged='True'}
 }
 $rejected=$false;try{Assert-LifecycleCompileObject $package $plan $planHash $compiled $exeHash}catch{$rejected=$true}
 if($rejected -ne ($mode -ne 'normal')){throw ('Lifecycle compile control failed: '+$mode)}
 $rows+=[ordered]@{mode=$mode;rejected=$rejected;gate='production-compile-object'}
}
$copy=Join-Path $OutputRoot 'changed-main.swift'
Copy-Item -LiteralPath (Join-Path $package 'Sources\FactoryProbe\main.swift') -Destination $copy
[IO.File]::AppendAllText($copy,[Environment]::NewLine+'// injected observer byte fault')
$changedHash=(Get-FileHash -LiteralPath $copy).Hash.ToLowerInvariant();$rejected=$false
try{Assert-LifecyclePlanObject $package $plan $planHash $changedHash $originalAdapterHash}catch{$rejected=$true}
if(-not $rejected){throw 'Actual changed lifecycle observer bytes accepted'}
$rows+=[ordered]@{mode='actual-changed-main-bytes';rejected=$true;gate='production-plan-object';sha256=$changedHash}
[ordered]@{kind='actual-lifecycle-source-and-compile-binding-controls-v1';status='passed';syntheticCompileFixture=$true;sourceFilesObserved=$true;compilerInvocations=0;nativeWindows=0;rendererLoaded=$false;controls=$rows}|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
