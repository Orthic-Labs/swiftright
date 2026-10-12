$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\sr0-launcher-controls-r1.zip';$s='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\launcher-controls-r1'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne 'd77a7dc1619eae925e800388a933ef6fdf19a3ded4155a35c82e0e3cc0e15268' -or (Test-Path $s)){throw 'fresh pinned launcher control stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $s
$pins=Get-Content -Raw (Join-Path $s 'pins.json')|ConvertFrom-Json
foreach($row in $pins.files){$f=Join-Path $s $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'launcher source pin drift'};if($row.path.EndsWith('.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}}
& (Join-Path $s 'test-launcher-controls-v4.ps1') -WorkerPath (Join-Path $s 'run-once-v4.ps1') -SchedulePath (Join-Path $s 'schedule-once-v4.ps1') -HelperPath (Join-Path $s 'Sr0OwnedJobProcess-v15.cs') -LauncherHelperPath (Join-Path $s 'Sr0LauncherOwnedJobProcess-v4.cs') -OutputPath (Join-Path $s 'source-controls.json')
& (Join-Path $s 'test-launcher-job-controls-v4.ps1') -LauncherHelperPath (Join-Path $s 'Sr0LauncherOwnedJobProcess-v4.cs') -OutputPath (Join-Path $s 'job-controls.json')
