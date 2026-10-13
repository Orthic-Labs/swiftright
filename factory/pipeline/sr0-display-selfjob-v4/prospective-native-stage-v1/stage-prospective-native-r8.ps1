# Source-only fresh SR0 r8 materializer. It creates no task, process, lock or qualification receipt.
[CmdletBinding()]
param(
  [string]$RepositoryRoot='D:\Claude\swiftright',
  [string]$StageRoot='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r8',
  [string]$Base='D:\Claude\swiftright\.work\sr0-r12-workload-v1',
  [string]$FactoryRoot='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r8',
  [string]$ControlRoot='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\controls-r8',
  [string]$LockPath='D:\Claude\desktop.lock',
  [switch]$Force
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxSourceBytes=67108864
function Require([bool]$ok,[string]$message){if(-not $ok){throw $message}}
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Require-Source([string]$p){Require (Test-Path -LiteralPath $p -PathType Leaf) "source missing: $p";$i=Get-Item -LiteralPath $p -Force;Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "source reparse point: $p";Require ($i.Length -le $MaxSourceBytes) "source exceeds bound: $p";return $i}
function Copy-Fresh([string]$source,[string]$destination){$null=Require-Source $source;$parent=Split-Path -Parent $destination;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};Require (-not(Test-Path -LiteralPath $destination)) "destination already exists: $destination";$tmp="$destination.$PID.$([guid]::NewGuid().ToString('N')).tmp";$in=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$out=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$in.CopyTo($out,65536);$out.Flush($true)}finally{$out.Dispose();$in.Dispose()};[IO.File]::Move($tmp,$destination)}
function Add-Copy([Collections.Generic.List[object]]$list,[string]$name,[string]$source,[string]$relative){$src=Full $source;$dst=Full (Join-Path $StageRoot $relative);Copy-Fresh $src $dst;$i=Get-Item -LiteralPath $dst -Force;$list.Add([ordered]@{name=$name;path=$relative.Replace('\','/');source=$src;bytes=[int64]$i.Length;sha256=(Hash $dst)})|Out-Null}
function Add-External([Collections.Generic.List[object]]$list,[string]$name,[string]$source){$src=Full $source;$i=Require-Source $src;$list.Add([ordered]@{name=$name;path=$src;source=$src;bytes=[int64]$i.Length;sha256=(Hash $src);external=$true})|Out-Null}
Require (-not (Test-Path -LiteralPath $StageRoot)) "fresh stage required: $StageRoot";Require (-not (Test-Path -LiteralPath $FactoryRoot)) "fresh run root required: $FactoryRoot";Require (-not (Test-Path -LiteralPath $ControlRoot)) "fresh control root required: $ControlRoot"
[IO.Directory]::CreateDirectory($StageRoot)|Out-Null;[IO.Directory]::CreateDirectory($FactoryRoot)|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $FactoryRoot 'run'))|Out-Null;[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null;$controlStage=Full (Join-Path $StageRoot 'control-root');[IO.Directory]::CreateDirectory($controlStage)|Out-Null
$repo=Full $RepositoryRoot;$files=[Collections.Generic.List[object]]::new()
# Admitted v5 coordinator, receipt parser, kernel helpers, wrapper and display controls.
Add-Copy $files 'coordinator' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/coordinator-selfjob-v5.ps1') 'coordinator-selfjob-v5.ps1'
Add-Copy $files 'parser' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/receipt-parser-v4.ps1') 'receipt-parser-v4.ps1'
Add-Copy $files 'helper' (Join-Path $repo 'factory/pipeline/pilot-next-source-v1/windows-capture-v1/Sr0OwnedJobProcess-v15.cs') 'Sr0OwnedJobProcess-v15.cs'
Add-Copy $files 'launcherHelper' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/Sr0LauncherOwnedJobProcess-v4.cs') 'Sr0LauncherOwnedJobProcess-v4.cs'
Add-Copy $files 'frozenTask' (Join-Path $repo 'qualification/tuple12-takeover/workload-controls-v8/task-workload.ps1') 'task-workload-v8.ps1'
Add-Copy $files 'collector' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/collector-selfjob-v7-drain-pidjoin.ps1') 'collector-selfjob-v7-drain-pidjoin.ps1'
Add-Copy $files 'drainTask' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/task-workload-drain-v1.ps1') 'task-workload-drain-v1.ps1'
Add-Copy $files 'drainHelper' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/workload-drain-helper-v1.ps1') 'workload-drain-helper-v1.ps1'
Add-Copy $files 'identityHelper' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/workload-identity-v6.ps1') 'workload-identity-v6.ps1'
Add-Copy $files 'controlSampler' (Join-Path $repo 'qualification/tuple12-takeover/workload-controls-v8/sample-resources.ps1') 'control-root/sample-resources.ps1'
Add-Copy $files 'controls-drain' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/test-workload-drain-controls-r10.ps1') 'test-workload-drain-controls-r10.ps1'
Add-Copy $files 'drainControls' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/run-source-controls-r8.ps1') 'run-source-controls-r8.ps1'
# Worker/scheduler are fresh copies whose manifest includes drain-task/helper/identity pins.
Add-Copy $files 'worker' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/run-once-v7.ps1') 'run-once-v7.ps1'
Add-Copy $files 'schedule' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/schedule-once-v7.ps1') 'schedule-once-v7.ps1'
Add-Copy $files 'wrapper' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/launch-once-v7.vbs') 'launch-once-v7.vbs'
# Preserve source controls as inputs; this stager does not execute them.
$oldStage=Join-Path $repo 'factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6'
foreach($n in @('test-collector-forced-stop-controls-v1.ps1','test-coordinator-forced-stop-controls-v1.ps1','test-v5-wrapper-controls-v1.ps1','display-parser-adapter-v1.ps1','test-display-parser-adapter-controls-v1.ps1','observer-source-v5-r1.ps1','test-observer-source-v5-controls-r1.ps1','test-forced-stop-admission-v5.ps1','materialize-analysis-inputs-v1.ps1','test-materialize-analysis-inputs-controls-v1.ps1','analyze_workload-v3-adapter-v1.py')){Add-Copy $files "control-$n" (Join-Path $oldStage $n) (Join-Path 'source-controls' $n)}Add-Copy $files 'legacy-source-pins' (Join-Path $oldStage 'source-pins.json') 'source-controls/v5-root-source-pins.json'
Add-Copy $files 'integration-source-pins' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/source-pins.json') 'source-controls/v5-r6-integration-source-pins.json'
Add-Copy $files 'integration-readme' (Join-Path $repo 'factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/README.md') 'source-controls/v5-r6-integration-README.md'
# Immutable executable inputs remain external, with hashes carried into fresh plan.
$workload='D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe';$renderer='D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\swiftright_render.dll';$presentmon='D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
Add-External $files 'workloadExe' $workload;Add-External $files 'rendererDll' $renderer;Add-External $files 'presentMonExe' $presentmon
$byName=@{};foreach($f in $files){$byName[$f.name]=$f}
$plan=[ordered]@{schema='sr0-display-selfjob-v4-fresh-one-run-r8';status='source-pin-plan';execution='fresh native diagnostic only; strict display gate retained; no eligibility claim';stageRoot=(Full $StageRoot);base=(Full $Base);factoryRoot=(Full $FactoryRoot);controlRoot=$controlStage;requestedControlRoot=(Full $ControlRoot);controlReceiptRoot=(Full $FactoryRoot);requiredControlReceipts=@('drain-controls-r10.json');runRoot=(Full (Join-Path $FactoryRoot 'run'));manifestPath=(Full (Join-Path $FactoryRoot 'one-shot-manifest.json'));lockPath=(Full $LockPath);taskName='SR0-factory-display-selfjob-v7-root-r8';tag='SR0-factory-display-selfjob-v7-root-r8';schedulePath=(Full (Join-Path $StageRoot 'schedule-once-v7.ps1'));workerPath=(Full (Join-Path $StageRoot 'run-once-v7.ps1'));collectorPath=(Full (Join-Path $StageRoot 'collector-selfjob-v7-drain-pidjoin.ps1'));coordinatorPath=(Full (Join-Path $StageRoot 'coordinator-selfjob-v5.ps1'));wrapperPath=(Full (Join-Path $StageRoot 'launch-once-v7.vbs'));frozenTaskPath=(Full (Join-Path $StageRoot 'task-workload-v8.ps1'));drainTaskPath=(Full (Join-Path $StageRoot 'task-workload-drain-v1.ps1'));helperPath=(Full (Join-Path $StageRoot 'Sr0OwnedJobProcess-v15.cs'));drainHelperPath=(Full (Join-Path $StageRoot 'workload-drain-helper-v1.ps1'));identityHelperPath=(Full (Join-Path $StageRoot 'workload-identity-v6.ps1'));parserPath=(Full (Join-Path $StageRoot 'receipt-parser-v4.ps1'));launcherHelperPath=(Full (Join-Path $StageRoot 'Sr0LauncherOwnedJobProcess-v4.cs'));workloadExe=(Full $workload);rendererDll=(Full $renderer);presentMonExe=(Full $presentmon);memoryLimitFlags='0x200';aggregateJobMemoryLimitBytes=1073741824;killOnJobClose=$false;deadlineSeconds=900;pollSeconds=1;warmup=10;measure=60;runs=1;noActivate=$true;noResources=$true;streamCapBytes=8388608;csvCapBytes=67108864;sourceFiles=$files;sourcePins=[ordered]@{drainControlTestSha256=$byName['controls-drain'].sha256;drainControlRunnerSha256=$byName.drainControls.sha256;frozenTask=$byName.frozenTask.sha256;drainTask=$byName.drainTask.sha256;helper=$byName.helper.sha256;drainHelper=$byName.drainHelper.sha256;identityHelper=$byName.identityHelper.sha256;parser=$byName.parser.sha256;launcherHelper=$byName.launcherHelper.sha256;worker=$byName.worker.sha256;collector=$byName.collector.sha256;coordinator=$byName.coordinator.sha256;wrapper=$byName.wrapper.sha256;workloadExe=$byName.workloadExe.sha256;rendererDll=$byName.rendererDll.sha256;presentMonExe=$byName.presentMonExe.sha256};nativeActions=0;qualificationClaim=$false}
$planJson=$plan|ConvertTo-Json -Depth 12
[IO.File]::WriteAllText((Join-Path $StageRoot 'one-run-plan-r8.json'),$planJson+"`r`n",[Text.UTF8Encoding]::new($false))
$pin=[ordered]@{schema='sr0-display-selfjob-v4-source-pins-r8';stage=(Full $StageRoot);files=$files;sourcePlan=(Join-Path $StageRoot 'one-run-plan-r8.json');sourcePlanSha256=(Hash (Join-Path $StageRoot 'one-run-plan-r8.json'));createdAt=[DateTimeOffset]::UtcNow.ToString('o');nativeActions=0;qualificationClaim=$false}
[IO.File]::WriteAllText((Join-Path $StageRoot 'source-pins-r8.json'),($pin|ConvertTo-Json -Depth 12)+"`r`n",[Text.UTF8Encoding]::new($false))
Write-Output (($plan|ConvertTo-Json -Depth 4))
