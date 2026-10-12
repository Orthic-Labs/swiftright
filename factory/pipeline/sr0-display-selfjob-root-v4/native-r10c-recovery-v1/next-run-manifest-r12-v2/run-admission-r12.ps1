[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$PlanPath,
 [Parameter(Mandatory)][string]$AdmissionManifestPath,
 [Parameter(Mandatory)][string]$RunManifestPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AdmissionManifestSha256,
 [Parameter(Mandatory)][string]$SchedulePath
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function ReadJson([string]$p){$f=Get-Item -LiteralPath $p -Force;if($f.PSIsContainer -or $f.Length -gt 2097152){throw 'bounded plan required'};[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json}
function Full([string]$p){[IO.Path]::GetFullPath($p)}
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
$plan=ReadJson $PlanPath;$admission=Full $AdmissionManifestPath;$run=Full $RunManifestPath
if([string]$plan.schema -ne 'sr0-display-selfjob-v4-fresh-one-run-r12'){throw 'r12 plan schema required'}
if([IO.Path]::GetFullPath([string]$plan.admissionManifestPath) -cne $admission -or [IO.Path]::GetFullPath([string]$plan.manifestPath) -cne $run){throw 'plan admission/run manifest paths drift'}
if((Hash $admission) -cne $AdmissionManifestSha256.ToLowerInvariant()){throw 'admission manifest hash drift'}
if(Test-Path -LiteralPath $run){throw 'run manifest must be fresh'}
$required=@{WorkerPath=$plan.workerPath;LauncherHelperPath=$plan.launcherHelperPath;CollectorPath=$plan.collectorPath;CoordinatorPath=$plan.coordinatorPath;WrapperPath=$plan.wrapperPath;AdmissionManifestPath=$admission;RunManifestPath=$run;AdmissionManifestSha256=$AdmissionManifestSha256;AdmissionHelperPath=$plan.admissionHelperPath;AdmissionHelperSha256=$plan.admissionHelperSha256;Base=$plan.base;ControlRoot=$plan.controlRoot;ControlReceiptRoot=$plan.controlReceiptRoot;RequiredControlReceipts=@($plan.requiredControlReceipts);FrozenTaskPath=$plan.frozenTaskPath;DrainTaskPath=$plan.drainTaskPath;HelperPath=$plan.helperPath;DrainHelperPath=$plan.drainHelperPath;ParserPath=$plan.parserPath;IdentityHelperPath=$plan.identityHelperPath;WorkloadExe=$plan.workloadExe;RendererDll=$plan.rendererDll;PresentMonExe=$plan.presentMonExe;FrozenTaskSha256=$plan.sourcePins.frozenTask;DrainTaskSha256=$plan.sourcePins.drainTask;HelperSha256=$plan.sourcePins.helper;DrainHelperSha256=$plan.sourcePins.drainHelper;ParserSha256=$plan.sourcePins.parser;IdentityHelperSha256=$plan.sourcePins.identityHelper;WorkerSha256=$plan.sourcePins.worker;LauncherHelperSha256=$plan.sourcePins.launcherHelper;CollectorSha256=$plan.sourcePins.collector;CoordinatorSha256=$plan.sourcePins.coordinator;WrapperSha256=$plan.sourcePins.wrapper;WorkloadExeSha256=$plan.workloadExeSha256;RendererDllSha256=$plan.rendererDllSha256;PresentMonSha256=$plan.presentMonSha256;TaskName=$plan.taskName;RunRoot=$plan.runRoot;LockPath=$plan.lockPath;Warmup=[int]$plan.warmup;Measure=[int]$plan.measure;Rows=[int]$plan.rows;KeyRate=[double]$plan.keyRate;WscriptPath="$env:SystemRoot\System32\wscript.exe"}
& $SchedulePath @required
if(-not $?) {throw 'r12 scheduler failed'}
