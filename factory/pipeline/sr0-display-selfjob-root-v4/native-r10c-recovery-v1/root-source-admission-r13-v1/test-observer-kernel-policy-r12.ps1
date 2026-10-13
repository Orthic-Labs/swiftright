[CmdletBinding()]
param([Parameter(Mandatory)][string]$ObserverPath)
$ErrorActionPreference='Stop'
function Assert([bool]$ok,[string]$message){if(-not $ok){throw $message}}
function Extract([string]$name){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $ObserverPath),[ref]$tokens,[ref]$errors);Assert ($errors.Count -eq 0) 'observer source parse failed';$fn=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true));Assert ($fn.Count -eq 1) "production function missing: $name";return $fn[0].Extent.Text}
Invoke-Expression (Extract 'Get-NativeScheduleDecision')
Invoke-Expression (Extract 'Test-FailedQuiescentReceipts')
Assert ((Get-NativeScheduleDecision $true ([uint32]0) $null) -ceq 'terminal-success') 'native terminal zero rejected'
Assert ((Get-NativeScheduleDecision $false ([uint32]0) $null) -ceq 'pending') 'cached false incorrectly terminal'
Assert ((Get-NativeScheduleDecision $true ([uint32]258) $null) -ceq 'terminal-failure') 'native terminal 258 accepted'
Assert ((Get-NativeScheduleDecision $false ([uint32]258) $null) -ceq 'pending') 'native pending 258 rejected'
Assert ((Get-NativeScheduleDecision $false ([uint32]0) 'native wait error') -ceq 'error') 'native wait error accepted'
$base=[pscustomobject]@{status='failed';parentCertificatePresent=$true;parentKernelTerminal=$true;parentOriginalHandleRetained=$true;activeSelfOnly=$true;presentMonStreamsSealed=$true;aggregateDescendantsQuiesced=$true;aggregateActiveAfter=1}
$collector=[pscustomobject]@{status='qualification-failed';parentOriginalHandleRetained=$true;activeSelfOnly=$true;presentMonStreamsSealed=$true}
$coordinator=[pscustomobject]@{status='failed';parentCertificatePresent=$true;parentKernelTerminal=$true}
$launcher=[pscustomobject]@{status='failed';aggregateDescendantsQuiesced=$true;aggregateActiveAfter=1}
Assert (Test-FailedQuiescentReceipts $launcher $collector $coordinator) 'failed quiescent receipts did not admit early held'
$collectorIncomplete=[pscustomobject]@{status='qualification-failed';parentOriginalHandleRetained=$true;activeSelfOnly=$true;presentMonStreamsSealed=$false}
Assert (-not (Test-FailedQuiescentReceipts $launcher $collectorIncomplete $coordinator)) 'incomplete streams incorrectly admitted early held'
$coordinatorIncomplete=[pscustomobject]@{status='failed';parentCertificatePresent=$true;parentKernelTerminal=$false}
Assert (-not (Test-FailedQuiescentReceipts $launcher $collector $coordinatorIncomplete)) 'incomplete kernel proof incorrectly admitted early held'
Write-Output ([ordered]@{kind='sr0-display-observer-kernel-policy-controls-r12';status='passed-source-controls';nativeQualificationClaim=$false;cases=@('cached-false','cached-true-258','cached-true-0','native-error','failed-quiescent-early-held','incomplete-proof-no-early-held') }|ConvertTo-Json -Depth 4)
