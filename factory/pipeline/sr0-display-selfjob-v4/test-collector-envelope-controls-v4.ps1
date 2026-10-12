[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $SourcePath -PathType Leaf)){throw "collector source missing: $SourcePath"}
$item=Get-Item -LiteralPath $SourcePath
if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'collector source reparse point rejected'}
if($item.Length -gt 2097152){throw 'collector source exceeds bounded control read'}
$source=[IO.File]::ReadAllText($item.FullName)
function Assert-CollectorSource([string]$text,[string]$label){
  $required=@(
    'CreateCurrentProcess(1073741824)',
    'PresentMonSha256',
    'JobMemoryOnlyFlags',
    'WaitForOnlyCurrent(30000)',
    'RequireOnlyCurrent',
    'ProcessStartInfo',
    'Sr0DisplayDesktopV4',
    'OpenInputDesktop',
    'GetUserObjectInformationW',
    'CloseDesktop',
    'DesktopReadObjects',
    'desktopAvailable',
    'desktopNameRead',
    'desktopLastError',
    '$desktopName -ceq ''Default''',
    '$h=$p.Handle',
    'try{$h=$p.Handle',
    'pmHandleAcquired',
    'workloadHandleAcquired',
    'pmStopHandleAcquired',
    'pmQueryHandleAcquired',
    'parentHandleAcquired',
    'WaitForSingleObject',
    'GetExitCodeProcess',
    'parentPath',
    'parentStartTimeUtc',
    'parentOriginalHandleRetained',
    'QueryPeakJobMemory',
    'PeakJobMemoryUsedBytes',
    'limitFlagsBefore',
    'limitFlagsAfter',
    'Sr0DisplayDrainStateV4',
    'Interlocked.Add',
    'Read-BoundedText',
    'Write-AtomicFresh',
    '[IO.File]::Move',
    'MaxStdoutBytes',
    'MaxStderrBytes',
    'MaxCsvBytes',
    'pmStarted',
    'pmStartObservedAt',
    'pmSessionAbsent',
    ('query' + [char]39 + ',$pmSession,' + [char]39 + '-ets'),
    'ownershipTerminal',
    'activeSelfOnly',
    'NoActivate',
    'Release-Lock',
    'Disable-ScheduledTask',
    'StreamReader -ArgumentList @($s,[Text.Encoding]::UTF8,$true,1024,$true)'
  )
  foreach($needle in $required){if($text.IndexOf($needle,[StringComparison]::Ordinal)-lt 0){throw "$label missing required control: $needle"}}
  $desktopProbe=$text.IndexOf('$desktop=[Sr0DisplayDesktopV4]::Probe()',[StringComparison]::Ordinal);$desktopGuard=$text.IndexOf('if(-not $desktopAvailable){throw',[StringComparison]::Ordinal);$firstOwnedStart=$text.IndexOf('$pm=Start-Owned',[StringComparison]::Ordinal);if($desktopProbe -lt 0 -or $desktopGuard -le $desktopProbe -or $firstOwnedStart -le $desktopGuard){throw "$label desktop admission guard is missing or late"}
  $handleIndex=$text.IndexOf('$h=$p.Handle',[StringComparison]::Ordinal);$returnIndex=$text.IndexOf('return $p',[StringComparison]::Ordinal);$drainIndex=$text.IndexOf('Drain-Bytes',[StringComparison]::Ordinal);if($handleIndex -lt 0 -or $returnIndex -le $handleIndex -or $drainIndex -le $handleIndex){throw "$label does not acquire original process handle before return or drain"}
  if($text -notmatch '-and\s+\$pmSessionAbsent\s+-and'){throw "$label missing exact PresentMon session absence release gate"}
  if($text -notmatch '-and\s+\$activeSelfOnly\s+-and'){throw "$label missing exact active-self release gate"}
  foreach($forbidden in @('taskkill.exe','Stop-Process','Get-Process |','gwmi Win32_Process','WMI')){if($text.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase)-ge 0){throw "$label contains forbidden unrelated-process control: $forbidden"}}
}
Assert-CollectorSource $source 'collector'
$mutations=@(
  @{name='memory-limit';text=$source.Replace('CreateCurrentProcess(1073741824)','CreateCurrentProcess(536870912)')},
  @{name='session-proof';text=$source.Replace('-and $pmSessionAbsent -and','-and $pmSessionAbsentRemoved -and')},
  @{name='active-proof';text=$source.Replace('-and $activeSelfOnly -and','-and $activeSelfOnlyRemoved -and')},
  @{name='leave-open';text=$source.Replace('StreamReader -ArgumentList @($s,[Text.Encoding]::UTF8,$true,1024,$true)','StreamReader -ArgumentList @($s,[Text.Encoding]::UTF8,$true,1024,$false)')},
  @{name='handle-before-return';text=$source.Replace('$h=$p.Handle','$h=[IntPtr]::Zero')},
  @{name='handle-before-drain';text=$source.Replace('try{$h=$p.Handle','try{$h=$p.Id')},
  @{name='desktop-guard';text=$source.Replace('if(-not $desktopAvailable){throw','if($desktopAvailable){throw')}
)
foreach($mutation in $mutations){$rejected=$false;try{Assert-CollectorSource $mutation.text "mutation/$($mutation.name)"}catch{$rejected=$true};if(-not $rejected){throw "collector control mutation escaped: $($mutation.name)"}}
$out=[ordered]@{kind='sr0-display-collector-v4-controls';status='passed';sourcePath=$item.FullName;sourceBytes=$item.Length;mutationsRejected=$mutations.Count;nativeActions=0;lockActions=0;guiActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
