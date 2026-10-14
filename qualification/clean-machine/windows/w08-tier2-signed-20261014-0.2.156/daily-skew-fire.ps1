# Phase B of the daily-window clock-skew proof (state from daily-skew-setup + the forged firstFailureEpoch run: retry.json dailyMode, one-shot TimeTrigger 24 h ahead). Skews the Sandbox clock to trigger + 30 s, polls, restores.
$ErrorActionPreference = 'Continue'
$d = Join-Path $env:LOCALAPPDATA 'SliceApp\repair'
function ReadG([string]$n) { try { $fs = [IO.File]::Open((Join-Path $d $n), 'Open', 'Read', 'ReadWrite'); try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } } catch { $null } }
function Task { $t = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs.SliceApp*-Repair' } | Select-Object -First 1; if ($t) { $i = Get-ScheduledTaskInfo -InputObject $t; [ordered]@{ state = [string]$t.State; lastRun = $i.LastRunTime.ToString('o'); lastResult = [int]$i.LastTaskResult; nextRun = $(if ($i.NextRunTime) { $i.NextRunTime.ToString('o') } else { $null }) } } }
$o = [ordered]@{}
$startUtc = (Get-Date).ToUniversalTime(); $sw = [Diagnostics.Stopwatch]::StartNew()
$o.startUtc = $startUtc.ToString('o')
try {
    $rj = ReadG 'retry.json' | ConvertFrom-Json
    $o.retry_before = $rj
    $o.task_before = Task
    $next = ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime().AddSeconds([double]$rj.nextEpoch)
    $o.trigger_utc = $next.ToString('o'); $o.trigger_hours_ahead = [math]::Round(($next - $startUtc).TotalHours, 2)
    $mark = (ReadG 'repair.log').Length
    Set-Date -Date $next.AddSeconds(30).ToLocalTime() | Out-Null
    $o.skewed_to_utc = (Get-Date).ToUniversalTime().ToString('o')
    $fired = $false; $e = (Get-Date).AddSeconds(100)
    while ((Get-Date) -lt $e) { $t = ReadG 'repair.log'; if ($t.Substring([math]::Min($mark, $t.Length)) -match 'package NOT healthy') { $fired = $true; break }; Start-Sleep -Seconds 2 }
    $o.guard_started_by_daily_trigger = $fired
    $o.task_at_fire = Task
    if ($fired) { Start-Sleep -Seconds 25 }
    $t = ReadG 'repair.log'; $o.log_during_skew = @($t.Substring([math]::Min($mark, $t.Length)) -split "`r?`n" | Where-Object { $_ })
    $o.retry_after = ReadG 'retry.json' | ConvertFrom-Json
} catch { $o.error = $_.Exception.Message }
finally {
    Set-Date -Date ($startUtc.AddSeconds($sw.Elapsed.TotalSeconds).ToLocalTime()) | Out-Null
    $o.clock_restored_utc = (Get-Date).ToUniversalTime().ToString('o'); $o.expected_utc = $startUtc.AddSeconds($sw.Elapsed.TotalSeconds).ToString('o')
}
'JSON-BEGIN'; ($o | ConvertTo-Json -Depth 6); 'JSON-END'
