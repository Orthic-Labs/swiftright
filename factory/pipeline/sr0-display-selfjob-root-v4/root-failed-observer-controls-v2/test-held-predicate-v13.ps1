[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FailureRoot,
  [Parameter(Mandatory)][string]$ObserverPath,
  [Parameter(Mandatory)][string]$SourcePinsPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [int64]$MaxJsonBytes = 2097152
)
$ErrorActionPreference='Stop'
if($MaxJsonBytes -lt 1 -or $MaxJsonBytes -gt 2097152){throw 'bounded read limit rejected'}
function Require-BoundedFile([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $i.Length -gt $MaxJsonBytes){throw "bounded/reparse input rejected: $Path"};return $i}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-BoundedJson([string]$Path){$i=Require-BoundedFile $Path;return ([IO.File]::ReadAllText($i.FullName)|ConvertFrom-Json)}
$pins=Read-BoundedJson $SourcePinsPath
$observer=Require-BoundedFile $ObserverPath
if((Hash $observer.FullName) -cne ([string]$pins.observerSha256).ToLowerInvariant()){throw 'observer source hash mismatch'}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($observer.FullName,[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0){throw 'observer source parse failed'}
$fn=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Test-FailedQuiescentReceipts'},$true))
if($fn.Count -ne 1){throw 'exact production held predicate missing'}
# Load only production function AST; observer body, scheduler, native actions, & receipt writer never execute.
. ([scriptblock]::Create($fn[0].Extent.Text))
if(-not (Get-Command Test-FailedQuiescentReceipts -ErrorAction SilentlyContinue)){throw 'production held predicate was not loaded'}
if(Test-Path -LiteralPath $ControlRoot){throw "fresh control root required: $ControlRoot"}
[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null
$names=[ordered]@{collector='collector.json';coordinator='coordinator.json';launcher='launcher.json'};$receipts=[ordered]@{}
foreach($name in $names.Keys){$path=Join-Path $FailureRoot $names[$name];$item=Require-BoundedFile $path;$expected=[string]$pins.receiptSha256.$name;if((Hash $item.FullName) -cne $expected.ToLowerInvariant()){throw "archived $name hash mismatch"};$receipts[$name]=Read-BoundedJson $item.FullName}
$actual=[bool](Test-FailedQuiescentReceipts $receipts.launcher $receipts.collector $receipts.coordinator)
if(-not $actual){throw 'production held predicate rejected archived fixture'}
$mutations=@(
  @{name='missing-original-retained-parent';apply={param($r)$r.collector.parentOriginalHandleRetained=$false}},
  @{name='presentmon-terminal-false';apply={param($r)$r.collector.presentMonTerminal=$false}},
  @{name='active-two';apply={param($r)$r.launcher.aggregateActiveAfter=2}},
  @{name='launcher-exit-identity-false';apply={param($r)$r.launcher.collectorExitIdentity=$false}},
  @{name='wrong-status';apply={param($r)$r.collector.status='passed'}},
  @{name='parent-kernel-proof-false';apply={param($r)$r.coordinator.parentKernelTerminal=$false}},
  @{name='parent-exit-mismatch';apply={param($r)$r.coordinator.parentExitSigned=0}}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($mutation in $mutations){$copy=[ordered]@{collector=(Read-BoundedJson (Join-Path $FailureRoot $names.collector));coordinator=(Read-BoundedJson (Join-Path $FailureRoot $names.coordinator));launcher=(Read-BoundedJson (Join-Path $FailureRoot $names.launcher))};& $mutation.apply $copy;$dir=Join-Path $ControlRoot $mutation.name;[IO.Directory]::CreateDirectory($dir)|Out-Null;foreach($name in $names.Keys){$copy[$name]|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $dir $names[$name]) -Encoding UTF8};$accepted=[bool](Test-FailedQuiescentReceipts $copy.launcher $copy.collector $copy.coordinator);if($accepted){throw "production held predicate fault accepted: $($mutation.name)"};$rows.Add([ordered]@{name=$mutation.name;status='rejected'})}
[ordered]@{kind='sr0-display-failed-observer-held-predicate-controls-v13';status='passed-source-controls';productionFunction='Test-FailedQuiescentReceipts';astExtracted=$true;actualAccepted=$actual;faults=@($rows);qualificationClaim=$false;lockReleaseEligibility=$false}|ConvertTo-Json -Depth 12
