$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$sessions=(& "$env:windir\System32\qwinsta.exe" 2>&1|Out-String)
$rows=@();foreach($pidValue in @(39404,21656)){$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$pidValue) -ErrorAction SilentlyContinue;if($p){$rows+=@{pid=$p.ProcessId;parentPid=$p.ParentProcessId;session=$p.SessionId;exe=$p.ExecutablePath;commandLine=$p.CommandLine}}}
@{utc=[DateTimeOffset]::UtcNow.ToString('o');sessions=$sessions;heavyPython=$rows;lock=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim()}|ConvertTo-Json -Depth 6
