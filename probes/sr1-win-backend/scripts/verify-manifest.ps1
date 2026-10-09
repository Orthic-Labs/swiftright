# Dumps the embedded application manifest of SR1Gallery.exe with mt.exe (Windows SDK). Read-only; never launches the exe.
param([string]$Base = 'D:\Claude\sr1-gallery06')
$ErrorActionPreference = 'Stop'
$bin = (Get-Content -Raw "$Base\bin-path.txt").Trim()
$exe = Join-Path $bin 'SR1Gallery.exe'
$mt = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter mt.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1
if (-not $mt) { throw 'mt.exe not found under the Windows 10 kits' }
$out = "$Base\sr1-manifest-dump.xml"
& $mt.FullName "-inputresource:$exe;#1" "-out:$out" | Out-Null
"mt_exit=$LASTEXITCODE mt=$($mt.FullName)"
Get-Content -Raw $out
