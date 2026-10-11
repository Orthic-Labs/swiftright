$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Remaining4-smoke-r5-r2'
$rows=@()
foreach($dir in @(Get-ChildItem -LiteralPath $root -Directory)){
 foreach($f in @(Get-ChildItem -LiteralPath (Join-Path $dir.FullName 'receipts') -Filter '*.json' -File -ErrorAction SilentlyContinue)){
  if($f.Length -gt 1048576){throw 'Receipt size budget'}
  $r=[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json
  $rows+=@{path=$f.FullName;status=$r.status;fixture=$r.fixture;variant=$r.variant;failure=$r.failure;semantic=$r.semantic;cleanup=$r.cleanup}
 }
}
[ordered]@{kind='root-remaining4-smoke-status-v1';lock=[IO.File]::ReadAllText('D:\Claude\desktop.lock').Trim();receipts=$rows;processes=@(Get-CimInstance Win32_Process -Filter "Name='FreshOnBridge.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath);at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8
