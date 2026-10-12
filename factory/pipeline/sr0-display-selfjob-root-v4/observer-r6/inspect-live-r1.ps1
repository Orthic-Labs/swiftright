$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4'
$rows=@()
foreach($rel in @('observer-r6.json','one-run-r4\start-receipt.json','one-run-r4\collector-receipt.json','one-run-r4\launcher-receipt.json','one-run-r4\coordinator-verdict.json')){
 $p=Join-Path $root $rel
 if(Test-Path -LiteralPath $p){$f=Get-Item -LiteralPath $p;if($f.Length -gt 2MB -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded live receipt required'};$j=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json;$rows+=@{name=$rel;bytes=$f.Length;modified=$f.LastWriteTimeUtc.ToString('o');status=$j.status;error=$j.error;workerStarted=$j.workerStarted;qualification=$j.qualification;result=$j.result;collectorExitCode=$j.collectorExitCode}}
 else{$rows+=@{name=$rel;exists=$false}}
}
$f=Get-Item -LiteralPath 'D:\Claude\desktop.lock';if($f.Length -gt 4096){throw 'lock bound'}
@{kind='sr0-root-live-inspection-v1';receipts=$rows;desktopLock=(Get-Content -Raw -LiteralPath $f.FullName).Trim();nativeActions=0}|ConvertTo-Json -Depth 8
