# Daily-window proof by clock skew (Windows Sandbox only, through client.py command). Precondition: `client.py w08 tier2-feed-down-long --keep-state` left the package NeedsRemediation, the feed down and retry 1 pending.
# 1 forge firstFailureEpoch to 25 h ago (retry.json is the guard's own state file; this stands in for 24 h of failed retries)
# 2 the next natural retry run must switch to dailyMode: one-shot trigger a full 24 h ahead
# 3 set the Sandbox clock to that trigger + 30 s: the task must fire and the guard must start an attempt (repair.log)
# 4 restore the clock (original UTC + elapsed stopwatch time)
$ErrorActionPreference = 'Continue'
$d = Join-Path $env:LOCALAPPDATA 'SliceApp\repair'
function ReadG([string]$n) { try { $fs = [IO.File]::Open((Join-Path $d $n), 'Open', 'Read', 'ReadWrite'); try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } } catch { $null } }
function Task { $t = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs.SliceApp*-Repair' } | Select-Object -First 1; if ($t) { $i = Get-ScheduledTaskInfo -InputObject $t; [ordered]@{ state = [string]$t.State; lastRun = $i.LastRunTime.ToString('o'); lastResult = [int]$i.LastTaskResult; nextRun = $(if ($i.NextRunTime) { $i.NextRunTime.ToString('o') } else { $null }); triggers = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName + $(if ($_.StartBoundary) { ' ' + $_.StartBoundary } else { '' }) }) } } }
function WaitLog([string]$re, [int]$sec) { $e = (Get-Date).AddSeconds($sec); while ((Get-Date) -lt $e) { if ((ReadG 'repair.log') -match $re) { return $true }; Start-Sleep -Seconds 2 }; $false }
$o = [ordered]@{ tz = (Get-TimeZone).Id; startUtc = (Get-Date).ToUniversalTime().ToString('o') }
$startUtc = (Get-Date).ToUniversalTime(); $sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $o.package = @(Get-AppxPackage -Name OrthicLabs.SliceApp | ForEach-Object { [string]$_.Version + ':' + [string]$_.Status })
    $o.retry_before = ReadG 'retry.json'
    $o.task_before = Task
    $st = ReadG 'retry.json' | ConvertFrom-Json
    if (-not $st) { throw 'no retry.json: the long-run state is not in place' }
    $nowEpoch = [math]::Floor(([datetime]::UtcNow - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)
    $st.firstFailureEpoch = $nowEpoch - 25 * 3600
    [IO.File]::WriteAllText((Join-Path $d 'retry.json'), ($st | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $o.forged_firstFailureEpoch = $st.firstFailureEpoch
    $logLen0 = (ReadG 'repair.log').Length
    # wait for the natural retry run (<= ~2 min after the first failure) to re-register in dailyMode
    $o.daily_mode_logged = WaitLog 'daily window 1' 240
    $o.retry_after_daily_switch = ReadG 'retry.json'
    $o.task_after_daily_switch = Task
    $rj = $o.retry_after_daily_switch | ConvertFrom-Json
    if ($rj -and $rj.nextEpoch) {
        $next = ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime().AddSeconds([double]$rj.nextEpoch)
        $o.next_trigger_utc = $next.ToString('o'); $o.next_trigger_hours_ahead = [math]::Round(($next - (Get-Date).ToUniversalTime()).TotalHours, 2)
        $mark = (ReadG 'repair.log').Length
        # skew the clock to the trigger + 30 s
        Set-Date -Date $next.AddSeconds(30).ToLocalTime() | Out-Null
        $o.skewed_to_utc = (Get-Date).ToUniversalTime().ToString('o')
        $fired = $false; $e = (Get-Date).AddSeconds(150)
        while ((Get-Date) -lt $e) { $t = (ReadG 'repair.log'); if ($t.Substring([math]::Min($mark, $t.Length)) -match 'package NOT healthy') { $fired = $true; break }; Start-Sleep -Seconds 2 }
        $o.daily_trigger_fired_guard_started = $fired
        $o.log_after_skew = @((ReadG 'repair.log').Substring([math]::Min($mark, (ReadG 'repair.log').Length)) -split "`r?`n" | Where-Object { $_ })
        Start-Sleep -Seconds 20
        $o.retry_after_fire = ReadG 'retry.json'
        $o.task_after_fire = Task
    }
} catch { $o.error = $_.Exception.Message }
finally {
    # restore the clock: original UTC + elapsed real time
    Set-Date -Date ($startUtc.AddSeconds($sw.Elapsed.TotalSeconds).ToLocalTime()) | Out-Null
    $o.clock_restored_utc = (Get-Date).ToUniversalTime().ToString('o'); $o.expected_utc = $startUtc.AddSeconds($sw.Elapsed.TotalSeconds).ToString('o')
    $o.guard_file_sha256 = $(try { (Get-FileHash -LiteralPath (Join-Path $d 'repair-guard.ps1') -Algorithm SHA256).Hash.ToLower() } catch { $null })
}
'JSON-BEGIN'; ($o | ConvertTo-Json -Depth 6); 'JSON-END'
