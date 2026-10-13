function Normalize-Hash([object]$Value){if($null -eq $Value){return ''};return ([string]$Value).ToLowerInvariant().Replace('sha256:','')}
function Same-Identity([object]$Actual,[object]$Expected){
  $actualTicks=[DateTimeOffset]::Parse([string]$Actual.startUtc).UtcDateTime.Ticks
  $expectedTicks=[DateTimeOffset]::Parse([string]$Expected.startUtc).UtcDateTime.Ticks
  return [bool]($Actual.pid -eq $Expected.pid -and
    ([string]$Actual.path).Equals([string]$Expected.path,[StringComparison]::OrdinalIgnoreCase) -and
    $actualTicks -eq $expectedTicks -and
    (Normalize-Hash $Actual.exeSha256) -eq (Normalize-Hash $Expected.exeSha256))
}
function Get-CleanupPolicyDecision([object]$Evidence,[object]$Expected){
  $holds=New-Object System.Collections.Generic.List[string]
  if($null -eq $Evidence -or $null -eq $Expected){$holds.Add('identity evidence missing');return [ordered]@{identityMatch=$false;terminate=$false;holds=@($holds)}}
  if(-not (Same-Identity $Evidence $Expected)){$holds.Add('pid/path/startUtc/exeSha256 identity mismatch')}
  $conflict=[bool]($Evidence.hasExited -and -not $Evidence.kernelTerminal)
  $wait=[int64]$Evidence.waitResult
  if($wait -ne 0 -and $wait -ne 258){$holds.Add('unknown kernel wait result')}
  $terminate=[bool]($wait -eq 258 -and $holds.Count -eq 0)
  return [ordered]@{identityMatch=($holds.Count -eq 0);terminate=$terminate;hasExitedKernelConflict=$conflict;waitResult=$wait;holds=@($holds)}
}
function Get-AbsentCleanupDecision([bool]$PinnedOriginalTerminalProof){
  $action='held-absent-without-proof';if($PinnedOriginalTerminalProof){$action='absent-original-terminal-proof'}
  return [ordered]@{accepted=[bool]$PinnedOriginalTerminalProof;action=$action}
}
function Get-CurrentAbsenceDecision([bool]$PinnedOriginalTerminalProof){
  return [ordered]@{currentAbsent=$true;originalTerminalProof=[bool]$PinnedOriginalTerminalProof;qualificationProof=[bool]$PinnedOriginalTerminalProof;action='current-not-present-at-cleanup'}
}
