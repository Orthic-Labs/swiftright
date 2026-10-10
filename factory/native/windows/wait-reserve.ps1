# One silent persistent wait. No GUI/task creation, foreign release, or deletion.
param([Parameter(Mandatory=$true)][string]$RunRoot,[int]$WaitHours=12,[int]$LeaseMinutes=120)
$ErrorActionPreference='Stop'
$factory='D:\Claude\swiftright\factory\native\windows\'
$run=[IO.Path]::GetFullPath($RunRoot)
if(-not $run.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $run)){throw 'Fresh owned factory root required'}
if($WaitHours -lt 1 -or $WaitHours -gt 24 -or $LeaseMinutes -lt 1 -or $LeaseMinutes -gt 180){throw 'Invalid bounded deadline'}
New-Item -ItemType Directory -Path $run|Out-Null
$lock='D:\Claude\desktop.lock';$owner='alchemist-f7-persistent-'+[Guid]::NewGuid().ToString('N')
$events=[Collections.Generic.List[object]]::new();$acquired=$false;$released=$false;$status='waiting';$errorText=''
function Change-Lock([string]$expected,[string]$replacement){
 try{$stream=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false}
 try{
  $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$state=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
  if($state -ne $expected){return $false}
  $data=[Text.Encoding]::UTF8.GetBytes($replacement);$stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true);return $true
 }finally{$stream.Dispose()}
}
[ordered]@{kind='windows-persistent-wait';owner=$owner;pid=$PID;startedAt=[DateTimeOffset]::UtcNow.ToString('o');waitHours=$WaitHours;leaseMinutes=$LeaseMinutes;runRoot=$run;consoleVisible=$false;windowedDispatch=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $run 'wait-start.json')
try{
 $deadline=[DateTime]::UtcNow.AddHours($WaitHours);$last=''
 while([DateTime]::UtcNow -lt $deadline){
  $acquired=Change-Lock 'free' $owner
  if($acquired){break}
  $state=try{(Get-Content -Raw $lock).Trim()}catch{'unreadable'}
  if($state -ne $last){$events.Add([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');state=$state});$last=$state}
  Start-Sleep -Seconds 10
 }
 if(-not $acquired){$status='hold-wait-deadline'}else{
  $status='reserved';$lease=[DateTime]::UtcNow.AddMinutes($LeaseMinutes)
  $ready=[ordered]@{kind='windows-lock-ready';owner=$owner;pid=$PID;acquiredAt=[DateTimeOffset]::UtcNow.ToString('o');leaseDeadline=$lease.ToString('o');runRoot=$run;windowedDispatch=$false}
  $ready|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $run 'lock-ready.json')
  $ready|ConvertTo-Json -Compress
  while([DateTime]::UtcNow -lt $lease){
   if((Get-Content -Raw $lock).Trim() -ne $owner){$status='hold-ownership-lost';break}
   $request=Join-Path $run 'release-request.json'
   if(Test-Path -LiteralPath $request){$r=Get-Content -Raw $request|ConvertFrom-Json;if($r.owner -eq $owner){$status='released-on-owned-request';break}}
   Start-Sleep -Seconds 5
  }
  if($status -eq 'reserved'){$status='released-lease-deadline'}
 }
}catch{$status='hold-wait-error';$errorText=[string]$_}
finally{
 if($acquired){$released=Change-Lock $owner 'free'}
 [ordered]@{kind='windows-persistent-wait-result';owner=$owner;status=$status;lockAcquired=$acquired;lockReleased=$released;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');ownerTransitions=$events;error=$errorText;windowedDispatch=$false;taskCreated=$false;stageModified=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $run 'wait-result.json')
}
