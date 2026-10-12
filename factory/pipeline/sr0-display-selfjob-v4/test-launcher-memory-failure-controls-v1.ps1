# Source-only controls for outer 1GiB over-cap diagnostics. No process, task, job, or native actions.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$HelperSourcePath,
  [Parameter(Mandatory)][string]$WrapperSourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $item.Length -le $Limit) 'bounded source required';return [IO.File]::ReadAllText($item.FullName)}
$helper=Read-Bounded $HelperSourcePath;$wrapper=Read-Bounded $WrapperSourcePath
Require ($helper.Contains('launcher cap configuration proof failed')) 'outer Query must preserve over-cap snapshot'
Require (-not $helper.Contains('launcher cap proof failed')) 'outer Query still discards over-cap snapshot'
Require ($helper.Contains('PeakJobMemoryUsedBytes > budgetBytes')) 'initial outer admission must reject over-cap peak'
Require ($wrapper.Contains('$memoryCapExceeded=$false')) 'outer cap state not initialized'
Require ($wrapper.Contains('$memoryCapExceeded=($outerFinal.PeakJobMemoryUsedBytes -gt $outerFinal.JobMemoryLimitBytes)')) 'outer final cap observation missing'
Require ($wrapper.Contains("Require (-not `$memoryCapExceeded) 'launcher aggregate memory cap exceeded'")) 'outer qualification cap rejection missing'
Require ($wrapper.Contains('aggregateMemoryCapExceeded=$memoryCapExceeded')) 'outer cap receipt field missing'
Require ($wrapper.Contains('-not $memoryCapExceeded){''passed''}')) 'outer pass gate does not reject cap violation'
$mutated=$wrapper.Replace("Require (-not `$memoryCapExceeded) 'launcher aggregate memory cap exceeded'",'$null')
Require ($mutated -cne $wrapper) 'outer cap mutation was no-op'
Require ($mutated -notmatch "Require \(-not \$memoryCapExceeded\) 'launcher aggregate memory cap exceeded'") 'outer cap fault still accepted'
$mutatedStatus=$wrapper.Replace('-not $memoryCapExceeded){''passed''}','$null){''passed''}')
Require ($mutatedStatus -cne $wrapper) 'outer status mutation was no-op'
Require ($mutatedStatus -notmatch '-not \$memoryCapExceeded\)\{''passed''\}') 'outer status fault still accepted'
$out=[ordered]@{kind='sr0-display-launcher-memory-failure-controls-v1';status='passed-source-controls';helperSourcePath=[IO.Path]::GetFullPath($HelperSourcePath);wrapperSourcePath=[IO.Path]::GetFullPath($WrapperSourcePath);nativeActions=0;processActions=0;overCapHeld=true;mutationsRejected=2;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
