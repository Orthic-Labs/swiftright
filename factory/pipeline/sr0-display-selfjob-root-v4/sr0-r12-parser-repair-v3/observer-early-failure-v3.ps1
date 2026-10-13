[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$CoordinatorPath,
  [Parameter(Mandatory)][string]$LauncherPath,
  [Parameter(Mandatory)][string]$TaskName,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][string]$AdmissionHelperPath,
  [ValidateRange(1,1100)][int]$ObserverDeadlineSeconds = 1100,
  [ValidateRange(1,900)][int]$TransportDeadlineSeconds = 900,
  [ValidateRange(0,120)][int]$CleanupMarginSeconds = 120,
  [int64]$MaxJsonBytes = 1048576
)
$ErrorActionPreference='Stop'
if($ObserverDeadlineSeconds -lt $TransportDeadlineSeconds){throw 'observer deadline must cover transport deadline'}
if($CleanupMarginSeconds -gt ($ObserverDeadlineSeconds-$TransportDeadlineSeconds)){throw 'cleanup margin exceeds observer slack'}
$h=Get-Item -LiteralPath $AdmissionHelperPath -Force -ErrorAction Stop
if($h.PSIsContainer -or ($h.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $h.Length -gt 2097152){throw 'admission helper rejected'}
. $h.FullName
if(-not (Get-Command Test-R12OriginalFailureQuiescence -ErrorAction SilentlyContinue)){throw 'admission predicate missing'}
$verdict=Test-R12OriginalFailureQuiescence -CollectorPath $CollectorPath -CoordinatorPath $CoordinatorPath -LauncherPath $LauncherPath -TaskName $TaskName -MaxJsonBytes $MaxJsonBytes
if(Test-Path -LiteralPath $OutputPath){throw "fresh output required: $OutputPath"}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
$out=[ordered]@{
  kind='sr0-display-r12-failure-observer-v3'
  status=[string]$verdict.status
  taskName=$TaskName
  qualificationClaim=$false
  lockReleaseEligibility=$false
  earlyReturnReason=if([string]$verdict.status -eq 'early-failure-held'){'strict-failure-terminal-quiescence'}else{'admission-rejected'}
  deadlines=[ordered]@{observerSeconds=$ObserverDeadlineSeconds;transportSeconds=$TransportDeadlineSeconds;cleanupMarginSeconds=$CleanupMarginSeconds}
  admissionHelperPath=[IO.Path]::GetFullPath($h.FullName)
  admission=$verdict
}
$tmp="$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
[IO.File]::WriteAllText($tmp,(($out|ConvertTo-Json -Depth 16)+"`r`n"),(New-Object Text.UTF8Encoding($false)))
[IO.File]::Move($tmp,$OutputPath)
$out|ConvertTo-Json -Depth 16
if([string]$verdict.status -ne 'early-failure-held'){exit 17}
exit 0
