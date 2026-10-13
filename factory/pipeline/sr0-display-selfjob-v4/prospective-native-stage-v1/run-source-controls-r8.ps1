# Root-invoked source control entry. It exercises staged production drain helper only.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$StageRoot,
  [Parameter(Mandatory)][string]$PlanPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Require([bool]$ok,[string]$m){if(-not $ok){throw $m}}
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p -Force;Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $i.Length -le 2097152) "bounded JSON rejected: $p";return [IO.File]::ReadAllText($i.FullName)|ConvertFrom-Json}
$stage=[IO.Path]::GetFullPath($StageRoot);$plan=Read-BoundedJson ([IO.Path]::GetFullPath($PlanPath));Require ([string]$plan.schema -eq 'sr0-display-selfjob-v4-fresh-one-run-r8') 'r8 plan schema mismatch';Require (-not [bool]$plan.qualificationClaim -and [int]$plan.nativeActions -eq 0) 'source controls cannot claim native qualification'
$helper=[IO.Path]::GetFullPath($plan.drainHelperPath);$control=[IO.Path]::GetFullPath((Join-Path $stage 'test-workload-drain-controls-r10.ps1'));$runner=[IO.Path]::GetFullPath((Join-Path $stage 'run-source-controls-r8.ps1'));Require (Test-Path -LiteralPath $helper -PathType Leaf) 'drain helper missing';Require (Test-Path -LiteralPath $control -PathType Leaf) 'drain controls missing';Require (Test-Path -LiteralPath $runner -PathType Leaf) 'drain controls runner missing';Require ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -ceq ([string]$plan.sourcePins.drainHelper).ToLowerInvariant()) 'drain helper pin mismatch';Require ((Get-FileHash -LiteralPath $control -Algorithm SHA256).Hash.ToLowerInvariant() -ceq ([string]$plan.sourcePins.drainControlTestSha256).ToLowerInvariant()) 'drain control test pin mismatch';Require ((Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash.ToLowerInvariant() -ceq ([string]$plan.sourcePins.drainControlRunnerSha256).ToLowerInvariant()) 'drain control runner pin mismatch';$out=[IO.Path]::GetFullPath($OutputPath);Require (-not(Test-Path -LiteralPath $out)) 'controls output must be fresh';$work=Join-Path (Split-Path -Parent $out) 'drain-controls-work-r8';if(-not(Test-Path -LiteralPath $work)){[IO.Directory]::CreateDirectory($work)|Out-Null}
& $control -DrainHelperPath $helper -DrainHelperSha256 ([string]$plan.sourcePins.drainHelper) -OutputPath $out -WorkRoot $work
Require ($? -eq $true) 'drain source controls failed';$receipt=Read-BoundedJson $out;Require ([string]$receipt.kind -eq 'sr0-display-workload-drain-controls-r10' -and [string]$receipt.status -eq 'passed-source-controls' -and [bool]$receipt.nativeQualificationClaim -eq $false) 'drain r10 control receipt status invalid';$receipt|ConvertTo-Json -Depth 8
