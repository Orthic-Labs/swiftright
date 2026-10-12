# Pure workload receipt parser. Dot-source from envelope & controls.
$script:ReceiptBytesLimit = 2MB
function Read-BoundedReceipt([string]$Path) {
  $item = Get-Item -LiteralPath $Path -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt $script:ReceiptBytesLimit) { throw 'receipt missing, reparse, or exceeds 2MiB' }
  return ([IO.File]::ReadAllText($Path) -replace "`r", '')
}
function Test-ExitIdentity($Match,[string]$ExitName,[string]$RawName,[string]$KernelName,[string]$DotnetName) {
  [uint64]$raw=0;[int64]$kernel=0;[int64]$exit=0;[int64]$dotnet=0
  if(-not [uint64]::TryParse($Match.Groups[$RawName].Value,[ref]$raw) -or -not [int64]::TryParse($Match.Groups[$KernelName].Value,[ref]$kernel) -or -not [int64]::TryParse($Match.Groups[$ExitName].Value,[ref]$exit) -or -not [int64]::TryParse($Match.Groups[$DotnetName].Value,[ref]$dotnet)){return $false}
  if($raw -gt [uint64]4294967295){return $false}
  [int64]$expected=if($raw -ge [uint64]2147483648){[int64]$raw-[int64]4294967296}else{[int64]$raw}
  return $raw -ne [uint64]259 -and $kernel -eq $expected -and $exit -eq $kernel -and $dotnet -eq $exit
}
function Parse-WorkloadReceipt {
  param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,20)][int]$Runs,[switch]$NoResources)
  $text = Read-BoundedReceipt $Path
  $runMatches = @([regex]::Matches($text,'(?m)^=== RUN ([A-Za-z0-9._-]+) start='))
  $runIds = @($runMatches | ForEach-Object { $_.Groups[1].Value })
  $runIdsUnique = @($runIds | Sort-Object -Unique)
  $workerMatches = @([regex]::Matches($text,'(?m)^pid_exit run=(?<run>[A-Za-z0-9._-]+) pid=(?<pid>[0-9]+) handle=(?<handle>[1-9][0-9]*) qpc_end=(?<qpc>[0-9]+) exit=(?<exit>-?[0-9]+) kernel_terminal=(?<terminal>[01]) kernel_exit_raw=(?<raw>[0-9]+) kernel_exit=(?<kernel>-?[0-9]+) dotnet_exit=(?<dotnet>-?[0-9]+)$'))
  $samplerMatches = @([regex]::Matches($text,'(?m)^resources run=(?<run>[A-Za-z0-9._-]+) rows=[0-9]+ sampler_exit=(?<exit>-?[0-9]+) sampler_kernel_terminal=(?<terminal>[01]) sampler_kernel_exit_raw=(?<raw>[0-9]+) sampler_kernel_exit=(?<kernel>-?[0-9]+) sampler_dotnet_exit=(?<dotnet>-?[0-9]+) handle=(?<handle>[1-9][0-9]*) stdout_drained=(?<stdout>[01]) stderr_drained=(?<stderr>[01]) csv=.*$'))
  $drainMatches = @([regex]::Matches($text,'(?m)^stream_drains run=(?<run>[A-Za-z0-9._-]+) worker_stdout=(?<workerOut>[01]) worker_stderr=(?<workerErr>[01]) sampler_stdout=(?<samplerOut>[01]) sampler_stderr=(?<samplerErr>[01])$'))
  $workerIdsUnique=@($workerMatches|ForEach-Object{$_.Groups['run'].Value}|Sort-Object -Unique);$samplerIdsUnique=@($samplerMatches|ForEach-Object{$_.Groups['run'].Value}|Sort-Object -Unique);$drainIdsUnique=@($drainMatches|ForEach-Object{$_.Groups['run'].Value}|Sort-Object -Unique)
  $finished = [regex]::Match($text,'(?m)^finished=.* runs_valid=(?<valid>[0-9]+) of (?<total>[0-9]+)$')
  $final = [regex]::Match($text,'(?m)^worker_terminal=(?<worker>[01]) sampler_terminal=(?<sampler>[01]) task_quiescent=(?<quiet>[01])$')
  $workerTerminal = $true; $workerExitZero = $true; $workerExitIdentity = $true; $workerHandles = $true
  foreach ($m in $workerMatches) { if ($m.Groups['terminal'].Value -ne '1' -or $m.Groups['raw'].Value -eq '259') { $workerTerminal = $false }; if (-not (Test-ExitIdentity $m 'exit' 'raw' 'kernel' 'dotnet')) { $workerExitIdentity = $false }; if ($m.Groups['exit'].Value -ne '0' -or $m.Groups['dotnet'].Value -ne '0' -or $m.Groups['kernel'].Value -ne '0') { $workerExitZero = $false }; if ($m.Groups['handle'].Value -eq '0') { $workerHandles = $false } }
  $samplerTerminal = $NoResources; $samplerExitZero = $NoResources; $samplerExitIdentity = $NoResources; $samplerHandles = $NoResources; $samplerDrained = $NoResources
  if (-not $NoResources) { $samplerTerminal = $true; $samplerExitZero = $true; $samplerExitIdentity = $true; $samplerHandles = $true; $samplerDrained = $true; foreach ($m in $samplerMatches) { if ($m.Groups['terminal'].Value -ne '1' -or $m.Groups['raw'].Value -eq '259') { $samplerTerminal = $false }; if (-not (Test-ExitIdentity $m 'exit' 'raw' 'kernel' 'dotnet')) { $samplerExitIdentity = $false }; if ($m.Groups['exit'].Value -ne '0' -or $m.Groups['dotnet'].Value -ne '0' -or $m.Groups['kernel'].Value -ne '0') { $samplerExitZero = $false }; if ($m.Groups['handle'].Value -eq '0') { $samplerHandles = $false }; if ($m.Groups['stdout'].Value -ne '1' -or $m.Groups['stderr'].Value -ne '1') { $samplerDrained = $false } } }
  $streamsDrained = $true
  foreach ($m in $drainMatches) { if ($m.Groups['workerOut'].Value -ne '1' -or $m.Groups['workerErr'].Value -ne '1' -or $m.Groups['samplerOut'].Value -ne '1' -or $m.Groups['samplerErr'].Value -ne '1') { $streamsDrained = $false } }
  if ($drainMatches.Count -ne $Runs -or $drainIdsUnique.Count -ne $Runs -or @(Compare-Object $runIdsUnique $drainIdsUnique).Count -ne 0) { $streamsDrained = $false }
  $workerRows = $workerMatches.Count -eq $Runs -and $workerIdsUnique.Count -eq $Runs -and (@(Compare-Object $runIdsUnique $workerIdsUnique).Count -eq 0); $samplerRows = $NoResources -or ($samplerMatches.Count -eq $Runs -and $samplerIdsUnique.Count -eq $Runs -and (@(Compare-Object $runIdsUnique $samplerIdsUnique).Count -eq 0))
  $finishedProof = $finished.Success -and [int]$finished.Groups['valid'].Value -eq $Runs -and [int]$finished.Groups['total'].Value -eq $Runs
  $taskQuiescent = $final.Success -and $final.Groups['quiet'].Value -eq '1'
  $qualificationPass = $runMatches.Count -eq $Runs -and $runIdsUnique.Count -eq $Runs -and $workerRows -and $samplerRows -and $finishedProof -and $workerTerminal -and $samplerTerminal -and $workerExitIdentity -and $samplerExitIdentity -and $workerExitZero -and $samplerExitZero -and $workerHandles -and $samplerHandles -and $samplerDrained -and $streamsDrained -and $taskQuiescent
  $ownershipTerminal = $runMatches.Count -eq $Runs -and $runIdsUnique.Count -eq $Runs -and $workerRows -and $samplerRows -and $workerTerminal -and $samplerTerminal -and $workerExitIdentity -and $samplerExitIdentity -and $workerHandles -and $samplerHandles -and $samplerDrained -and $streamsDrained -and $taskQuiescent
  return [ordered]@{ path=$Path; runCount=$runMatches.Count; uniqueRunCount=$runIdsUnique.Count; workerRows=$workerMatches.Count; samplerRows=$samplerMatches.Count; streamDrainRows=$drainMatches.Count; finished=$finishedProof; allRunsValid=$finishedProof; workerTerminal=$workerTerminal; samplerTerminal=$samplerTerminal; workerExitIdentity=$workerExitIdentity; samplerExitIdentity=$samplerExitIdentity; workerExitZero=$workerExitZero; samplerExitZero=$samplerExitZero; workerHandles=$workerHandles; samplerHandles=$samplerHandles; samplerStreamsDrained=$samplerDrained; streamsDrained=$streamsDrained; taskQuiescent=$taskQuiescent; ownershipTerminal=$ownershipTerminal; qualificationPass=$qualificationPass }
}
