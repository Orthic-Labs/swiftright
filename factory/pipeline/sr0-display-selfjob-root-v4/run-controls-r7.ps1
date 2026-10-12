$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\sr0-selfjob-v4-controls-r7.zip';$s='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\controls-r7'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne '81bd176c88d5632d4a1d173585f46cf47f1663763d0aab2d0c6300462c3b5f3c' -or (Test-Path $s)){throw 'fresh pinned control stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $s
$pins=Get-Content -Raw (Join-Path $s 'pins.json')|ConvertFrom-Json
foreach($row in $pins.files){$f=Join-Path $s $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'source pin drift'}}
Add-Type -Path (Join-Path $s 'Sr0OwnedJobProcess-v15.cs')
$job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824)
try{
 foreach($row in $pins.files|Where-Object{$_.path.EndsWith('.ps1')}){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $s $row.path),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
 & (Join-Path $s 'test-receipt-parser-controls-v4.ps1') -ParserPath (Join-Path $s 'receipt-parser-v4.ps1') -ArchivedReceipt (Join-Path $s 'archived-v7.txt') -OutputPath (Join-Path $s 'parser-controls.json') -Runs 3
 & (Join-Path $s 'test-envelope-controls-v4.ps1') -SourcePath (Join-Path $s 'interactive-selfjob-v4.ps1') -FrozenTaskPath (Join-Path $s 'task-workload-v8.ps1') -HelperPath (Join-Path $s 'Sr0OwnedJobProcess-v15.cs') -ParserPath (Join-Path $s 'receipt-parser-v4.ps1') -OutputPath (Join-Path $s 'envelope-controls.json')
 & (Join-Path $s 'test-collector-envelope-controls-v4.ps1') -SourcePath (Join-Path $s 'collector-selfjob-v4.ps1') -OutputPath (Join-Path $s 'collector-controls.json')
 & (Join-Path $s 'test-coordinator-controls-v4.ps1') -SourcePath (Join-Path $s 'coordinator-selfjob-v4.ps1') -OutputPath (Join-Path $s 'coordinator-controls.json')
 & (Join-Path $s 'test-coordinator-receipt-controls-v4.ps1') -CoordinatorPath (Join-Path $s 'coordinator-selfjob-v4.ps1') -OutputPath (Join-Path $s 'coordinator-receipt-controls.json')
 & (Join-Path $s 'test-coordinator-positive-controls-v4.ps1') -CoordinatorPath (Join-Path $s 'coordinator-selfjob-v4.ps1') -ChildPath (Join-Path $s 'coordinator-child-fixture-v4.ps1') -OutputPath (Join-Path $s 'coordinator-positive-controls.json')
 & (Join-Path $s 'test-display-evidence-controls-v4.ps1') -AnalyzerPath (Join-Path $s 'display-evidence-v4.ps1') -PresentMonCsv (Join-Path $s 'presentmon-archived.csv') -MetaPath (Join-Path $s 'meta-archived.json') -OutputPath (Join-Path $s 'display-controls.json')
 & (Join-Path $s 'test-launcher-controls-v4.ps1') -WorkerPath (Join-Path $s 'run-once-v4.ps1') -SchedulePath (Join-Path $s 'schedule-once-v4.ps1') -HelperPath (Join-Path $s 'Sr0OwnedJobProcess-v15.cs') -LauncherHelperPath (Join-Path $s 'Sr0LauncherOwnedJobProcess-v4.cs') -OutputPath (Join-Path $s 'launcher-source-controls.json')
 & (Join-Path $s 'test-launcher-job-controls-v4.ps1') -LauncherHelperPath (Join-Path $s 'Sr0LauncherOwnedJobProcess-v4.cs') -OutputPath (Join-Path $s 'launcher-job-controls.json')
 $m=$job.QueryPeakJobMemory();[Sr0OwnedJobProcess]::RequireOnlyCurrent($m);@{limit=$m.JobMemoryLimitBytes;flags=$m.LimitFlags;peak=$m.PeakJobMemoryUsedBytes;active=$m.ActiveProcessCount;nativeActions=0;lockActions=0}|ConvertTo-Json|Set-Content (Join-Path $s 'memory.json') -Encoding UTF8
}finally{$job.Dispose()}
