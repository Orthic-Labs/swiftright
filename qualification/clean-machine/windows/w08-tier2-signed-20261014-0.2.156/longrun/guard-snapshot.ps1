# Runs INSIDE the Windows Sandbox (client.py command). Read-only: prints one JSON object (marker lines JSON-BEGIN / JSON-END) with the guard's receipts, log, task state and package state.
$ErrorActionPreference = 'Continue'
$d = Join-Path $env:LOCALAPPDATA 'SliceApp\repair'
function ReadG([string]$n) { try { $fs = [IO.File]::Open((Join-Path $d $n), 'Open', 'Read', 'ReadWrite'); try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } } catch { $null } }
$o = [ordered]@{ nowLocal = (Get-Date).ToString('o'); nowUtc = (Get-Date).ToUniversalTime().ToString('o'); tz = (Get-TimeZone).Id }
$o.packages = @(Get-AppxPackage -Name OrthicLabs.SliceApp -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Version + ':' + [string]$_.Status })
$t = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs.SliceApp*-Repair' } | Select-Object -First 1
if ($t) {
    $i = Get-ScheduledTaskInfo -InputObject $t
    $o.task = [ordered]@{ name = $t.TaskName; state = [string]$t.State; lastRun = $i.LastRunTime.ToString('o'); lastResult = [int]$i.LastTaskResult; nextRun = $(if ($i.NextRunTime) { $i.NextRunTime.ToString('o') } else { $null })
        triggers = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName + $(if ($_.StartBoundary) { ' ' + $_.StartBoundary } else { '' }) }) }
}
$o.guardDir = $d
$o.guardFileSha256 = $(try { (Get-FileHash -LiteralPath (Join-Path $d 'repair-guard.ps1') -Algorithm SHA256).Hash.ToLower() } catch { $null })
foreach ($f in 'retry.json', 'last-result.json', 'install-result.json', 'install-attempt.json', 'install-launch-failure.json', 'guard.json') { $o[$f] = ReadG $f }
$o.repairLog = @((ReadG 'repair.log') -split "`r?`n" | Where-Object { $_ })
$o.feedUp = $(try { (Invoke-WebRequest -Uri 'https://localhost:8443/sliceapp/SliceApp.appinstaller' -UseBasicParsing -TimeoutSec 4).StatusCode -eq 200 } catch { $false })
'JSON-BEGIN'; ($o | ConvertTo-Json -Depth 6 -Compress); 'JSON-END'
