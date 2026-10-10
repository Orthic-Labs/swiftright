# PHASE 2 END: moves the stage dir to the Recycle Bin (permanent deletes are blocked). Run a COPY of this file from %TEMP%, not from inside
# the stage dir:  win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-geomodal\...\recycle-stage.ps1'  (copy it out first)
param([string]$Path = 'D:\Claude\sr0-geomodal')
$ErrorActionPreference = 'Stop'
if ($Path -ne 'D:\Claude\sr0-geomodal') { throw 'refusing: only the geomodal stage dir' }
if ((Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SR0GM-*' })) { throw 'a SR0GM scheduled task still exists' }
if (-not (Test-Path $Path)) { 'stage dir already gone'; exit 0 }
Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) } catch { } }
Add-Type -AssemblyName Microsoft.VisualBasic
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
"moved to Recycle Bin: $Path exists_after=$(Test-Path $Path)"
