$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$rows=@();$quiet=0;$previous=@{};$deadline=[DateTime]::UtcNow.AddMinutes(10)
do{
 $all=@(Get-CimInstance Win32_Process);$ids=@(45640);$changed=$true
 while($changed){$changed=$false;foreach($p in $all){if($p.ParentProcessId -in $ids -and $p.ProcessId -notin $ids){$ids+=[int]$p.ProcessId;$changed=$true}}}
 $tree=@();$busy=$false;$now=@{}
 foreach($p in $all|Where-Object {$_.ProcessId -in $ids}){
  $cpu=$null;$delta=$null
  try{$cpu=(Get-Process -Id $p.ProcessId -ErrorAction Stop).TotalProcessorTime.TotalSeconds}catch{}
  $key=[string]$p.ProcessId+'|'+[string]$p.CreationDate
  if($null -ne $cpu){$now[$key]=$cpu;if($previous.ContainsKey($key)){$delta=$cpu-$previous[$key];if($delta -gt 0.25){$busy=$true}}elseif($previous.Count -gt 0){$busy=$true}}
  if($p.Name -match '^(rustc|cl|clang|clang-cl|link|lld-link|swift-frontend|build_script_build)(.exe)?$'){$busy=$true}
  $tree+=[ordered]@{pid=[int]$p.ProcessId;parentPid=[int]$p.ParentProcessId;name=$p.Name;creationDate=[string]$p.CreationDate;executablePath=$p.ExecutablePath;commandLine=$p.CommandLine;cpuSeconds=$cpu;cpuDeltaSeconds=$delta}
 }
 $compilers=@($all|Where-Object {$_.Name -match '^(rustc|cl|clang|clang-cl|link|lld-link|swift|swiftc|swift-frontend|swift-test)(.exe)?$'}|Select-Object ProcessId,ParentProcessId,Name,CreationDate,ExecutablePath,CommandLine)
 if($compilers.Count -gt 0){$busy=$true}
 if($previous.Count -eq 0){$busy=$true}
 if($busy){$quiet=0}else{$quiet++}
 $rows+=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');cargoRootPid=45640;cargoTree=$tree;allCompilers=$compilers;processorLoad=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage);busy=$busy;consecutiveQuietSamples=$quiet}
 $previous=$now
 if($quiet -ge 5){break};Start-Sleep -Seconds 2
}while([DateTime]::UtcNow -lt $deadline)
[ordered]@{schema='copycost-pre-execution-quiescence-v1';quiescent=($quiet-ge5);policy='five2s samples; no compiler processes; cargo descendant CPU delta <=0.25s';cargoPid=45640;rows=$rows;finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20
if($quiet -lt 5){exit 2}
