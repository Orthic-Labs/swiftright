$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-centered\captures\count1-r12'
$Names=@('control-count1-r12\coordinator.json','control-count1-r12\task-result.json','control-count1-r12\task-start.json','control-count1-r12\scheduled-task-receipt.json')
$Rows=@();foreach($N in $Names){$P=Join-Path $Root $N;if(Test-Path -LiteralPath $P){$F=Get-Item -LiteralPath $P;if($F.Length -gt 2097152 -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular file required'};$Rows+=@([ordered]@{path=$N;bytes=$F.Length;sha256=(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant();rawBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($P))})}}
[ordered]@{kind='factory-failed-native-bounded-readback-v1';rows=$Rows;desktopLock=(Get-Content -Raw -LiteralPath 'D:\Claude\desktop.lock').Trim();nativeActions=0}|ConvertTo-Json -Depth 12
