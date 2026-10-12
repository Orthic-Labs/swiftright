param([Parameter(Mandatory=$true)][string]$ControlRoot,[Parameter(Mandatory=$true)][string]$HelperPath,[Parameter(Mandatory=$true)][string]$WorkerInvokerPath,[Parameter(Mandatory=$true)][string]$WorkerContractPath,[Parameter(Mandatory=$true)][string]$DesktopLockPath)
Set-StrictMode -Version Latest
. $HelperPath
function Write-Json([string]$Path,[object]$Value){$Value|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $Path -Encoding UTF8}
function New-SupplementalFixture([string]$Name,[scriptblock]$Mutate){
 $root=Join-Path $ControlRoot ('supplemental-'+$Name+'-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root -Force|Out-Null
 $coord=Join-Path $root 'coordinator.json';$memory=Join-Path $root 'memory.json';$renderer=Join-Path $root 'renderer';New-Item -ItemType Directory -Path $renderer|Out-Null
 $workerRoot=Join-Path $renderer 'uia-worker';$output=Join-Path $root 'supplemental-proof.json';$lock=Join-Path $root 'desktop.lock'
 Write-Json $coord ([ordered]@{status='failed';owner='control-owner';lockAcquired=$true;lockReleased=$false;taskParentProof=[ordered]@{pid=101;kernelWait=0;kernelExitCodeSigned=1;dotNetExited=$true;dotNetExitCode=1};error='Cannot find path worker-contract.json because it does not exist'})
 Write-Json $memory ([ordered]@{status='passed';parentPid=101;killOnJobClose=$false;limitFlags=512;jobMemoryLimitBytes=1073741824;activeProcessCount=1;peakJobMemoryUsedBytes=1048576})
 Write-Json (Join-Path $renderer 'renderer-proof.json') ([ordered]@{kind='factory-production-renderer-release-proof-v1';owner='control-owner';status='failed-original-parent-released'})
 [IO.File]::WriteAllText($lock,'control-owner',[Text.UTF8Encoding]::new($false))
 & $Mutate $coord $memory $renderer $workerRoot $lock
 [pscustomobject]@{root=$root;coord=$coord;memory=$memory;renderer=$renderer;workerRoot=$workerRoot;lock=$lock;output=$output}
}
function Invoke-Supplemental([object]$Fixture){
 $invokerHash=(Get-FileHash -LiteralPath $WorkerInvokerPath).Hash.ToLowerInvariant();$contractHash=(Get-FileHash -LiteralPath $WorkerContractPath).Hash.ToLowerInvariant()
 & (Get-Command Assert-FactorySupplementalNoStartRelease) -CoordinatorPath $Fixture.coord -MemoryReceiptPath $Fixture.memory -RendererDirectory $Fixture.renderer -WorkerRoot $Fixture.workerRoot -WorkerSourceRoot (Split-Path -Parent $WorkerContractPath) -WorkerInvokerPath $WorkerInvokerPath -WorkerContractPath $WorkerContractPath -Owner 'control-owner' -ExpectedInvokerHash $invokerHash -ExpectedWorkerContractHash $contractHash -DesktopLockPath $Fixture.lock -RendererReleaseVerifier { $proof=Get-Content -Raw -LiteralPath (Join-Path $Fixture.renderer 'renderer-proof.json')|ConvertFrom-Json;if($proof.kind -cne 'factory-production-renderer-release-proof-v1' -or $proof.status -cne 'failed-original-parent-released'){throw 'renderer fixture proof'};$true } -OutputPath $Fixture.output|Out-Null
}
$positive=New-SupplementalFixture 'positive' {param($c,$m,$r,$w,$l)};Invoke-Supplemental $positive
$rejectedHarness=New-SupplementalFixture 'matched-memory-rejection' {param($c,$m,$r,$w,$l);$x=Get-Content -Raw $m|ConvertFrom-Json;$x.status='rejected';$x|Add-Member -NotePropertyName reason -NotePropertyValue 'worker-contract.json cannot find path before worker start';Write-Json $m $x};Invoke-Supplemental $rejectedHarness
foreach($case in @(
 @{name='wrong-owner';mutate={param($c,$m,$r,$w,$l);$x=Get-Content -Raw $c|ConvertFrom-Json;$x.owner='wrong-owner';Write-Json $c $x}},
 @{name='wrong-parent-exit';mutate={param($c,$m,$r,$w,$l);$x=Get-Content -Raw $c|ConvertFrom-Json;$x.taskParentProof.dotNetExitCode=0;$x.taskParentProof.kernelExitCodeSigned=0;Write-Json $c $x}},
 @{name='extra-memory-child';mutate={param($c,$m,$r,$w,$l);$x=Get-Content -Raw $m|ConvertFrom-Json;$x.activeProcessCount=2;Write-Json $m $x}},
 @{name='unrelated-memory-rejection';mutate={param($c,$m,$r,$w,$l);$x=Get-Content -Raw $m|ConvertFrom-Json;$x.status='rejected';$x|Add-Member -NotePropertyName reason -NotePropertyValue 'unrelated memory rejection';Write-Json $m $x}},
 @{name='wrong-failure';mutate={param($c,$m,$r,$w,$l);$x=Get-Content -Raw $c|ConvertFrom-Json;$x.error='unrelated failure';Write-Json $c $x}},
 @{name='worker-start-artifact';mutate={param($c,$m,$r,$w,$l);New-Item -ItemType Directory -Path $w|Out-Null;[IO.File]::WriteAllText((Join-Path $w 'worker-launch-attempt.json'),'{}',[Text.UTF8Encoding]::new($false))}},
 @{name='lock-owner-drift';mutate={param($c,$m,$r,$w,$l);[IO.File]::WriteAllText($l,'other-owner',[Text.UTF8Encoding]::new($false))}}
)){
 $fixture=New-SupplementalFixture $case.name $case.mutate;$accepted=$false;$rejected=$false
 try{Invoke-Supplemental $fixture;$accepted=$true}catch{$rejected=$true}
 if($accepted -or -not $rejected){throw ('Supplemental fault was accepted: '+$case.name)}
}
Write-Output 'SOURCE_CONTROLS_PASS supplemental-no-start-release'
