# Bounded source preflight. No native actions.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$FrozenTaskPath,[Parameter(Mandatory)][string]$HelperPath,[Parameter(Mandatory)][string]$ParserPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Read-Source([string]$Path,[long]$Limit){$item=Get-Item -LiteralPath $Path -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded source rejection: $Path"};return [IO.File]::ReadAllText($Path)}
$source=Read-Source $SourcePath 2MB;$frozen=Read-Source $FrozenTaskPath 2MB;$helper=Read-Source $HelperPath 2MB;$parser=Read-Source $ParserPath 2MB
$required=@('[Parameter(Mandatory)][switch]$NoActivate','-NoActivate:$NoActivate','CreateCurrentProcess(1073741824)','WaitForOnlyCurrent(30000)','RequireOnlyCurrent','QueryPeakJobMemory','PeakJobMemoryUsedBytes','Parse-WorkloadReceipt','FrozenTaskSha256','HelperSha256','ParserSha256','StartReceiptPath','TaskName','parentOriginalHandleRetained','Disable-ScheduledTask','schedulerDisabled')
$missing=@($required|Where-Object{$source.IndexOf($_,[StringComparison]::Ordinal)-lt 0});if($missing.Count){throw "envelope contract missing: $($missing -join ',')"}
if($source -match '\[switch\]\$NoActivate(?!\s*\r?\n)' -and $source -notmatch '\[Parameter\(Mandatory\)\]\[switch\]\$NoActivate'){throw 'NoActivate must be mandatory'}
if($source -match '(?i)SetForegroundWindow|SetActiveWindow|BringWindowToTop|SendInput|Acquire\('){throw 'foreground/input path present'}
$forbidden='Register-'+'ScheduledTask';$forbidden2='Start-'+'ScheduledTask';if($source.IndexOf($forbidden,[StringComparison]::Ordinal)-ge 0 -or $source.IndexOf($forbidden2,[StringComparison]::Ordinal)-ge 0){throw 'scheduled-task API in envelope'}
if($frozen -notmatch '\[System\.Diagnostics\.Process\]::Start' -or $frozen -notmatch 'WorkloadWin\.exe' -or $frozen.IndexOf($forbidden,[StringComparison]::Ordinal)-ge 0 -or $frozen.IndexOf($forbidden2,[StringComparison]::Ordinal)-ge 0){throw 'frozen task direct-child contract failed'}
if($helper.IndexOf('JobMemoryOnlyFlags = 0x200',[StringComparison]::Ordinal)-lt 0){throw 'v15 memory-only helper missing'}
if($parser.IndexOf('function Parse-WorkloadReceipt',[StringComparison]::Ordinal)-lt 0 -or $parser.IndexOf('ownershipTerminal',[StringComparison]::Ordinal)-lt 0 -or $parser.IndexOf('qualificationPass',[StringComparison]::Ordinal)-lt 0){throw 'pure parser contract missing'}
$obj=[ordered]@{schema='sr0-display-selfjob-envelope-controls-v4';status='source-admitted';nativeActions=0;lockActions=0;noActivateMandatory=$true;foregroundPath=$false;directFrozenTask=$true;pureParser=$true};$obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$obj|ConvertTo-Json -Depth 8
