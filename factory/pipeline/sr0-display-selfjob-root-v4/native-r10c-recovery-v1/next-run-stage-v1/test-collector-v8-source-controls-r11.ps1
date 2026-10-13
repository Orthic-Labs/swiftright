[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$ok,[string]$why){if(-not $ok){throw "r11 collector controls rejected: $why"}}
$item=Get-Item -LiteralPath $SourcePath -Force
Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $item.Length -le 2097152) 'collector source bound/reparse check failed'
$source=[IO.File]::ReadAllText($item.FullName)
foreach($needle in @("kind='sr0-display-collector-v8-drain-pidjoin'",'Read-PresentMonCsvEvidenceV5','workload ProcessID mismatch','Test-ForcedOwnedStopEvidenceV5')){Require ($source.IndexOf($needle,[StringComparison]::Ordinal)-ge 0) "production collector proof missing: $needle"}
$tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors);Require ($parseErrors.Count -eq 0) 'collector source parse failed'
$fn=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ForcedOwnedStopEvidenceV5'},$true));Require ($fn.Count -eq 1) 'production forced-stop predicate missing or duplicated';$predicate=[scriptblock]::Create($fn[0].Extent.Text);. $predicate
$positive=[pscustomobject]@{stopMode='forced-owned';forcedAttempted=$true;handleAcquired=$true;terminal=$true;exitIdentity=$true;exit=-1;exitRaw=[uint32]4294967295;stopExit=0;sessionAbsent=$true;csvValid=$true;csvHash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';csvRowPidMatch=$true;csvQpcValid=$true;stderrExactBenign=$true;stdoutSealed=$true;stderrSealed=$true;timedOut=$false;outputExceeded=$false;drainFault=$false;workloadExit=0;workloadExitIdentity=$true;activeSelfOnly=$true}
Require (Test-ForcedOwnedStopEvidenceV5 $positive) 'production predicate rejected positive evidence'
$mutations=@(@{name='wrong-raw-exit';field='exitRaw';value=[uint32]7},@{name='missing-stderr';field='stderrExactBenign';value=$false},@{name='missing-csv';field='csvValid';value=$false},@{name='wrong-row-pid';field='csvRowPidMatch';value=$false},@{name='stop-nonzero';field='stopExit';value=1},@{name='session-present';field='sessionAbsent';value=$false})
$rejected=0;foreach($m in $mutations){$bad=[pscustomobject]@{};foreach($p in $positive.PSObject.Properties){$bad|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value};$bad.($m.field)=$m.value;Require (-not(Test-ForcedOwnedStopEvidenceV5 $bad)) "predicate mutation escaped: $($m.name)";$rejected++}
$out=[ordered]@{kind='sr0-display-collector-v8-source-controls';status='passed-source-controls';predicate='production-AST-extracted';sourcePath=$item.FullName;sourceBytes=$item.Length;mutationsRejected=$rejected;nativeActions=0;lockActions=0;guiActions=0;nativeQualificationClaim=$false;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};if(Test-Path -LiteralPath $OutputPath){throw 'collector controls output must be fresh'};$tmp="$OutputPath.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($out|ConvertTo-Json -Depth 8)+"`r`n"),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$OutputPath);$out|ConvertTo-Json -Depth 8
