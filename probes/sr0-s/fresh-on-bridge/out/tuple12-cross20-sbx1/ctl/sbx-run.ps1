# Runs inside Windows Sandbox at logon: re-records the listed cross tags with the foreground-checking recorder.
$ErrorActionPreference = 'Continue'
$ctl = 'C:\sb\ctl'
"start $(Get-Date -Format o) session=$((Get-Process -Id $PID).SessionId)" | Out-File -Append "$ctl\sbx.log"
$mp = [Environment]::GetEnvironmentVariable('Path', 'Machine')
[Environment]::SetEnvironmentVariable('Path', "C:\sb\vc;$mp", 'Machine')
foreach ($line in Get-Content "$ctl\list.txt") {
  $c, $i = $line.Split(' ')
  $tag = "$c-s12$i"
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$ctl\run-cross.ps1" -Config $c -Tag $tag -Base 'C:\sb\base' -Recorder 'C:\sb\rec\UIARecorder.exe' -Bin 'C:\sb\bin' -OutDir 'C:\sb\out' 2>&1 | Out-File -Append "$ctl\sbx.log"
  "$tag rc=$LASTEXITCODE $(Get-Date -Format o)" | Out-File -Append "$ctl\sbx.log"
}
"done $(Get-Date -Format o)" | Out-File -Append "$ctl\sbx.log"
Set-Content -Path "$ctl\DONE" -Value 'done'
