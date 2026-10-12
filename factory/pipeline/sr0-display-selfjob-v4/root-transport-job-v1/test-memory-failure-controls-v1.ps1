# Source-only controls for over-cap diagnostics. No process, job, scheduler, or native actions.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$HelperSourcePath,
  [Parameter(Mandatory)][string]$WrapperSourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $item.Length -le $Limit) 'bounded source required';return [IO.File]::ReadAllText($item.FullName)}
$helper=Read-Bounded $HelperSourcePath
$wrapper=Read-Bounded $WrapperSourcePath
Require ($helper.Contains('PeakBytes > s.LimitBytes')) 'RequireMemoryOnly must reject over-cap peak'
Require ($helper.Contains('root transport cap configuration proof failed')) 'Query must preserve over-cap snapshot after configuration proof'
Require (-not $helper.Contains('root transport cap proof failed')) 'Query still discards over-cap snapshot'
Require ($wrapper.Contains('$memoryCapExceeded=$false')) 'wrapper cap state not initialized'
Require ($wrapper.Contains('$memoryCapExceeded=($final.PeakBytes -gt $final.LimitBytes)')) 'wrapper final cap observation missing'
Require ($wrapper.Contains('Require (-not $memoryCapExceeded) ''root transport memory cap exceeded''')) 'wrapper qualification cap rejection missing'
Require ($wrapper.Contains('memoryCapExceeded=$memoryCapExceeded')) 'wrapper failure receipt cap field missing'
Require ($wrapper.Contains('-not $memoryCapExceeded -and $null -ne $final')) 'wrapper pass gate does not reject cap violation'
$mutated=$wrapper.Replace('Require (-not $memoryCapExceeded) ''root transport memory cap exceeded''','$null')
Require ($mutated -cne $wrapper) 'cap mutation was no-op'
Require ($mutated -notmatch "Require \(-not \$memoryCapExceeded\) 'root transport memory cap exceeded'") 'cap fault still accepted'
$mutatedStatus=$wrapper.Replace('-not $memoryCapExceeded -and $null -ne $final','$null -ne $final')
Require ($mutatedStatus -cne $wrapper) 'status cap mutation was no-op'
Require ($mutatedStatus -notmatch '-not \$memoryCapExceeded -and \$null -ne \$final') 'status fault still accepted'
$out=[ordered]@{kind='sr0-root-transport-memory-failure-controls-v1';status='passed-source-controls';helperSourcePath=[IO.Path]::GetFullPath($HelperSourcePath);wrapperSourcePath=[IO.Path]::GetFullPath($WrapperSourcePath);nativeActions=0;processActions=0;overCapHeld=true;mutationsRejected=2;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
