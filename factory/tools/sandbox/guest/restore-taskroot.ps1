# Restores the Task Scheduler root folder's DACL saved by the W08 method tier2-sched-blocked (#47). That method denies FW to Interactive users on the root folder,
# which also stops an interactive administrator from changing the folder's security again, so this script runs as LocalSystem (a one-shot service created by
# job-w08.ps1 Reset-W08State). Writes the resulting DACL to C:\Windows\Temp\restore-taskroot.out.
# Paths are under C:\Windows\Temp: the mapped C:\sbq folder is not readable by LocalSystem in the Sandbox (measured 22 Oct 2026).
$saved = 'C:\Windows\Temp\taskroot-dacl.txt'
$out = 'C:\Windows\Temp\restore-taskroot.out'
try {
    $s = New-Object -ComObject Schedule.Service; $s.Connect()
    $root = $s.GetFolder('\')
    $root.SetSecurityDescriptor([IO.File]::ReadAllText($saved), 0)
    [IO.File]::WriteAllText($out, $root.GetSecurityDescriptor(4))
} catch {
    [IO.File]::WriteAllText($out, 'ERROR ' + $_.Exception.Message)
}
