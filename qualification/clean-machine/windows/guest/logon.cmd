@echo off
rem logon.cmd - LogonCommand target for clean-machine.wsb. Starts the guest harness with a fixed command line
rem (LogonCommand takes no arguments). Paths match the SandboxFolder entries in clean-machine.wsb.tmpl.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\WDAGUtilityAccount\Desktop\clean-machine\harness\sandbox-run.ps1"
