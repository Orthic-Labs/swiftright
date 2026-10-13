# Take desktop.lock, run capture.ps1 in the interactive session via a hidden scheduled task, ALWAYS write 'free' at the end.
param([Parameter(Mandatory)][string]$Exe,[Parameter(Mandatory)][string]$Out,[int]$Runs=1,[int]$WaitMinutes=30,[switch]$Shared,[string]$Case='case')
$ErrorActionPreference='Stop'
$lock='D:\Claude\desktop.lock';$owner='swiftright-87';$acquired=$false;$task='SwiftRightPair-'+[Guid]::NewGuid().ToString('N')
function CAS($expected,$new){try{$s=[IO.File]::Open($lock,'Open','ReadWrite','None')}catch [IO.IOException]{return $false}
 try{$r=[IO.StreamReader]::new($s,[Text.Encoding]::UTF8,$true,1024,$true);$old=$r.ReadToEnd().Trim();$r.Dispose();if($old -cne $expected){return $false}
  $b=[Text.Encoding]::UTF8.GetBytes($new);$s.Position=0;$s.SetLength(0);$s.Write($b,0,$b.Length);$s.Flush($true);return $true}finally{$s.Dispose()}}
New-Item -ItemType Directory -Force -Path $Out|Out-Null
try{
 $until=[DateTime]::UtcNow.AddMinutes($WaitMinutes)
 if($Shared){$marker='D:\Claude\desktop.shared.'+$Case;[IO.File]::WriteAllText($marker,'swiftright-87 shared PrintWindow capture, no input, no activation '+[DateTime]::UtcNow.ToString('o'))}
 else{while(-not($acquired=CAS 'free' $owner)){if([DateTime]::UtcNow -gt $until){throw "desktop busy for $WaitMinutes min"};Start-Sleep -Seconds 15}}
 $cap=Join-Path $PSScriptRoot 'capture.ps1';$vbs=Join-Path $Out 'task.vbs'
 $cmd='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$cap+'" -Exe "'+$Exe+'" -Out "'+$Out+'" -Runs '+$Runs+' -Owner '+$owner+$(if($Shared){' -Shared'}else{''})
 [IO.File]::WriteAllText($vbs,'Set sh = CreateObject("WScript.Shell")'+"`r`n"+'rc = sh.Run("'+$cmd.Replace('"','""')+'", 0, True)'+"`r`n"+'WScript.Quit rc',[Text.Encoding]::ASCII)
 $act=New-ScheduledTaskAction -Execute "$env:windir\System32\wscript.exe" -Argument ('"'+$vbs+'"')
 $pr=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest
 $set=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes ([Math]::Max(5,$Runs*2+3))) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $task -Action $act -Principal $pr -Settings $set|Out-Null
 Start-ScheduledTask -TaskName $task
 $done=Join-Path $Out 'done.json';$deadline=[DateTime]::UtcNow.AddSeconds($Runs*60+120)
 while(-not(Test-Path $done)){if([DateTime]::UtcNow -gt $deadline){throw 'capture task timeout'};Start-Sleep -Milliseconds 500}
}catch{$_|Out-String|Set-Content (Join-Path $Out 'session-error.txt');Write-Error $_;$code=1}
finally{
 try{Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue}catch{}
 Get-Process FactoryProbe -ErrorAction SilentlyContinue|Where-Object{$_.Path -eq $Exe}|Stop-Process -Force -ErrorAction SilentlyContinue
 if($acquired){[IO.File]::WriteAllText($lock,'free')}
 if($Shared -and (Test-Path $marker)){New-Item -ItemType Directory -Force 'D:\Claude\swiftright\.work'|Out-Null;Move-Item $marker ('D:\Claude\swiftright\.work\desktop.shared.'+$Case+'.'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')) -Force}
}
if($code){exit $code}
