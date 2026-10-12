$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\sr0-selfjob-v4-controls-r2.zip';$s='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\controls-r2'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne '3d5091f0895e353f1bdf760ff22127ddd6bc69b4f3d5ff51727a9be82934ead5' -or (Test-Path $s)){throw 'fresh pinned control stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $s
$pins=Get-Content -Raw (Join-Path $s 'pins.json')|ConvertFrom-Json
foreach($row in $pins.files){$f=Join-Path $s $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'source pin drift'}}
Add-Type -Path (Join-Path $s 'Sr0OwnedJobProcess-v15.cs')
$job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824)
try{
 foreach($row in $pins.files|Where-Object{$_.path.EndsWith('.ps1')}){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $s $row.path),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
 & (Join-Path $s 'test-receipt-parser-controls-v4.ps1') -ParserPath (Join-Path $s 'receipt-parser-v4.ps1') -ArchivedReceipt (Join-Path $s 'archived-v7.txt') -OutputPath (Join-Path $s 'parser-controls.json') -Runs 3
 & (Join-Path $s 'test-envelope-controls-v4.ps1') -SourcePath (Join-Path $s 'interactive-selfjob-v4.ps1') -FrozenTaskPath (Join-Path $s 'task-workload-v8.ps1') -HelperPath (Join-Path $s 'Sr0OwnedJobProcess-v15.cs') -ParserPath (Join-Path $s 'receipt-parser-v4.ps1') -OutputPath (Join-Path $s 'envelope-controls.json')
 $m=$job.QueryPeakJobMemory();[Sr0OwnedJobProcess]::RequireOnlyCurrent($m);@{limit=$m.JobMemoryLimitBytes;flags=$m.LimitFlags;peak=$m.PeakJobMemoryUsedBytes;active=$m.ActiveProcessCount;nativeActions=0;lockActions=0}|ConvertTo-Json|Set-Content (Join-Path $s 'memory.json') -Encoding UTF8
}finally{$job.Dispose()}
