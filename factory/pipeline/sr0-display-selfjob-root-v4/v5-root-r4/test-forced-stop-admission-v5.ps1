# Source-only executable controls. Extracts exact production predicate via PS AST.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$item=Get-Item -LiteralPath $CollectorPath -Force -ErrorAction Stop
Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) 'collector source must be regular'
Require ($item.Length -le 2097152) 'collector source exceeds bounded control read'
$source=[IO.File]::ReadAllText($item.FullName)
$tokens=$null;$parseErrors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
Require ($parseErrors.Count -eq 0) 'collector source parse failed'
$fn=@($ast.FindAll({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ForcedOwnedStopEvidenceV5'},$true))
Require ($fn.Count -eq 1) 'production forced-stop predicate function missing or duplicated'
$predicate=[scriptblock]::Create($fn[0].Extent.Text)
. $predicate
function New-PositiveEvidence(){return [pscustomobject]@{
  stopMode='forced-owned';forcedAttempted=$true;handleAcquired=$true;terminal=$true;exitIdentity=$true;exit=-1;exitRaw=[uint64]4294967295;stopExit=0;sessionAbsent=$true
  csvValid=$true;csvHash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';csvRowPidMatch=$true;csvQpcValid=$true;stderrExactBenign=$true;stdoutSealed=$true;stderrSealed=$true
  timedOut=$false;outputExceeded=$false;drainFault=$false;workloadExit=0;workloadExitIdentity=$true;activeSelfOnly=$true
}}
$positive=New-PositiveEvidence
Require ((Test-ForcedOwnedStopEvidenceV5 $positive) -eq $true) 'production forced-stop positive evidence rejected'
$mutations=@(
  @{name='wrong-raw-exit';change={param($x)$x.exitRaw=[uint64]7}},
  @{name='stdio';change={param($x)$x.stderrExactBenign=$false}},
  @{name='missing-csv';change={param($x)$x.csvValid=$false}},
  @{name='row-pid';change={param($x)$x.csvRowPidMatch=$false}},
  @{name='stop-nonzero';change={param($x)$x.stopExit=1}},
  @{name='session-present';change={param($x)$x.sessionAbsent=$false}}
)
$rejected=0
foreach($m in $mutations){$bad=[pscustomobject]@{};foreach($p in $positive.PSObject.Properties){$bad|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value};& $m.change $bad;Require (-not (Test-ForcedOwnedStopEvidenceV5 $bad)) "production mutation escaped: $($m.name)";$rejected++}
$out=[ordered]@{kind='sr0-display-forced-stop-admission-v5-controls';status='passed-source-controls';predicate='production-AST-extracted';collectorPath=$item.FullName;collectorBytes=$item.Length;positiveAccepted=$true;mutationsRejected=$rejected;nativeActions=0;processActions=0;schedulerActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
