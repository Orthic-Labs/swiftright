# Root-owned compile request adapter; emits bounded request, then exits.
# A Windows controller must consume request under its Job Object 1 GiB cap.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('rounded-stroke-circular')][string]$Host,
  [Parameter(Mandatory=$true)][string]$Repo,
  [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
$Repo=[IO.Path]::GetFullPath($Repo)
if($Repo -cne 'D:\Claude\swiftright'){throw 'Exact workspace root required'}
$stage=Join-Path $Repo ('.factory-work\hosts\'+$Host)
$package=Join-Path $stage 'package'
$planPath=Join-Path $package 'plan.json'
if(-not (Test-Path -LiteralPath $planPath)){throw 'Staged plan missing; run prepare-bounded-stage.ps1 first'}
$plan=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json
if($plan.packageStagePath -cne $package -or $plan.runtimePackagePath -cne (Join-Path $Repo '.factory-work\runtime-stage\runtime') -or $plan.bridgePackagePath -cne (Join-Path $Repo '.factory-work\inputs\SwiftRightBridge')){throw 'Plan namespace drift'}
if($plan.boundedAdapter.memoryCapBytes -ne 1073741824 -or $plan.boundedAdapter.maxParallelJobs -ne 1 -or $plan.boundedAdapter.maxFrontendThreads -ne 1){throw 'Bounded adapter policy drift'}
$scratch=Join-Path $package 'build-circular-centered-r1\scratch'
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argv=@('build','--package-path',$package,'--scratch-path',$scratch,'--jobs','1','-Xswiftc','-j1','-Xswiftc','-num-threads','-Xswiftc','1','-c','release','-Xlinker','/MANIFEST:EMBED','-Xlinker',$dep,'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup')
$request=[ordered]@{kind='pilot-delivery-bounded-compile-request-v1';host=$Host;package=$package;scratch=$scratch;compilerPath=$plan.compilerPath;compilerHash=$plan.compilerHash;argv=$argv;memoryCapBytes=1073741824;maxParallelJobs=1;maxFrontendThreads=1;sourceOnly=$true;executionEligible=$false;hostHash=$null;caseHash=$null;nativeActions=0}
$out=Join-Path $stage 'compile-request.json'
if(-not $PreflightOnly){$request|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8}
$request|ConvertTo-Json -Depth 12
