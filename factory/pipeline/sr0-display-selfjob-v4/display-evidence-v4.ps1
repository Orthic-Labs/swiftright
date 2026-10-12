# Bounded PresentMon displayed-row observer. No qualification claim.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PresentMonCsv,[Parameter(Mandatory)][string]$MetaPath,[Parameter(Mandatory)][string]$OutputPath,[int64]$MaxCsvBytes=67108864,[int64]$MaxMetaBytes=2097152,[int64]$MaxRows=2000000)
$ErrorActionPreference='Stop'
function Check-Bounded([string]$Path,[int64]$Limit){$item=Get-Item -LiteralPath $Path -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded read rejected: $Path"};return $item}
function Read-BoundedText([string]$Path,[int64]$Limit){Check-Bounded $Path $Limit|Out-Null;return [IO.File]::ReadAllText($Path)}
function Num([object]$Value){[double]$n=0;if([double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)){if([double]::IsNaN($n)-or[double]::IsInfinity($n)){return $null};return $n};return $null}
function Read-CsvHeader([string]$Line){if($Line.Length -gt 131072){throw 'PresentMon header exceeds bound'};$columns=New-Object 'System.Collections.Generic.List[string]';$builder=New-Object Text.StringBuilder;$quoted=$false;for($i=0;$i -lt $Line.Length;$i++){[char]$ch=$Line[$i];if($ch -eq [char]34){if($quoted -and $i+1 -lt $Line.Length -and $Line[$i+1] -eq [char]34){[void]$builder.Append([char]34);$i++}else{$quoted=-not $quoted}}elseif($ch -eq ',' -and -not $quoted){[void]$columns.Add($builder.ToString());[void]$builder.Clear()}else{[void]$builder.Append($ch)}};if($quoted){throw 'PresentMon header quote is unterminated'};[void]$columns.Add($builder.ToString());return @($columns|ForEach-Object{$_.Trim()})}
$metaText=Read-BoundedText $MetaPath $MaxMetaBytes;$meta=$metaText|ConvertFrom-Json
foreach($field in @('pid','run_id','measure_start_ticks','measure_end_ticks','hz')){if($null -eq $meta.$field){throw "meta field missing: $field"}}
$workloadPid=[string]$meta.pid;$start=[double]$meta.measure_start_ticks;$end=[double]$meta.measure_end_ticks;$hz=[double]$meta.hz;if($end -le $start -or $hz -le 0){throw 'invalid QPC measure bounds'}
$csvItem=Check-Bounded $PresentMonCsv $MaxCsvBytes
$header=([string](Get-Content -LiteralPath $PresentMonCsv -TotalCount 1 -Encoding UTF8)).TrimStart([char]0xFEFF);$columns=Read-CsvHeader $header;foreach($required in @('Application','ProcessID','Dropped','msUntilDisplayed')){if(@($columns)-notcontains $required){throw 'PresentMon v2.6 display columns missing'}}
$qcol=if(@($columns)-contains 'CPUStartQPC'){'CPUStartQPC'}elseif(@($columns)-contains 'QPCTime'){'QPCTime'}else{$null};if($null -eq $qcol){throw 'PresentMon QPC column missing'}
$counts=[ordered]@{rows=0;raw=0;displayed=0;dropped=0;invalidDisplay=0}
Import-Csv -LiteralPath $PresentMonCsv | ForEach-Object {
  $counts.rows++;if($counts.rows -gt $MaxRows){throw "PresentMon row cap exceeded: $MaxRows"}
  if([string]$_.Application -ne 'WorkloadWin.exe' -or [string]$_.ProcessID -ne $workloadPid){return}
  $q=Num $_.$qcol;if($null -eq $q -or $q -lt $start -or $q -gt $end){return}
  $counts.raw++;$dropText=[string]$_.Dropped;$untilText=[string]$_.msUntilDisplayed;if($dropText -eq '1'){$counts.dropped++}elseif($dropText -eq '0' -and $untilText.Trim() -ne '' -and $null -ne (Num $untilText)){$counts.displayed++}else{$counts.invalidDisplay++}
}
$status=if($counts.raw -eq 0){'held'}elseif($counts.displayed -eq 0){'held'}else{'observed'};$reason=if($counts.raw -eq 0){'no-presentmon-rows-for-pid-in-measure-window'}elseif($counts.displayed -eq 0){'all-presentmon-rows-dropped-or-occluded'}else{'displayed-rows-observed'};$displayEvidence=if($status -eq 'observed'){'observed'}else{'held'}
$obj=[ordered]@{schema='sr0-display-evidence-v4';status=$status;reason=$reason;runId=[string]$meta.run_id;pid=$workloadPid;qpcColumn=$qcol;measureStartTicks=$start;measureEndTicks=$end;rawPresentRows=$counts.raw;displayedRows=$counts.displayed;droppedRows=$counts.dropped;invalidDisplayRows=$counts.invalidDisplay;presentmonCsv=$PresentMonCsv;metaPath=$MetaPath;nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged';qualification='separate-workload-gate';displayEvidence=$displayEvidence;sourceBytes=[ordered]@{csv=$csvItem.Length;meta=(Get-Item -LiteralPath $MetaPath).Length};rowCap=$MaxRows}
$parent=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$obj|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$obj|ConvertTo-Json -Depth 12
