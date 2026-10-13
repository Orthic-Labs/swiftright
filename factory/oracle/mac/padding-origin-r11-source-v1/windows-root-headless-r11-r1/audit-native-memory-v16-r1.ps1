$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11\r16';$control=Join-Path $ns 'coordinator-r1'
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Proof bound'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
$co=Read-BoundedJson (Join-Path $control 'coordinator.json');$task=Read-BoundedJson (Join-Path $control 'task-result.json')
if(-not $co.lockReleased -or -not $co.wholeBatchExitConfirmed -or -not $co.terminalResultConfirmed -or $task.memoryReceipt.activeProcessCount -ne 1){throw 'Failed capture cleanup not proven'}
$proofs=@();$dirs=@(Get-ChildItem -LiteralPath $co.runRoot -Directory)
if($dirs.Count -gt 20){throw 'Native directory bound'}
foreach($d in $dirs){foreach($n in @('observation.json','owned-process-final.json','owned-worker-inventory.json','cleanup.json','process-final.json')){$p=Join-Path $d.FullName $n;if(Test-Path -LiteralPath $p){$proofs+=@{path=$p;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();data=(Read-BoundedJson $p)}}}}
$files=@();foreach($d in $dirs){$files+=@(Get-ChildItem -LiteralPath $d.FullName -File|Select-Object Name,Length)}
$live=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -like '*swiftright*.exe' -or $_.CommandLine -like '*windows-replay-r11*r16*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath)
if($live.Count -gt 32){throw 'Live process bound'}
[ordered]@{kind='root-factory-failed-native-v16-audit-v1';status='failed-native-cleanup-observed';nativeDirectories=$dirs.Count;proofs=$proofs;files=$files;task=$task;coordinator=$co;live=$live;lockState=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim();qualification='hold'}|ConvertTo-Json -Depth 16
