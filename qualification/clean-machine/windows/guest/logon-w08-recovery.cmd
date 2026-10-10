@echo off
rem logon-w08-recovery.cmd - staged as harness\logon.cmd by run-w08-recovery.ps1 (LogonCommand takes no arguments). Paths match clean-machine.wsb.tmpl.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\WDAGUtilityAccount\Desktop\clean-machine\harness\w08-recovery-guest.ps1"
