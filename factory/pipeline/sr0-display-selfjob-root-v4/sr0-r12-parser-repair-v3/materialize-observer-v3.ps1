[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ObserverSourcePath,
  [Parameter(Mandatory)][string]$AdmissionSourcePath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [int64]$MaxSourceBytes = 2097152
)
$ErrorActionPreference='Stop'
if($MaxSourceBytes -lt 1 -or $MaxSourceBytes -gt 2097152){throw 'source bound rejected'}
function Require-Source([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $i.Length -gt $MaxSourceBytes){throw "source rejected: $Path"};return $i}
$o=Require-Source $ObserverSourcePath;$a=Require-Source $AdmissionSourcePath
if(Test-Path -LiteralPath $OutputRoot){throw "fresh output required: $OutputRoot"}
$ot=[IO.File]::ReadAllText($o.FullName);$at=[IO.File]::ReadAllText($a.FullName)
foreach($needle in @('ObserverDeadlineSeconds','TransportDeadlineSeconds','CleanupMarginSeconds','qualificationClaim','lockReleaseEligibility','Test-R12OriginalFailureQuiescence')){if($ot -notmatch [regex]::Escape($needle)){throw "observer admission token missing: $needle"}}
if($at -notmatch '(?m)^function\s+Test-R12OriginalFailureQuiescence\s*\{'){throw 'admission predicate source missing'}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$outObserver=Join-Path $OutputRoot 'observer-early-failure-v3.ps1';$outAdmission=Join-Path $OutputRoot 'r12-failure-admission-v1.ps1'
[IO.File]::Copy($o.FullName,$outObserver);[IO.File]::Copy($a.FullName,$outAdmission)
$meta=[ordered]@{schema='sr0-r12-observer-materialization-v3';observerSource=[IO.Path]::GetFullPath($o.FullName);admissionSource=[IO.Path]::GetFullPath($a.FullName);observerOutput=[IO.Path]::GetFullPath($outObserver);admissionOutput=[IO.Path]::GetFullPath($outAdmission);deadlineSeconds=1100;transportDeadlineSeconds=900;cleanupMarginSeconds=120;qualificationClaim=$false;lockReleaseEligibility=$false}
$tmp=Join-Path $OutputRoot 'materialization.json.tmp';[IO.File]::WriteAllText($tmp,($meta|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)));[IO.File]::Move($tmp,(Join-Path $OutputRoot 'materialization.json'))
$meta|ConvertTo-Json -Depth 8
