$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Remaining4-smoke-r5-r2';$stage='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5'
$zipPath='D:\Claude\swiftright\.factory-work\transports\startupguard-remaining4-r5-r2.zip'
if(Test-Path -LiteralPath $zipPath){throw 'Fresh fetch archive required'}
$files=@();$total=0
foreach($pair in @(@('runs',$base),@('stage',$stage))){
 foreach($f in Get-ChildItem -LiteralPath $pair[1] -File -Recurse){
  if($f.Length -gt 8MB -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Evidence file bound'}
  $total+=$f.Length;if($total -gt 32MB -or $files.Count -ge 200){throw 'Evidence total bound'}
  $files+=@{path=$pair[0]+'/'+$f.FullName.Substring($pair[1].Length+1).Replace('\','/');recordedPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant()}
 }
}
$owned=@(Get-CimInstance Win32_Process -Filter "Name='FreshOnBridge.exe'"|Where-Object{$_.ExecutablePath -like '*\sr0-r12-typecheck\*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath)
$runningTasks=@(Get-ScheduledTask|Where-Object{$_.State -eq 'Running' -and $_.TaskName -like 'SR0-T12-*'}|Select-Object TaskName,State)
if($owned.Count -or $runningTasks.Count){throw 'Owned test lane not quiescent'}
Add-Type -AssemblyName System.IO.Compression;$s=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew);$arc=New-Object IO.Compression.ZipArchive($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{
 foreach($f in $files){$st=$arc.CreateEntry($f.path).Open();$source=[IO.File]::OpenRead($f.recordedPath);try{$source.CopyTo($st,1048576)}finally{$source.Dispose();$st.Dispose()}}
 $b=[Text.Encoding]::UTF8.GetBytes((@{kind='root-sr0-remaining4-smoke-r5-fetch-v1';files=$files;lockState=[IO.File]::ReadAllText('D:\Claude\desktop.lock');ownedProcesses=$owned;runningTasks=$runningTasks;deleted=$false;observedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10))
 $st=$arc.CreateEntry('manifest.json').Open();try{$st.Write($b,0,$b.Length)}finally{$st.Dispose()}
}finally{$arc.Dispose();$s.Dispose()}
@{zipPath=$zipPath;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant();files=$files.Count;ownedProcesses=$owned.Count;runningTasks=$runningTasks.Count}|ConvertTo-Json
