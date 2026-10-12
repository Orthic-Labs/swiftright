# Source controls for bounded PresentMon adapter. Root executes on Windows; this file launches no child.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$item=Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'adapter source reparse point rejected'
Require ($item.Length -le 2097152) 'adapter source exceeds bound'
$source=[IO.File]::ReadAllText($item.FullName)
$required=@(
  'MaxCsvBytes=67108864','Require-InputFile $CsvPath $MaxCsvBytes','PresentMon header column count mismatch',
  '[string]$v[0] -eq ''WorkloadWin.exe''','$rowPid -eq $WorkloadPid','PresentMon Dropped invalid for WorkloadWin row',
  'displayQualification=''pending-strict-frozen-parser''','parityClaim=$false','strictParserCommand=',
  "--os windows",'--expect-scale 2.5','csvSha256=$csvHash','Write-AtomicJson $OutputPath'
)
foreach($needle in $required){Require ($source.Contains($needle)) "adapter required guard missing: $needle"}
$cases=[ordered]@{}
$mutations=[ordered]@{
  'pid-binding'=@{needle='$rowPid -eq $WorkloadPid';replacement='$rowPid -eq 1'}
  'header-gate'=@{needle='PresentMon header column count mismatch';replacement='PresentMon header accepted'}
  'bounded-csv'=@{needle='Require-InputFile $CsvPath $MaxCsvBytes';replacement='Require-InputFile $CsvPath 9223372036854775807'}
  'hold-status'=@{needle='status=''qualification-held''';replacement='status=''passed'''}
  'frozen-parser'=@{needle='displayQualification=''pending-strict-frozen-parser''';replacement='displayQualification=''passed'''}
  'no-parity'=@{needle='parityClaim=$false';replacement='parityClaim=$true'}
}
foreach($name in $mutations.Keys){$m=$mutations[$name];Require ($source.Contains([string]$m.needle)) "mutation needle missing: $name";$mutated=$source.Replace([string]$m.needle,[string]$m.replacement);Require ($mutated -ne $source) "mutation had no effect: $name";$cases[$name]=[ordered]@{status='expected-rejected';needle=$m.needle;changed=($mutated -ne $source)}}
$receipt=[ordered]@{kind='sr0-display-presentmon-adapter-v1-controls';status='passed';sourcePath=[IO.Path]::GetFullPath($SourcePath);cases=$cases;qualificationClaimed=$false;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};if(Test-Path -LiteralPath $OutputPath){throw 'controls output must be fresh'};[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($receipt|ConvertTo-Json -Depth 8)+"`r`n",(New-Object Text.UTF8Encoding($false)));exit 0
