$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11\r16';$control=Join-Path $ns 'coordinator-r1'
function R([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB){throw 'Proof bound'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
$co=R (Join-Path $control 'coordinator.json');$task=R (Join-Path $control 'task-result.json')
$proofs=@();$dirs=@(Get-ChildItem -LiteralPath $co.runRoot -Directory);if($dirs.Count -gt 20){throw 'Native directory bound'}
foreach($d in $dirs){$fs=@(Get-ChildItem -LiteralPath $d.FullName -File);if($fs.Count -gt 128){throw 'Proof count bound'};foreach($f in $fs){if($f.Extension -eq '.json'){$proofs+=@{path=$f.FullName;sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();data=(R $f.FullName)}}}}
$live=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -like '*swiftright*.exe' -or $_.CommandLine -like '*windows-replay-r11*r16*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath);if($live.Count -gt 32){throw 'Live bound'}
[ordered]@{task=$task;coordinator=$co;proofs=$proofs;live=$live;lockState=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim()}|ConvertTo-Json -Depth 18
