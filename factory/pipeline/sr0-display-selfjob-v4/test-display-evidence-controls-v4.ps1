# Display evidence controls. Same bounded analyzer, actual capture plus explicit mutations.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AnalyzerPath,
  [Parameter(Mandatory)][string]$PresentMonCsv,
  [Parameter(Mandatory)][string]$MetaPath,
  [Parameter(Mandatory)][string]$OutputPath,
  [int64]$MaxCsvBytes=67108864,
  [int64]$MaxMetaBytes=2097152,
  [int64]$MaxRows=2000000
)
$ErrorActionPreference='Stop'
$parent=Split-Path -Parent $OutputPath
if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}

function Get-Bounded([string]$Path,[int64]$Limit){
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded input rejected: $Path"}
  return $item
}
function Write-Utf8([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding -ArgumentList $false;[IO.File]::WriteAllText($Path,$Text,$enc)}
function Read-CsvHeader([string]$Line){if($Line.Length -gt 131072){throw 'PresentMon header exceeds bound'};$columns=New-Object 'System.Collections.Generic.List[string]';$builder=New-Object Text.StringBuilder;$quoted=$false;for($i=0;$i -lt $Line.Length;$i++){[char]$ch=$Line[$i];if($ch -eq [char]34){if($quoted -and $i+1 -lt $Line.Length -and $Line[$i+1] -eq [char]34){[void]$builder.Append([char]34);$i++}else{$quoted=-not $quoted}}elseif($ch -eq ',' -and -not $quoted){[void]$columns.Add($builder.ToString());[void]$builder.Clear()}else{[void]$builder.Append($ch)}};if($quoted){throw 'PresentMon header quote is unterminated'};[void]$columns.Add($builder.ToString());return @($columns|ForEach-Object{$_.Trim()})}
function Invoke-Case([string]$Name,[string]$Csv,[string]$Meta,[string]$ExpectedStatus,[string]$ExpectedReason){
  Get-Bounded $Csv $MaxCsvBytes|Out-Null;Get-Bounded $Meta $MaxMetaBytes|Out-Null
  $out=Join-Path $parent "display-$Name.json"
  & $AnalyzerPath -PresentMonCsv $Csv -MetaPath $Meta -OutputPath $out | Out-Null
  $result=Get-Content -Raw -LiteralPath $out|ConvertFrom-Json
  if([string]$result.status -ne $ExpectedStatus -or [string]$result.reason -ne $ExpectedReason){throw "display case $Name mismatch: $($result.status)/$($result.reason)"}
  return [ordered]@{name=$Name;status=[string]$result.status;reason=[string]$result.reason;rawPresentRows=[int64]$result.rawPresentRows;displayedRows=[int64]$result.displayedRows;droppedRows=[int64]$result.droppedRows}
}

$csvItem=Get-Bounded $PresentMonCsv $MaxCsvBytes
$metaItem=Get-Bounded $MetaPath $MaxMetaBytes
$header=[string](Get-Content -LiteralPath $PresentMonCsv -TotalCount 1 -Encoding UTF8)
$columns=Read-CsvHeader $header;foreach($required in @('Application','ProcessID','Dropped','msUntilDisplayed')){if(@($columns)-notcontains $required){throw 'PresentMon mutation columns missing'}}
$qpcColumn=if(@($columns)-contains 'CPUStartQPC'){'CPUStartQPC'}elseif(@($columns)-contains 'QPCTime'){'QPCTime'}else{throw 'PresentMon mutation QPC column missing'}
$actual=Invoke-Case 'positive' $PresentMonCsv $MetaPath 'observed' 'displayed-rows-observed'

$zeroCsv=Join-Path $parent 'mutated-all-dropped.csv'
$rowCounter=@{count=0}
Import-Csv -LiteralPath $PresentMonCsv | ForEach-Object {
  $rowCounter.count++;if($rowCounter.count -gt $MaxRows){throw "PresentMon row cap exceeded: $MaxRows"}
  if([string]$_.Application -eq 'WorkloadWin.exe'){$_.Dropped='1'}
  $_
} | Export-Csv -LiteralPath $zeroCsv -NoTypeInformation -Encoding UTF8
if($rowCounter.count -eq 0){throw 'PresentMon source has no rows for controls'}
$occluded=Invoke-Case 'all-dropped' $zeroCsv $MetaPath 'held' 'all-presentmon-rows-dropped-or-occluded'

$invalidCsv=Join-Path $parent 'mutated-invalid-display.csv'
$invalidCounter=@{count=0}
Import-Csv -LiteralPath $PresentMonCsv | ForEach-Object {
  $invalidCounter.count++;if($invalidCounter.count -gt $MaxRows){throw "PresentMon row cap exceeded: $MaxRows"}
  if([string]$_.Application -eq 'WorkloadWin.exe'){$_.Dropped='0';$_.msUntilDisplayed='NaN'}
  $_
} | Export-Csv -LiteralPath $invalidCsv -NoTypeInformation -Encoding UTF8
$invalidDisplay=Invoke-Case 'invalid-display' $invalidCsv $MetaPath 'held' 'all-presentmon-rows-dropped-or-occluded'
if($invalidDisplay.displayedRows -ne 0){throw 'invalid Dropped/msUntilDisplayed rows counted as displayed'}

$invalidTimingCsv=Join-Path $parent 'mutated-invalid-timing.csv'
$invalidTimingCounter=@{count=0}
Import-Csv -LiteralPath $PresentMonCsv | ForEach-Object {
  $invalidTimingCounter.count++;if($invalidTimingCounter.count -gt $MaxRows){throw "PresentMon row cap exceeded: $MaxRows"}
  if([string]$_.Application -eq 'WorkloadWin.exe'){$_.PSObject.Properties[$qpcColumn].Value='Infinity'}
  $_
} | Export-Csv -LiteralPath $invalidTimingCsv -NoTypeInformation -Encoding UTF8
$invalidTiming=Invoke-Case 'invalid-timing' $invalidTimingCsv $MetaPath 'held' 'no-presentmon-rows-for-pid-in-measure-window'
if($invalidTiming.rawPresentRows -ne 0 -or $invalidTiming.displayedRows -ne 0){throw 'NaN/Infinity timing markers counted as PresentMon rows'}

$missingCsv=Join-Path $parent 'mutated-header-only.csv'
Write-Utf8 $missingCsv ($header+"`r`n")
$zeroRows=Invoke-Case 'zero-rows' $missingCsv $MetaPath 'held' 'no-presentmon-rows-for-pid-in-measure-window'

$missingInput=Join-Path $parent 'missing-input.csv'
if(Test-Path -LiteralPath $missingInput){throw 'missing-input control path must be absent before run; refusing deletion'}
$missingRejected=$false
try { & $AnalyzerPath -PresentMonCsv $missingInput -MetaPath $MetaPath -OutputPath (Join-Path $parent 'display-missing-input.json') | Out-Null;throw 'missing input unexpectedly accepted' } catch { if($_.Exception.Message -match 'unexpectedly accepted'){throw};$missingRejected=$true }
$missing=[ordered]@{name='missing-input';status='rejected';reason='missing-explicit-csv';rawPresentRows=0;displayedRows=0;droppedRows=0}
if(-not $missingRejected){throw 'missing input was not rejected'}

$wrongMeta=Join-Path $parent 'mutated-wrong-pid-meta.json'
$meta=(Get-Content -Raw -LiteralPath $MetaPath|ConvertFrom-Json)
$meta.pid='0'
Write-Utf8 $wrongMeta ($meta|ConvertTo-Json -Depth 12)
$wrongPid=Invoke-Case 'wrong-pid' $PresentMonCsv $wrongMeta 'held' 'no-presentmon-rows-for-pid-in-measure-window'

$summary=[ordered]@{
  schema='sr0-display-evidence-controls-v4';status='passed';nativeActions=0;lockActions=0
  sourceCsv=$PresentMonCsv;sourceMeta=$MetaPath
  boundedLimits=[ordered]@{csvBytes=$MaxCsvBytes;metaBytes=$MaxMetaBytes;rows=$MaxRows}
  cases=@($actual,$occluded,$invalidDisplay,$invalidTiming,$zeroRows,$missing,$wrongPid)
  qualification='separate-workload-gate'
  nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged'
}
$summary|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $OutputPath -Encoding UTF8
$summary|ConvertTo-Json -Depth 16
