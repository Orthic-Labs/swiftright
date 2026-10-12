[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $SourcePath -PathType Leaf)){throw "coordinator source missing: $SourcePath"}
$item=Get-Item -LiteralPath $SourcePath
if($item.Length -gt 2097152){throw 'coordinator source exceeds bounded control read'}
$source=[IO.File]::ReadAllText($item.FullName)
function Assert-V5Coordinator([string]$text,[string]$label){
  $required=@(
    "start.kind -eq 'sr0-display-collector-v5-start'",
    "final.kind -eq 'sr0-display-collector-v5'",
    "kind='sr0-display-coordinator-v5'",
    'presentMonExpectedStopValidated',
    'presentMonCsvEvidence.valid',
    'presentMonStderrEvidence.exactBenignWarning',
    "final.status -eq 'qualification-held'",
    'captureComplete',
    'qualificationHeld',
    'strict-display-parser-pending',
    'parentOriginalHandle',
    'parentKernelTerminal',
    'parent-exit-identity',
    'Read-BoundedJson',
    'Write-AtomicJson'
  )
  foreach($needle in $required){if($text.IndexOf($needle,[StringComparison]::Ordinal)-lt 0){throw "$label missing: $needle"}}
}
Assert-V5Coordinator $source 'coordinator-v5'
$mutations=@(
  @{name='wrong-final-kind';text=$source.Replace("final.kind -eq 'sr0-display-collector-v5'","final.kind -eq 'sr0-display-collector-v4'")},
  @{name='missing-stop-proof';text=$source.Replace("presentMonExpectedStopValidated) 'presentmon-stop-evidence'",'$true)')},
  @{name='missing-csv-proof';text=$source.Replace("presentMonCsvEvidence.valid) 'presentmon-csv-evidence'",'$true)')},
  @{name='missing-stderr-proof';text=$source.Replace("presentMonStderrEvidence.exactBenignWarning -or [string]$final.presentMonStderrEvidence.kind -eq 'empty'",'$true')},
  @{name='missing-display-hold';text=$source.Replace("final.status -eq 'qualification-held'","final.status -eq 'completed'")}
)
foreach($mutation in $mutations){$rejected=$false;try{Assert-V5Coordinator $mutation.text "mutation/$($mutation.name)"}catch{$rejected=$true};if(-not $rejected){throw "coordinator control mutation escaped: $($mutation.name)"}}
$out=[ordered]@{kind='sr0-display-coordinator-v5-forced-stop-controls';status='passed';sourcePath=$item.FullName;sourceBytes=$item.Length;mutationsRejected=$mutations.Count;nativeActions=0;lockActions=0;guiActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
