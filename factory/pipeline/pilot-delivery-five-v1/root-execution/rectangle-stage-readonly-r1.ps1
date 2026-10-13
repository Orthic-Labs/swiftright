$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$PlanPath=Join-Path $Root 'package\plan-final-v4.json'
$Plan=Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json
$Rows=@();$Bytes=0
foreach($R in @($Plan.sourceBindings)) {
 $P=Join-Path (Join-Path $Root 'package') $R.path
 $I=Get-Item -LiteralPath $P -Force
 if($I.PSIsContainer -or $I.Length -gt 67108864 -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular source required'}
 $Bytes+=$I.Length;if($Bytes -gt 268435456){throw 'source byte budget'}
 $H=(Get-FileHash -LiteralPath $P -Algorithm SHA256).Hash.ToLowerInvariant()
 $Rows+=@{path=$R.path;bytes=$I.Length;sha256=$H;matches=($H -ceq $R.sha256.Replace('sha256:',''))}
}
$Processes=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '^(swift|swiftc|swift-build|clang|FactoryProbe|cargo)(\.exe)?$'}|Select-Object ProcessId,Name,CommandLine)
[ordered]@{kind='factory-rectangle-stage-readonly-v1';at=[DateTimeOffset]::UtcNow.ToString('o');nativeActions=0;desktopActions=0;lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();processes=$Processes;planSha256=(Get-FileHash -LiteralPath $PlanPath).Hash.ToLowerInvariant();sourceBindings=$Rows;phaseReceipts=@(Get-ChildItem -LiteralPath $Root -Directory|Where-Object {$_.Name -match '^(prebuild|final)-r[0-9]+$'}|ForEach-Object {$_.Name});helperSha256=(Get-FileHash -LiteralPath (Join-Path $Root 'Sr0OwnedJobProcess.cs')).Hash.ToLowerInvariant();buildScriptSha256=(Get-FileHash -LiteralPath (Join-Path $Root 'build-owned-v4.ps1')).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8
