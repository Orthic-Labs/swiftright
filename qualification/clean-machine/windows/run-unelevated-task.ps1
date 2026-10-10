# Runs ONE command as the logged-in Dell user in a NON-ELEVATED interactive context (an SSH session is a High-integrity admin token, and Windows Sandbox
# needs the desktop). Registers a one-shot Interactive/Limited hidden scheduled task, waits for it, prints the log tail, and DISABLES (never deletes) the task.
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File <this> -Log <file> -WorkDir <dir> -Cmd '<powershell command>' [-TimeoutMin 60]"
# The log's first line records `elevated=False`; `EXIT=<code>` is the last line. Hold D:\Claude\desktop.lock around the call (with-desktop-lock.ps1).
param([Parameter(Mandatory = $true)][string]$Cmd, [Parameter(Mandatory = $true)][string]$Log, [string]$WorkDir = 'D:\Claude', [int]$TimeoutMin = 60)
$ErrorActionPreference = 'Stop'
$TaskName = 'sr0-t12-step-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 4)
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
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings | Out-Null
try {
    Start-ScheduledTask -TaskName $TaskName
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    $done = $false
    while ((Get-Date) -lt $deadline -and -not $done) {
        Start-Sleep -Seconds 5
        $done = (Test-Path -LiteralPath $Log) -and ((Get-Content -LiteralPath $Log -Tail 3 -ErrorAction SilentlyContinue) -match '^EXIT=')
    }
    if (-not $done) { "timeout after $TimeoutMin min; log: $Log"; exit 3 }
    Get-Content -LiteralPath $Log -Tail 8
    $exit = [int](((Get-Content -LiteralPath $Log -Tail 3) | Where-Object { $_ -match '^EXIT=' } | Select-Object -Last 1) -replace '^EXIT=', '')
    exit $exit
}
finally { Disable-ScheduledTask -TaskName $TaskName | Out-Null; "disabled task $TaskName" }
