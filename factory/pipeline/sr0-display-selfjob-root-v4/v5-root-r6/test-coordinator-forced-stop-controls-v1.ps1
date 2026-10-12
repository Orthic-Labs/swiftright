# Source-only executable controls for coordinator v5 final admission predicate.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Reason,[System.Collections.Generic.List[string]]$Errors){if(-not $Condition){[void]$Errors.Add($Reason)}}
function Need([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$item=Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
Need (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $item.Length -le 2097152) 'bounded coordinator source required'
$source=[IO.File]::ReadAllText($item.FullName);$tokens=$null;$parseErrors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors);Need ($parseErrors.Count -eq 0) 'coordinator source parse failed'
$fn=@($ast.FindAll({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-CoordinatorFinalAdmissionV5'},$true));Need ($fn.Count -eq 1) 'production coordinator predicate missing or duplicated';$predicate=[scriptblock]::Create($fn[0].Extent.Text);. $predicate
$positive=[pscustomobject]@{kind='sr0-display-collector-v5';taskName='T';parentOriginalHandleRetained=$true;presentMonStarted=$true;presentMonTerminal=$true;presentMonExitIdentity=$true;presentMonSessionAbsent=$true;presentMonExpectedStopValidated=$true;presentMonCsvEvidence=[pscustomobject]@{valid=$true};presentMonStderrEvidence=[pscustomobject]@{exactBenignWarning=$true;kind='benign-warning'};presentMonStreamsSealed=$true;presentMonStopMode='forced-owned';presentMonForcedStopAttempted=$true;presentMonExit=-1;presentMonExitRaw=[uint32]4294967295;presentMonStopExit=0;status='qualification-held';captureComplete=$true;qualificationHeld=$true;qualificationHoldReason='strict-display-parser-pending';workloadTerminal=$true;workloadExitIdentity=$true;activeReadableAfter=$true;activeAfter=1;activeSelfOnly=$true;workloadProof=[pscustomobject]@{ownershipTerminal=$true};lockReleased=$true}
Need ((Test-CoordinatorFinalAdmissionV5 $positive 'T').Count -eq 0) 'production coordinator positive rejected'
$mutations=@(
  @{name='stderr';field='presentMonStderrEvidence';value=[pscustomobject]@{exactBenignWarning=$false;kind='unexpected'}},
  @{name='csv';field='presentMonCsvEvidence';value=[pscustomobject]@{valid=$false}},
  @{name='stop';field='presentMonStopExit';value=1},
  @{name='parent';field='parentOriginalHandleRetained';value=$false},
  @{name='hold';field='qualificationHeld';value=$false}
)
$rejected=0
foreach($m in $mutations){$bad=[pscustomobject]@{};foreach($p in $positive.PSObject.Properties){$bad|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value};$bad.($m.field)=$m.value;Need ((Test-CoordinatorFinalAdmissionV5 $bad 'T').Count -gt 0) "coordinator mutation escaped: $($m.name)";$rejected++}
$out=[ordered]@{kind='sr0-display-coordinator-v5-forced-stop-controls';status='passed-source-controls';predicate='production-AST-extracted';sourcePath=$item.FullName;sourceBytes=$item.Length;mutationsRejected=$rejected;nativeActions=0;lockActions=0;guiActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
