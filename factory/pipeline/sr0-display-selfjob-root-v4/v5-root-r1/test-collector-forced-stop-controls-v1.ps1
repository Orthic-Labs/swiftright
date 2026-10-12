[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $SourcePath -PathType Leaf)){throw "collector source missing: $SourcePath"}
$item=Get-Item -LiteralPath $SourcePath
if($item.Length -gt 2097152){throw 'collector source exceeds bounded control read'}
$source=[IO.File]::ReadAllText($item.FullName)
function Assert-V5([string]$text,[string]$label){
  $required=@(
    "kind='sr0-display-collector-v5'",
    "kind='sr0-display-collector-v5-start'",
    'presentMonStopMode',
    'presentMonForcedStopAttempted',
    'presentMonExpectedStopValidated',
    'Read-PresentMonCsvEvidenceV5',
    'Read-PresentMonStderrEvidenceV5',
    'Split-CsvFieldsV5',
    'QPCTime invalid',
    'ProcessID invalid',
    'TimeInSeconds invalid',
    'row count exceeds bound',
    'Get-FileHash -LiteralPath $path -Algorithm SHA256',
    "warning: ignoring --write_display_metadata due to --v1_metrics.",
    "pmStopMode -eq 'forced-owned'",
    '$pmForcedStopAttempted',
    "pmStopMode -eq 'forced-owned' -and `$pmForcedStopAttempted -and",
    '$pmHandleAcquired -and $pmTerminal',
    '$pmExit -eq -1',
    '[uint64]$pmExitRaw -eq [uint64]4294967295',
    '$pmStopExit -eq 0',
    '$pmSessionAbsent',
    '$pmExitIdentity',
    '$pmCsvEvidence.valid',
    '$pmStderrEvidence.exactBenignWarning',
    '$streamsSealed',
    '$streamsSealed -and -not $timedOut',
    '$workloadExit -eq 0',
    '$activeSelfOnly',
    "pmStopMode -eq 'natural'",
    '$pmNaturalExit',
    "qualificationHoldReason=if($qualificationHeld){'strict-display-parser-pending'}",
    "if($status -in @('completed','qualification-held')){exit 0}else{exit 1}"
  )
  foreach($needle in $required){if($text.IndexOf($needle,[StringComparison]::Ordinal)-lt 0){throw "$label missing: $needle"}}
  if(([regex]::Matches($text,'\[bool\]\$pmCsvEvidence\.valid')).Count -lt 2){throw "$label CSV validity is not required by both PM stop paths"}
  if(([regex]::Matches($text,'\$pmExitIdentity')).Count -lt 3){throw "$label PM exit identity is not bound into evidence"}
  if($text.IndexOf('Read-PresentMonCsvEvidenceV5 $pmCsv $MaxCsvBytes',[StringComparison]::Ordinal) -lt 0){throw "$label CSV read is not capped"}
  if($text.IndexOf('Read-PresentMonStderrEvidenceV5 $pmStderrPath $MaxStderrBytes',[StringComparison]::Ordinal) -lt 0){throw "$label stderr read is not capped"}
}
Assert-V5 $source 'collector-v5'
$mutations=@(
  @{name='wrong-signed-exit';text=$source.Replace('$pmExit -eq -1','$pmExit -eq -7')},
  @{name='wrong-raw-exit';text=$source.Replace('[uint64]4294967295','[uint64]7')},
  @{name='wrong-stderr';text=$source.Replace('warning: ignoring --write_display_metadata due to --v1_metrics.','warning: unexpected PresentMon stderr.')},
  @{name='missing-csv-proof';text=$source.Replace('[bool]$pmCsvEvidence.valid','$true')},
  @{name='missing-csv-hash';text=$source.Replace('$csvHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()','$csvHash=""')},
  @{name='missing-header-gate';text=$source.Replace('PresentMon CSV header column count mismatch','PresentMon CSV header accepted')},
  @{name='missing-clock-gate';text=$source.Replace('PresentMon CSV QPCTime invalid','PresentMon CSV QPCTime accepted')},
  @{name='missing-row-count-gate';text=$source.Replace('PresentMon CSV row count exceeds bound','PresentMon CSV row count accepted')},
  @{name='missing-forced-attempt';text=$source.Replace('$pmForcedStopAttempted -and','$true -and')},
  @{name='missing-stop-proof';text=$source.Replace('$pmStopExit -eq 0','$true')},
  @{name='missing-session-proof';text=$source.Replace('$pmSessionAbsent -and','$true -and')},
  @{name='missing-handle-proof';text=$source.Replace('$pmHandleAcquired -and $pmTerminal','$true -and $pmTerminal')},
  @{name='missing-stream-proof';text=$source.Replace('$streamsSealed -and','$true -and')},
  @{name='missing-hold';text=$source.Replace("qualificationHoldReason=if($qualificationHeld){'strict-display-parser-pending'}",'qualificationHoldReason=$null')}
)
foreach($mutation in $mutations){$rejected=$false;try{Assert-V5 $mutation.text "mutation/$($mutation.name)"}catch{$rejected=$true};if(-not $rejected){throw "forced-stop control mutation escaped: $($mutation.name)"}}
$out=[ordered]@{kind='sr0-display-collector-v5-forced-stop-controls';status='passed';sourcePath=$item.FullName;sourceBytes=$item.Length;mutationsRejected=$mutations.Count;nativeActions=0;lockActions=0;guiActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
