$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Full-16-20-r4';$rows=@();foreach($f in Get-ChildItem -LiteralPath $root -Filter matrix-run.json -File -Recurse){$j=Get-Content -Raw -LiteralPath $f.FullName|ConvertFrom-Json;$rows+=$j}
$last=$rows|Sort-Object index|Select-Object -Last 1
@{kind='root-full16-readonly-progress-v1';completedRuns=$rows.Count;expectedRuns=320;last=$last;lockState=[IO.File]::ReadAllText('D:\Claude\desktop.lock');at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5
