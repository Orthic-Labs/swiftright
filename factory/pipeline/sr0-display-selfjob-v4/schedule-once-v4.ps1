# Registers one fresh interactive Highest hidden wscript task for collector + coordinator.
# It only stages explicit pins & starts owned source; it never compiles, deletes, or changes CAS.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkerPath,
  [Parameter(Mandatory)][string]$LauncherHelperPath,
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$CoordinatorPath,
  [Parameter(Mandatory)][string]$WrapperPath,
  [Parameter(Mandatory)][string]$ManifestPath,
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$ParserPath,
  [Parameter(Mandatory)][string]$WorkloadExe,
  [Parameter(Mandatory)][string]$RendererDll,
  [Parameter(Mandatory)][string]$PresentMonExe,
  [Parameter(Mandatory)][string]$FrozenTaskSha256,
  [Parameter(Mandatory)][string]$HelperSha256,
  [Parameter(Mandatory)][string]$ParserSha256,
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
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($Tag)){$Tag=$TaskName};if($Tag -cne $TaskName){throw 'TaskName and Tag must match'};$sha='^[0-9a-fA-F]{64}$';foreach($v in @($FrozenTaskSha256,$HelperSha256,$ParserSha256,$WorkerSha256,$LauncherHelperSha256,$CollectorSha256,$CoordinatorSha256,$WrapperSha256,$WorkloadExeSha256,$RendererDllSha256,$PresentMonSha256)){if($v -notmatch $sha){throw 'all launcher pins must be SHA-256'}}
function Require-File([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "launcher input missing: $Path"};$item=Get-Item -LiteralPath $Path -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "launcher reparse input: $Path"};return $item}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-AtomicJson([string]$Path,[object]$Value){if(Test-Path -LiteralPath $Path){throw "manifest must be fresh: $Path"};$parent=Split-Path -Parent ([IO.Path]::GetFullPath($Path));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$tmp="$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp";if(Test-Path -LiteralPath $tmp){throw "manifest temp must be fresh: $tmp"};$s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$b=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 16)+"`r`n");$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()};[IO.File]::Move($tmp,$Path)}
foreach($p in @($WorkerPath,$LauncherHelperPath,$CollectorPath,$CoordinatorPath,$WrapperPath,$FrozenTaskPath,$HelperPath,$ParserPath,$WorkloadExe,$RendererDll,$PresentMonExe,$WscriptPath)){Require-File $p|Out-Null};foreach($p in @($Base,$ControlRoot,$RunRoot)){if(-not(Test-Path -LiteralPath $p -PathType Container)){throw "launcher directory missing: $p"}}
foreach($pair in @(@($FrozenTaskPath,$FrozenTaskSha256),@($HelperPath,$HelperSha256),@($ParserPath,$ParserSha256),@($WorkerPath,$WorkerSha256),@($LauncherHelperPath,$LauncherHelperSha256),@($CollectorPath,$CollectorSha256),@($CoordinatorPath,$CoordinatorSha256),@($WrapperPath,$WrapperSha256),@($WorkloadExe,$WorkloadExeSha256),@($RendererDll,$RendererDllSha256),@($PresentMonExe,$PresentMonSha256))){if((Hash $pair[0]) -cne $pair[1].ToLowerInvariant()){throw "launcher hash mismatch: $($pair[0])"}}
if(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue){throw "scheduled task already exists: $TaskName"};$run=[IO.Path]::GetFullPath($RunRoot);foreach($name in @('start-receipt.json','collector-receipt.json','coordinator-verdict.json','launcher-receipt.json')){if(Test-Path -LiteralPath (Join-Path $run $name)){throw "diagnostic receipt must be fresh: $name"}}
$pins=[ordered]@{schema='sr0-display-selfjob-v4-one-shot';taskName=$TaskName;tag=$Tag;base=[IO.Path]::GetFullPath($Base);controlRoot=[IO.Path]::GetFullPath($ControlRoot);frozenTaskPath=[IO.Path]::GetFullPath($FrozenTaskPath);helperPath=[IO.Path]::GetFullPath($HelperPath);parserPath=[IO.Path]::GetFullPath($ParserPath);launcherHelperPath=[IO.Path]::GetFullPath($LauncherHelperPath);collectorPath=[IO.Path]::GetFullPath($CollectorPath);coordinatorPath=[IO.Path]::GetFullPath($CoordinatorPath);workerPath=[IO.Path]::GetFullPath($WorkerPath);wrapperPath=[IO.Path]::GetFullPath($WrapperPath);workloadExe=[IO.Path]::GetFullPath($WorkloadExe);rendererDll=[IO.Path]::GetFullPath($RendererDll);presentMonExe=[IO.Path]::GetFullPath($PresentMonExe);frozenTaskSha256=$FrozenTaskSha256.ToLowerInvariant();helperSha256=$HelperSha256.ToLowerInvariant();parserSha256=$ParserSha256.ToLowerInvariant();launcherHelperSha256=$LauncherHelperSha256.ToLowerInvariant();workerSha256=$WorkerSha256.ToLowerInvariant();collectorSha256=$CollectorSha256.ToLowerInvariant();coordinatorSha256=$CoordinatorSha256.ToLowerInvariant();wrapperSha256=$WrapperSha256.ToLowerInvariant();workloadExeSha256=$WorkloadExeSha256.ToLowerInvariant();rendererDllSha256=$RendererDllSha256.ToLowerInvariant();presentMonSha256=$PresentMonSha256.ToLowerInvariant();runRoot=$run;resultFile=(Join-Path $run 'result-workload.txt');memoryReceiptPath=(Join-Path $run 'collector-receipt.json');startReceiptPath=(Join-Path $run 'start-receipt.json');coordinatorOutputPath=(Join-Path $run 'coordinator-verdict.json');launcherReceiptPath=(Join-Path $run 'launcher-receipt.json');lockPath=[IO.Path]::GetFullPath($LockPath);noActivate=$true;noResources=$true;runs=1;warmup=$Warmup;measure=$Measure;rows=$Rows;keyRate=$KeyRate;deadlineSeconds=900;pollSeconds=1;aggregateJobMemoryLimitBytes=1073741824;createdAt=[DateTimeOffset]::UtcNow.ToString('o')};Write-AtomicJson $ManifestPath $pins
function Quote-TaskArg([string]$Value){return '"'+$Value.Replace('"','\"')+'"'};$wscript=[IO.Path]::GetFullPath($WscriptPath);$wrapper=[IO.Path]::GetFullPath($WrapperPath);$worker=[IO.Path]::GetFullPath($WorkerPath);$manifest=[IO.Path]::GetFullPath($ManifestPath);$arguments="//B //NoLogo $(Quote-TaskArg $wrapper) $(Quote-TaskArg $worker) $(Quote-TaskArg $manifest)";$action=New-ScheduledTaskAction -Execute $wscript -Argument $arguments -WorkingDirectory ([IO.Path]::GetFullPath($Base));$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest;$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force|Out-Null;Start-ScheduledTask -TaskName $TaskName
