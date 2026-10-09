# Verifies the manifest embedded in WorkloadWin.exe with mt.exe: the ComCtl v6 dependency must be present.
param([string]$Base = 'D:\Claude\sr0b-workload')
$ErrorActionPreference = 'Stop'
$bin = (Get-Content -Raw "$Base\build.json" | ConvertFrom-Json).exe
$mt = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter mt.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\mt\.exe$' } | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $mt) { throw 'mt.exe not found under Windows Kits' }
$out = Join-Path $env:TEMP 'workloadwin-manifest.xml'
& $mt.FullName "-inputresource:$bin;#1" "-out:$out" | Out-Null
"mt=$($mt.FullName) exit=$LASTEXITCODE"
"exe=$bin timestamp=$((Get-Item $bin).LastWriteTime.ToString('o'))"
$xml = Get-Content -Raw $out
$dep = [regex]::Match($xml, '<dependency>.*?</dependency>', 'Singleline').Value
"dependency: $(($dep -replace '\s+', ' ').Trim())"
if ($xml -match 'Microsoft\.Windows\.Common-Controls' -and $xml -match 'version="6\.0\.0\.0"') { 'manifest=OK comctl32-v6' } else { 'manifest=MISSING comctl32-v6'; exit 1 }
