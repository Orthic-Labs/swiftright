@echo off
rem logon.cmd - LogonCommand of the long-lived worker Sandbox (no arguments allowed). Leaves a breadcrumb, then starts the guest worker loop in a minimised window.
echo logon.cmd ran %DATE% %TIME% > C:\sbq\state\logon-ran.txt
start "swiftright-worker" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\sbq\guest\guest-worker.ps1
