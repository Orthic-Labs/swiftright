# v5 scheduler: worker receipt accepts capture-complete qualification-held; strict display parser is separate.
# It only stages explicit pins & starts owned source; it never compiles, deletes, or changes CAS.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkerPath,
  [Parameter(Mandatory)][string]$LauncherHelperPath,
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$CoordinatorPath,
  [Parameter(Mandatory)][string]$WrapperPath,
  [Parameter(Mandatory)][string]$AdmissionManifestPath,
  [Parameter(Mandatory)][string]$RunManifestPath,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AdmissionManifestSha256,
  [Parameter(Mandatory)][string]$AdmissionHelperPath,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AdmissionHelperSha256,
  [Parameter(Mandatory)][string]$SourceRowsPath,
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$ControlReceiptRoot,
  [Parameter(Mandatory)][string[]]$RequiredControlReceipts,
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$DrainTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$DrainHelperPath,
  [Parameter(Mandatory)][string]$ParserPath,
  [Parameter(Mandatory)][string]$IdentityHelperPath,
  [Parameter(Mandatory)][string]$WorkloadExe,
  [Parameter(Mandatory)][string]$RendererDll,
  [Parameter(Mandatory)][string]$PresentMonExe,
  [Parameter(Mandatory)][string]$FrozenTaskSha256,
  [Parameter(Mandatory)][string]$DrainTaskSha256,
  [Parameter(Mandatory)][string]$HelperSha256,
  [Parameter(Mandatory)][string]$DrainHelperSha256,
  [Parameter(Mandatory)][string]$ParserSha256,
  [Parameter(Mandatory)][string]$IdentityHelperSha256,
  [Parameter(Mandatory)][string]$WorkerSha256,
  [Parameter(Mandatory)][string]$LauncherHelperSha256,
  [Parameter(Mandatory)][string]$CollectorSha256,
  [Parameter(Mandatory)][string]$CoordinatorSha256,
  [Parameter(Mandatory)][string]$WrapperSha256,
  [Parameter(Mandatory)][string]$WorkloadExeSha256,
  [Parameter(Mandatory)][string]$RendererDllSha256,
  [Parameter(Mandatory)][string]$PresentMonSha256,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$TaskName,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$LockPath,
  [string]$WscriptPath="$env:SystemRoot\System32\wscript.exe",
  [string]$Tag='',
  [ValidateRange(1,120)][int]$Warmup=10,
  [ValidateRange(1,300)][int]$Measure=60,
  [int]$Rows=200,
  [double]$KeyRate=10
)
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($Tag)){$Tag=$TaskName};if($Tag -cne $TaskName){throw 'TaskName and Tag must match'};$sha='^[0-9a-fA-F]{64}$';foreach($v in @($FrozenTaskSha256,$DrainTaskSha256,$HelperSha256,$DrainHelperSha256,$ParserSha256,$IdentityHelperSha256,$WorkerSha256,$LauncherHelperSha256,$CollectorSha256,$CoordinatorSha256,$WrapperSha256,$WorkloadExeSha256,$RendererDllSha256,$PresentMonSha256)){if($v -notmatch $sha){throw 'all launcher pins must be SHA-256'}}
function Require-File([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "launcher input missing: $Path"};$item=Get-Item -LiteralPath $Path -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "launcher reparse input: $Path"};return $item}
function Full([string]$Path){return [IO.Path]::GetFullPath($Path)}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-AtomicJson([string]$Path,[object]$Value){if(Test-Path -LiteralPath $Path){throw "manifest must be fresh: $Path"};$parent=Split-Path -Parent ([IO.Path]::GetFullPath($Path));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$tmp="$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp";if(Test-Path -LiteralPath $tmp){throw "manifest temp must be fresh: $tmp"};$s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$b=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 16)+"`r`n");$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()};[IO.File]::Move($tmp,$Path)}
foreach($p in @($WorkerPath,$LauncherHelperPath,$CollectorPath,$CoordinatorPath,$WrapperPath,$FrozenTaskPath,$DrainTaskPath,$HelperPath,$DrainHelperPath,$ParserPath,$IdentityHelperPath,$WorkloadExe,$RendererDll,$PresentMonExe,$WscriptPath)){Require-File $p|Out-Null};$admission=[IO.Path]::GetFullPath($AdmissionManifestPath);$manifest=[IO.Path]::GetFullPath($RunManifestPath);if($admission -ceq $manifest){throw 'admission/run manifest paths must differ'};if($Warmup -ne 10 -or $Measure -ne 60 -or $Rows -ne 200 -or $KeyRate -ne 10){throw 'workload configuration drift'};$admissionHelper=[IO.Path]::GetFullPath($AdmissionHelperPath);if(-not(Test-Path -LiteralPath $admissionHelper -PathType Leaf)){throw 'admission helper missing'};if((Hash $admissionHelper) -cne $AdmissionHelperSha256.ToLowerInvariant()){throw 'admission helper hash mismatch'};. $admissionHelper;foreach($p in @($Base,$ControlRoot,$ControlReceiptRoot,$RunRoot)){if(-not(Test-Path -LiteralPath $p -PathType Container)){throw "launcher directory missing: $p"}};$runItem=Get-Item -LiteralPath (Full $RunRoot) -Force;if(($runItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'launcher run root reparse input'};if(@(Get-ChildItem -LiteralPath (Full $RunRoot) -Force).Count -ne 0){throw 'launcher run root must be fresh and empty'};if($RequiredControlReceipts.Count -lt 1){throw 'production control receipts required'};foreach($name in $RequiredControlReceipts){if($name -match '[\/:]'){throw 'control receipt name must be leaf'};$rp=Join-Path (Full $ControlReceiptRoot) $name;if(-not(Test-Path -LiteralPath $rp -PathType Leaf)){throw "production control receipt missing: $rp"};$ri=Get-Item -LiteralPath $rp -Force;if(($ri.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $ri.Length -gt 2097152){throw "production control receipt bounds/reparse failure: $rp"};$rc=[IO.File]::ReadAllText($ri.FullName)|ConvertFrom-Json;if([string]$rc.kind -ne 'sr0-display-workload-drain-controls-r10' -or [string]$rc.status -ne 'passed-source-controls' -or [bool]$rc.nativeQualificationClaim){throw "production r10 control receipt not passed/held: $rp"}}
foreach($pair in @(@($FrozenTaskPath,$FrozenTaskSha256),@($DrainTaskPath,$DrainTaskSha256),@($HelperPath,$HelperSha256),@($DrainHelperPath,$DrainHelperSha256),@($ParserPath,$ParserSha256),@($IdentityHelperPath,$IdentityHelperSha256),@($WorkerPath,$WorkerSha256),@($LauncherHelperPath,$LauncherHelperSha256),@($CollectorPath,$CollectorSha256),@($CoordinatorPath,$CoordinatorSha256),@($WrapperPath,$WrapperSha256),@($WorkloadExe,$WorkloadExeSha256),@($RendererDll,$RendererDllSha256),@($PresentMonExe,$PresentMonSha256))){if((Hash $pair[0]) -cne $pair[1].ToLowerInvariant()){throw "launcher hash mismatch: $($pair[0])"}}
if(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue){throw "scheduled task already exists: $TaskName"};$run=[IO.Path]::GetFullPath($RunRoot);if(-not(Test-Path -LiteralPath $admission -PathType Leaf)){throw "admission manifest missing: $admission"};if((Hash $admission) -cne $AdmissionManifestSha256.ToLowerInvariant()){throw 'admission manifest hash mismatch'};$admissionDoc=[IO.File]::ReadAllText($admission)|ConvertFrom-Json;foreach($name in @('start-receipt.json','collector-receipt.json','coordinator-verdict.json','launcher-receipt.json')){if(Test-Path -LiteralPath (Join-Path $run $name)){throw "diagnostic receipt must be fresh: $name"}}
$pins=[ordered]@{schema='sr0-display-selfjob-v5-one-shot-admission-r12';taskName=$TaskName;tag=$Tag;base=[IO.Path]::GetFullPath($Base);controlRoot=[IO.Path]::GetFullPath($ControlRoot);controlReceiptRoot=[IO.Path]::GetFullPath($ControlReceiptRoot);requiredControlReceipts=@($RequiredControlReceipts);frozenTaskPath=[IO.Path]::GetFullPath($FrozenTaskPath);drainTaskPath=[IO.Path]::GetFullPath($DrainTaskPath);helperPath=[IO.Path]::GetFullPath($HelperPath);drainHelperPath=[IO.Path]::GetFullPath($DrainHelperPath);parserPath=[IO.Path]::GetFullPath($ParserPath);identityHelperPath=[IO.Path]::GetFullPath($IdentityHelperPath);launcherHelperPath=[IO.Path]::GetFullPath($LauncherHelperPath);collectorPath=[IO.Path]::GetFullPath($CollectorPath);coordinatorPath=[IO.Path]::GetFullPath($CoordinatorPath);workerPath=[IO.Path]::GetFullPath($WorkerPath);wrapperPath=[IO.Path]::GetFullPath($WrapperPath);workloadExe=[IO.Path]::GetFullPath($WorkloadExe);rendererDll=[IO.Path]::GetFullPath($RendererDll);presentMonExe=[IO.Path]::GetFullPath($PresentMonExe);sourceRowsPath=[IO.Path]::GetFullPath($SourceRowsPath);admissionHelperPath=$admissionHelper;admissionHelperSha256=$AdmissionHelperSha256.ToLowerInvariant();frozenTaskSha256=$FrozenTaskSha256.ToLowerInvariant();drainTaskSha256=$DrainTaskSha256.ToLowerInvariant();helperSha256=$HelperSha256.ToLowerInvariant();drainHelperSha256=$DrainHelperSha256.ToLowerInvariant();parserSha256=$ParserSha256.ToLowerInvariant();identityHelperSha256=$IdentityHelperSha256.ToLowerInvariant();launcherHelperSha256=$LauncherHelperSha256.ToLowerInvariant();workerSha256=$WorkerSha256.ToLowerInvariant();collectorSha256=$CollectorSha256.ToLowerInvariant();coordinatorSha256=$CoordinatorSha256.ToLowerInvariant();wrapperSha256=$WrapperSha256.ToLowerInvariant();workloadExeSha256=$WorkloadExeSha256.ToLowerInvariant();rendererDllSha256=$RendererDllSha256.ToLowerInvariant();presentMonSha256=$PresentMonSha256.ToLowerInvariant();runRoot=$run;resultFile=(Join-Path $run 'result-workload.txt');memoryReceiptPath=(Join-Path $run 'collector-receipt.json');startReceiptPath=(Join-Path $run 'start-receipt.json');coordinatorOutputPath=(Join-Path $run 'coordinator-verdict.json');launcherReceiptPath=(Join-Path $run 'launcher-receipt.json');lockPath=[IO.Path]::GetFullPath($LockPath);noActivate=$true;noResources=$true;runs=1;warmup=$Warmup;measure=$Measure;rows=$Rows;keyRate=$KeyRate;deadlineSeconds=900;pollSeconds=1;aggregateJobMemoryLimitBytes=1073741824;aggregateLimitFlags=512;killOnJobClose=$false;createdAt=[DateTimeOffset]::UtcNow.ToString('o')};[void](Assert-Sr0R12Admission -Admission $admissionDoc -Requested ([pscustomobject]$pins));$runPins=[ordered]@{};foreach($k in $pins.Keys){$runPins[$k]=$pins[$k]};$runPins.schema='sr0-display-selfjob-v5-one-shot';$runPins.manifestGeneration='r12';$runPins.admissionManifestPath=$admission;$runPins.admissionManifestSha256=$AdmissionManifestSha256.ToLowerInvariant();Write-AtomicJson $manifest $runPins
function Quote-TaskArg([string]$Value){return '"'+$Value.Replace('"','\"')+'"'};$wscript=[IO.Path]::GetFullPath($WscriptPath);$wrapper=[IO.Path]::GetFullPath($WrapperPath);$worker=[IO.Path]::GetFullPath($WorkerPath);$arguments="//B //NoLogo $(Quote-TaskArg $wrapper) $(Quote-TaskArg $worker) $(Quote-TaskArg $manifest)";$action=New-ScheduledTaskAction -Execute $wscript -Argument $arguments -WorkingDirectory ([IO.Path]::GetFullPath($Base));$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest;$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force|Out-Null;Start-ScheduledTask -TaskName $TaskName
