# Runs ONE command as the logged-in Dell user in a NON-ELEVATED context (RightKit's ownership gate refuses an elevated token,
# and an SSH session is a High-integrity admin token). Registers a one-shot Interactive/Limited hidden scheduled task, waits for
# it, copies its log, unregisters it. Needs an interactive logon (the console session); nothing is shown on the desktop.
# Used for `right-release build --platform win` (RESULT-R2.md) and for starting the Windows Sandbox (R5, needs the desktop).
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\run-unelevated-step.ps1 -Log <file> -WorkDir <dir> -Cmd '<powershell command>' [-TimeoutMin 60]"
# The log's first line records `elevated=False` when the gate will accept the run; `EXIT=<code>` is the last line.
param(
    [Parameter(Mandatory)][string]$Cmd, [Parameter(Mandatory)][string]$Log, [string]$WorkDir = 'D:\Claude',
    [int]$TimeoutMin = 60, [string]$TaskName = ''
)
$ErrorActionPreference = 'Stop'
if (-not $TaskName) { $TaskName = 'sr0-r5-step-' + [guid]::NewGuid().ToString('N').Substring(0, 8) }
$step = $Log + '.step.ps1'
$cmdFile = $Log + '.cmd.txt'
[IO.File]::WriteAllText($cmdFile, $Cmd, (New-Object Text.UTF8Encoding($false)))
$body = @"
`$ErrorActionPreference = 'Continue'
`$id = [Security.Principal.WindowsIdentity]::GetCurrent()
`$elev = (New-Object Security.Principal.WindowsPrincipal(`$id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
'=== ' + (Get-Date -Format o) + ' elevated=' + `$elev + ' user=' + `$env:USERNAME | Out-File -FilePath '$Log' -Encoding utf8
Set-Location -LiteralPath '$WorkDir'
`$c = [IO.File]::ReadAllText('$cmdFile')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `$c *>&1 | Out-File -FilePath '$Log' -Encoding utf8 -Append
'EXIT=' + `$LASTEXITCODE | Out-File -FilePath '$Log' -Encoding utf8 -Append
"@
[IO.File]::WriteAllText($step, $body, (New-Object Text.UTF8Encoding($false)))
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $step + '"')
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes ($TimeoutMin + 5))
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
try {
    Start-ScheduledTask -TaskName $TaskName
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    $done = $false
    while ((Get-Date) -lt $deadline -and -not $done) {
        Start-Sleep -Seconds 5
        $done = (Test-Path -LiteralPath $Log) -and ((Get-Content -LiteralPath $Log -Tail 3 -ErrorAction SilentlyContinue) -match '^EXIT=')
    }
    if (-not $done) { "timeout after $TimeoutMin min; log: $Log"; exit 3 }
    Get-Content -LiteralPath $Log -Tail 5
    $exit = [int](((Get-Content -LiteralPath $Log -Tail 3) | Where-Object { $_ -match '^EXIT=' } | Select-Object -Last 1) -replace '^EXIT=', '')
    exit $exit
}
finally { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
