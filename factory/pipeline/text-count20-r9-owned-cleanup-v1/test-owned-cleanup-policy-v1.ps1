$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'owned-cleanup-policy.ps1')
function Expect([bool]$ok,[string]$why){if(-not $ok){throw "cleanup policy control failed: $why"}}
$e=[pscustomobject]@{pid=26108;path='D:\FactoryProbe.exe';startUtc='2026-10-12T03:58:13.9333787Z';exeSha256=('a'*64);hasExited=$true;kernelTerminal=$false;waitResult=258}
$x=[pscustomobject]@{pid=26108;path='D:\FactoryProbe.exe';startUtc='2026-10-12T03:58:13.9333787Z';exeSha256=('a'*64)}
$d=Get-CleanupPolicyDecision $e $x;Expect $d.terminate 'HasExited=true must not suppress termination when kernel is nonterminal';Expect $d.hasExitedKernelConflict 'managed/kernel conflict must be visible';Expect ($d.holds.Count -eq 0) 'identity remains valid despite managed-state conflict'
$e.kernelTerminal=$true;$e.waitResult=0;$d=Get-CleanupPolicyDecision $e $x;Expect (-not $d.terminate) 'terminal process must not be terminated'
$e.waitResult=17;$d=Get-CleanupPolicyDecision $e $x;Expect (-not $d.terminate) 'unknown kernel wait must never terminate'
$bad=[pscustomobject]@{pid=26108;path='D:\Foreign.exe';startUtc=$x.startUtc;exeSha256=$x.exeSha256;hasExited=$false;kernelTerminal=$false;waitResult=258};$d=Get-CleanupPolicyDecision $bad $x;Expect (-not $d.terminate) 'wrong path must never terminate'
Expect (Get-AbsentCleanupDecision $true).accepted 'pinned original terminal proof must accept absent identity'
Expect (-not (Get-AbsentCleanupDecision $false).accepted) 'absence without original proof must hold'
Expect ((Get-CurrentAbsenceDecision $false).currentAbsent -and -not (Get-CurrentAbsenceDecision $false).qualificationProof) 'current absence must remain separate from original proof'
Write-Output 'passed-cleanup-policy-controls'
