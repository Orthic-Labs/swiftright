param([Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$ObserverRoot)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$path=Join-Path $ObserverRoot 'samples.jsonl';$stop=Join-Path $ObserverRoot 'stop-observer';$deadline=[DateTime]::UtcNow.AddMinutes(32);$previous=@{}
$writer=[IO.StreamWriter]::new($path,$false,[Text.UTF8Encoding]::new($false))
try{
 while(-not(Test-Path -LiteralPath $stop) -and [DateTime]::UtcNow-lt$deadline){
  $all=@(Get-CimInstance Win32_Process);$cargoIds=@(45640);$changed=$true
  while($changed){$changed=$false;foreach($p in $all){if($p.ParentProcessId-in$cargoIds -and $p.ProcessId-notin$cargoIds){$cargoIds+=[int]$p.ProcessId;$changed=$true}}}
  $selected=@($all|Where-Object {$_.ProcessId-in$cargoIds -or $_.Name-match '^(cargo|rustc|cl|clang|clang-cl|link|lld-link|swift|swiftc|swift-frontend|swift-test|FactoryProbe)(\.exe)?$'})
  $rows=@();$now=@{}
  foreach($p in $selected){
   $cpu=$null;$delta=$null;try{$cpu=(Get-Process -Id $p.ProcessId -ErrorAction Stop).TotalProcessorTime.TotalSeconds}catch{}
   $key=[string]$p.ProcessId+'|'+[string]$p.CreationDate;if($null-ne$cpu){$now[$key]=$cpu;if($previous.ContainsKey($key)){$delta=$cpu-$previous[$key]}}
   $rows+=[ordered]@{pid=[int]$p.ProcessId;parentPid=[int]$p.ParentProcessId;name=$p.Name;creationDate=[string]$p.CreationDate;executablePath=$p.ExecutablePath;commandLine=$p.CommandLine;cpuSeconds=$cpu;cpuDeltaSeconds=$delta;cargoDescendant=($p.ProcessId-in$cargoIds);ownedPair=([string]$p.CommandLine).Contains($RunRoot)}
  }
  $sample=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');processorLoad=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage);processes=$rows}
  $writer.WriteLine(($sample|ConvertTo-Json -Depth 12 -Compress));$writer.Flush();$previous=$now;Start-Sleep -Seconds 5
 }
}finally{$writer.Dispose()}
