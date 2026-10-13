# AST controls for capture-held report predicate. No observer body or native action executes.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CaptureRoot,
  [Parameter(Mandatory)][string]$PredicatePath,
  [Parameter(Mandatory)][string]$SourcePinsPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [int64]$MaxJsonBytes=2097152
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Require([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
function Full([string]$Path){return [IO.Path]::GetFullPath($Path)}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Bounded([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (-not $i.PSIsContainer -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $i.Length -le $MaxJsonBytes) "bounded input rejected: $Path";return $i}
function ReadJson([string]$Path){return [IO.File]::ReadAllText((Bounded $Path).FullName)|ConvertFrom-Json}
function Clone([object]$Value){return (($Value|ConvertTo-Json -Depth 24 -Compress)|ConvertFrom-Json)}
Require ($MaxJsonBytes -ge 1024 -and $MaxJsonBytes -le 2097152) 'JSON bound rejected'
$root=Full $CaptureRoot;$predicate=Full $PredicatePath;$pins=ReadJson $SourcePinsPath
Require (Test-Path -LiteralPath $root -PathType Container) "capture root missing: $root"
$predicateItem=Bounded $predicate;$tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($predicate,[ref]$tokens,[ref]$parseErrors);Require ($parseErrors.Count -eq 0) 'capture predicate parse failed'
$functions=@($ast.FindAll({param($Node)$Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -ceq 'Test-CaptureHeldTerminalV13'},$true));Require ($functions.Count -eq 1) 'exact capture-held production predicate missing'
. ([scriptblock]::Create($functions[0].Extent.Text));Require ($null -ne (Get-Command Test-CaptureHeldTerminalV13 -ErrorAction SilentlyContinue)) 'capture-held predicate did not load'
$names=[ordered]@{launcher='launcher-receipt.json';collector='collector-receipt.json';coordinator='coordinator-verdict.json'};$receipts=[ordered]@{}
foreach($Name in $names.Keys){$path=Join-Path $root $names[$Name];$item=Bounded $path;$expected=switch($Name){'launcher'{[string]$pins.launcherReceiptSha256};'collector'{[string]$pins.collectorReceiptSha256};'coordinator'{[string]$pins.coordinatorReceiptSha256}};Require ($expected -match '^[0-9a-fA-F]{64}$') "receipt pin missing: $Name";Require ((Hash $item.FullName) -ceq $expected.ToLowerInvariant()) "receipt hash mismatch: $Name";$receipts[$Name]=ReadJson $item.FullName}
$actual=[bool](Test-CaptureHeldTerminalV13 $receipts.launcher $receipts.collector $receipts.coordinator);Require $actual 'r13 capture-held receipts rejected by production predicate'
Require ([string]$receipts.collector.status -ceq 'qualification-held') 'capture-held status drift';Require ([bool]$receipts.collector.captureComplete) 'capture completion missing';Require ([bool]$receipts.collector.qualificationHeld) 'qualification hold missing';Require ([string]$receipts.collector.qualificationHoldReason -ceq 'strict-display-parser-pending') 'strict parser hold reason drift';Require (-not [bool]$receipts.launcher.nativeQualificationClaim) 'launcher qualification claim present';Require (-not [bool]$receipts.collector.nativeQualificationClaim) 'collector qualification claim present';Require (-not [bool]$receipts.coordinator.nativeQualificationClaim) 'coordinator qualification claim present'
Require (-not (Test-Path -LiteralPath $ControlRoot)) "control root must be fresh: $ControlRoot";[IO.Directory]::CreateDirectory((Full $ControlRoot))|Out-Null
$mutations=@(
 @{name='collector-status-passed';apply={param($r)$r.collector.status='passed'}},
 @{name='capture-complete-false';apply={param($r)$r.collector.captureComplete=$false}},
 @{name='qualification-claim-true';apply={param($r)$r.collector.nativeQualificationClaim=$true}},
 @{name='csv-invalid';apply={param($r)$r.collector.presentMonCsvEvidence.valid=$false}},
 @{name='active-two';apply={param($r)$r.collector.activeAfter=2}},
 @{name='lock-released-false';apply={param($r)$r.collector.lockReleased=$false}},
 @{name='launcher-not-quiescent';apply={param($r)$r.launcher.aggregateDescendantsQuiesced=$false}},
 @{name='coordinator-parent-proof-false';apply={param($r)$r.coordinator.parentKernelTerminal=$false}},
 @{name='coordinator-exit-mismatch';apply={param($r)$r.coordinator.parentExitSigned=1}}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($Mutation in $mutations){$copy=[ordered]@{launcher=(Clone $receipts.launcher);collector=(Clone $receipts.collector);coordinator=(Clone $receipts.coordinator)};& $Mutation.apply $copy;$accepted=[bool](Test-CaptureHeldTerminalV13 $copy.launcher $copy.collector $copy.coordinator);Require (-not $accepted) "capture-held fault accepted: $($Mutation.name)";$dir=Join-Path (Full $ControlRoot) $Mutation.name;[IO.Directory]::CreateDirectory($dir)|Out-Null;foreach($Name in $names.Keys){$copy[$Name]|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $dir $names[$Name]) -Encoding UTF8};$rows.Add([ordered]@{name=$Mutation.name;status='rejected'})}
[ordered]@{kind='sr0-r13-capture-held-reader-controls-v1';status='passed-source-controls';predicate='Test-CaptureHeldTerminalV13';astExtracted=$true;actualStatus='capture-held-report-only';actualAccepted=$actual;qualificationClaim=$false;lockMutation=$false;faults=@($rows);receiptPins=[ordered]@{launcher=$pins.launcherReceiptSha256;collector=$pins.collectorReceiptSha256;coordinator=$pins.coordinatorReceiptSha256};checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 16
exit 0
