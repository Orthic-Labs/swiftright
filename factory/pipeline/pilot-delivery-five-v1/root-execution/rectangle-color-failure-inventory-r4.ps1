$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r4'
$Files=@();$Bytes=0
foreach($Rel in @('control-count1-r1','native\count1-r1')){
 $Dir=Join-Path $Root $Rel
 if(Test-Path -LiteralPath $Dir){foreach($F in @(Get-ChildItem -LiteralPath $Dir -File -Recurse)){
  if($F.Length -gt 16777216 -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular failure evidence required'}
  $Bytes+=$F.Length;if($Files.Count -ge 128 -or $Bytes -gt 33554432){throw 'failure archive cap exceeded'}
  $Files+=@{path=$F.FullName.Substring($Root.Length+1).Replace('\','/');bytes=$F.Length;sha256=(Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant()}
 }}
}
$Procs=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -like '*\FactoryProbe.exe' -or $_.CommandLine -like '*captures\color-r4*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine)
[ordered]@{kind='factory-rectangle-failure-inventory-v1';root=$Root;lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();files=$Files;bytes=$Bytes;processes=$Procs;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 8
