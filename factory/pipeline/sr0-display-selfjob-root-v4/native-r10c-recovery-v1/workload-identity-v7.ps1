function Resolve-WorkloadIdentityV7Core {
  param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,20)][int]$ExpectedRuns,[int]$WrapperPid)
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt 2097152){throw 'workload identity receipt missing, reparse, or exceeds 2MiB'}
  $text=[IO.File]::ReadAllText($item.FullName)
  $workers=@([regex]::Matches($text,'(?m)^worker run=(?<run>[A-Za-z0-9._-]+) pid=(?<pid>[1-9][0-9]*) parent_pid=(?<parent>[1-9][0-9]*) full_path=(?<path>.+)$'))
  if($workers.Count-ne $ExpectedRuns){throw "workload identity row count mismatch: $($workers.Count) vs $ExpectedRuns"}
  $ids=@($workers|ForEach-Object{$_.Groups['run'].Value}|Sort-Object -Unique);if($ids.Count-ne $ExpectedRuns){throw 'workload identity run ids are not unique'}
  $workerPid=[int64]$workers[0].Groups['pid'].Value;$parentPid=[int64]$workers[0].Groups['parent'].Value
  if($WrapperPid -gt 0 -and $parentPid -ne [int64]$WrapperPid){throw "workload wrapper parent mismatch: $parentPid vs $WrapperPid"}
  foreach($m in $workers){if([int64]$m.Groups['pid'].Value -ne $workerPid){throw 'multiple workload PIDs in one strict run'};if([int64]$m.Groups['parent'].Value -ne $parentPid){throw 'multiple workload wrapper parents in one strict run'}}
  $exits=@([regex]::Matches($text,'(?m)^pid_exit run=(?<run>[A-Za-z0-9._-]+) pid=(?<pid>[1-9][0-9]*) handle=(?<handle>[1-9][0-9]*) qpc_end=(?<qpc>[0-9]+) exit=(?<exit>-?[0-9]+) kernel_terminal=(?<terminal>[01]) kernel_exit_raw=(?<raw>[0-9]+) kernel_exit=(?<kernel>-?[0-9]+) dotnet_exit=(?<dotnet>-?[0-9]+)$'))
  if($exits.Count-ne $ExpectedRuns){throw "workload exit row count mismatch: $($exits.Count) vs $ExpectedRuns"}
  $exitIds=@($exits|ForEach-Object{$_.Groups['run'].Value}|Sort-Object -Unique);if($exitIds.Count-ne $ExpectedRuns){throw 'workload exit run ids are not unique'};foreach($id in $ids){if($exitIds -notcontains $id){throw 'workload worker/exit run identity mismatch'}}
  foreach($m in $exits){[uint64]$raw=0;if(-not [uint64]::TryParse($m.Groups['raw'].Value,[ref]$raw)-or $raw -gt [uint64]4294967295){throw 'workload raw exit invalid'};[int64]$signed=if($raw -ge [uint64]2147483648){[int64]$raw-[int64]4294967296}else{[int64]$raw};if([int64]$m.Groups['pid'].Value-ne $workerPid -or $m.Groups['terminal'].Value-ne '1' -or $raw-eq [uint64]259 -or $signed-ne [int64]$m.Groups['kernel'].Value -or $signed-ne [int64]$m.Groups['exit'].Value -or $signed-ne [int64]$m.Groups['dotnet'].Value){throw 'workload exit identity mismatch'}}
  $drains=@([regex]::Matches($text,'(?m)^stream_drains run=(?<run>[A-Za-z0-9._-]+) worker_stdout=(?<out>[01]) worker_stderr=(?<err>[01]) sampler_stdout=(?<sout>[01]) sampler_stderr=(?<serr>[01])$'))
  return [ordered]@{workerPid=$workerPid;parentPid=$parentPid;workerPath=$workers[0].Groups['path'].Value;workerExit=[int64]$exits[0].Groups['exit'].Value;workerExitIdentity=$true;streamDrainRows=$drains.Count;streamsDrained=($drains.Count-eq $ExpectedRuns-and @($drains|Where-Object{$_.Groups['out'].Value-ne '1'-or $_.Groups['err'].Value-ne '1'-or $_.Groups['sout'].Value-ne '1'-or $_.Groups['serr'].Value-ne '1'}).Count-eq 0)}
}
function Resolve-WorkloadIdentityV7 {
  param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,20)][int]$ExpectedRuns,[int]$WrapperPid,[ValidateRange(1,60)][int]$CompletionGraceSeconds=30)
  $deadline=[DateTime]::UtcNow.AddSeconds($CompletionGraceSeconds);$last=$null
  while($true){
    try{return Resolve-WorkloadIdentityV7Core -Path $Path -ExpectedRuns $ExpectedRuns -WrapperPid $WrapperPid}
    catch{
      $last=$_.Exception
      $retryable=$last.Message -match '^workload (identity|exit) row count mismatch:'
      if(-not $retryable -or [DateTime]::UtcNow -ge $deadline){throw}
      Start-Sleep -Milliseconds 200
    }
  }
}
