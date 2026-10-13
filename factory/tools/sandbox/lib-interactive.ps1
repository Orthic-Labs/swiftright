# lib-interactive.ps1 - dot-source. Invoke-Interactive runs one PowerShell file in the logged-in user's INTERACTIVE session (needed by Windows Sandbox
# and by anything that reads the real desktop: GetForegroundWindow, IsIconic) through a one-shot Interactive/Limited scheduled task. The task runs
# through a hidden wscript wrapper (Run style 0): no console, no window. Same path as run-unelevated-task.ps1; nothing is shown on the desktop.
function Invoke-Interactive {
    param([Parameter(Mandatory)][string]$File, [string]$FileArgs = '', [Parameter(Mandatory)][string]$WorkDir, [int]$TimeoutSec = 120, [string]$User = 'adrds')
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $task = 'SwiftRightSandbox-' + $id
    $vbs = Join-Path $WorkDir ("task-$id.vbs")
    $exitFile = Join-Path $WorkDir ("task-$id.exit")
    $cmd = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $File + '" ' + $FileArgs
    $body = 'Set sh = CreateObject("WScript.Shell")' + "`r`n" + 'rc = sh.Run("' + $cmd.Replace('"', '""') + '", 0, True)' + "`r`n" +
        'Set fso = CreateObject("Scripting.FileSystemObject")' + "`r`n" + 'Set f = fso.CreateTextFile("' + $exitFile + '", True)' + "`r`n" + 'f.Write rc' + "`r`n" + 'f.Close' + "`r`n" + 'WScript.Quit rc'
    [IO.File]::WriteAllText($vbs, $body, [Text.Encoding]::ASCII)
    $act = New-ScheduledTaskAction -Execute "$env:windir\System32\wscript.exe" -Argument ('"' + $vbs + '"')
    $pr = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
    $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds ($TimeoutSec + 60)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $task -Action $act -Principal $pr -Settings $set | Out-Null
    try {
        Start-ScheduledTask -TaskName $task
        $dl = (Get-Date).AddSeconds($TimeoutSec)
        while (-not (Test-Path -LiteralPath $exitFile) -and (Get-Date) -lt $dl) { Start-Sleep -Milliseconds 300 }
        if (-not (Test-Path -LiteralPath $exitFile)) { return -999 }
        return [int](Get-Content -LiteralPath $exitFile -Raw)
    }
    finally {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
        # never delete on the Dell: park the helper files
        $park = 'D:\Claude\swiftright\.work\sandbox-task-files'
        New-Item -ItemType Directory -Force -Path $park | Out-Null
        foreach ($f in @($vbs, $exitFile)) { if (Test-Path -LiteralPath $f) { Move-Item -LiteralPath $f -Destination $park -Force -ErrorAction SilentlyContinue } }
    }
}
