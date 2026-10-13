# guest-worker.ps1 - runs INSIDE the long-lived Windows Sandbox (started once by logon.cmd). Polls C:\sbq\queue every 2 s for job files <id>.json
# {"kind":"capture|w08|command","timeoutSec":N,"args":{...}} and runs each through guest\job-<kind>.ps1 in a child process (so a hung job never kills the loop and
# job scripts can be updated without restarting the Sandbox). Per job: results\<id>\{job.json,status.json,stdout.txt,stderr.txt,result.json,DONE}.
# The worker maps D:\ (subst) so host-built executables with absolute D:\Claude\swiftright\.factory-work paths run unchanged. The Sandbox is NEVER restarted per job.
$ErrorActionPreference = 'Continue'
$Root = 'C:\sbq'; $Q = "$Root\queue"; $Res = "$Root\results"; $State = "$Root\state"; $Guest = "$Root\guest"
$Utf8 = New-Object Text.UTF8Encoding($false)
foreach ($d in $Q, $Res, $State) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
function WL([string]$s) { try { [IO.File]::AppendAllText("$State\worker.log", (Get-Date -Format 'o') + ' ' + $s + "`r`n", $Utf8) } catch { } }
$script:CurrentJob = ''
function Beat { try { [IO.File]::WriteAllText("$State\hb.json", (ConvertTo-Json @{ utc = (Get-Date).ToUniversalTime().ToString('o'); pid = $PID; job = $script:CurrentJob; host = $env:COMPUTERNAME })) } catch { } }

# ---- D: mapping: D:\Claude\swiftright\.factory-work -> mapped host folder (read-only), D:\ itself is a subst of C:\dmap
function Initialize-DriveMap {
    try {
        $fw = 'C:\dmap\Claude\swiftright\.factory-work'
        if (-not (Test-Path -LiteralPath 'C:\dmap\Claude\swiftright')) { New-Item -ItemType Directory -Force -Path 'C:\dmap\Claude\swiftright' | Out-Null }
        if (-not (Test-Path -LiteralPath $fw)) { & cmd.exe /c mklink /J "$fw" C:\hostfw | Out-Null }
        if (-not (Test-Path -LiteralPath 'D:\')) { & subst.exe D: C:\dmap | Out-Null }
        $ok = Test-Path -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'
        WL ('drive map D: ok=' + $ok)
        return $ok
    } catch { WL ('drive map failed: ' + $_.Exception.Message); return $false }
}
$driveOk = Initialize-DriveMap
$env:Path = 'C:\swiftrt;' + $env:Path
WL ('worker start pid=' + $PID + ' os=' + [Environment]::OSVersion.Version + ' user=' + $env:USERNAME + ' drive_map=' + $driveOk)
try { WL ('video: ' + ((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + ' drv=' + $_.DriverVersion }) -join '; ')) } catch { }

function Write-Json([string]$Path, $Obj) { [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Obj -Depth 8), $Utf8) }

function Invoke-Job([string]$Id) {
    $dir = "$Res\$Id"
    $job = $null
    try { $job = Get-Content -LiteralPath "$dir\job.json" -Raw | ConvertFrom-Json } catch { Write-Json "$dir\status.json" @{ state = 'error'; error = 'unparseable job.json' }; Set-Content "$dir\DONE" 'error'; return }
    $kind = [string]$job.kind
    $timeout = $(if ($job.timeoutSec) { [int]$job.timeoutSec } else { 600 })
    $script = "$Guest\job-$kind.ps1"
    $t0 = Get-Date
    WL ("job $Id kind=$kind timeout=$timeout")
    if ($kind -notmatch '^[a-z0-9]+$' -or -not (Test-Path -LiteralPath $script)) {
        Write-Json "$dir\status.json" @{ state = 'error'; error = "unknown job kind '$kind'"; id = $Id }; Set-Content "$dir\DONE" 'error'; return
    }
    Write-Json "$dir\status.json" @{ state = 'running'; id = $Id; kind = $kind; started_utc = $t0.ToUniversalTime().ToString('o') }
    $p = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -RedirectStandardOutput "$dir\stdout.txt" -RedirectStandardError "$dir\stderr.txt" `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-JobDir', $dir)
    while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt $timeout) { Beat; Start-Sleep -Milliseconds 500 }
    $state = 'done'
    if (-not $p.HasExited) {
        $state = 'timeout'
        & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        WL ("job $Id TIMEOUT after $timeout s; killed")
    }
    $ec = $(if ($p.HasExited) { $p.ExitCode } else { -1 })
    Write-Json "$dir\status.json" @{ state = $state; id = $Id; kind = $kind; exit_code = $ec; started_utc = $t0.ToUniversalTime().ToString('o'); ended_utc = (Get-Date).ToUniversalTime().ToString('o'); seconds = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1) }
    Set-Content -LiteralPath "$dir\DONE" -Value $state
    WL ("job $Id $state exit=$ec")
}

while ($true) {
    Beat
    try {
        $files = @(Get-ChildItem -LiteralPath $Q -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($f in $files) {
            $id = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $dir = "$Res\$id"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            try { Move-Item -LiteralPath $f.FullName -Destination "$dir\job.json" -Force -ErrorAction Stop } catch { WL ("claim failed $id : " + $_.Exception.Message); continue }
            $script:CurrentJob = $id
            try { Invoke-Job $id } catch { WL ("job $id worker exception: " + $_.Exception.Message); try { Set-Content "$dir\DONE" 'error' } catch { } }
            $script:CurrentJob = ''
        }
    } catch { WL ('loop exception: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 2
}
