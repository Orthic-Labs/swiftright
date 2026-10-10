# Compile-only or explicitly reviewed synthetic pure-metrics unit; never opens renderer/window.
param([switch]$RunUnit)
$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\viewport-unit-20261011-r2'
$exe=Join-Path $root 'ViewportUnit.exe'
$bindings=@('FactoryViewport.swift','main.swift')|ForEach-Object{[ordered]@{path=$_;hash=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}}
function Child($file,$childArguments,$prefix,$seconds){
 $info=[Diagnostics.ProcessStartInfo]::new($file);$info.Arguments=$childArguments;$info.WorkingDirectory=$root;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 try {if(-not $p.WaitForExit($seconds*1000)){throw 'Owned unit child deadline'}}
 finally {if(-not $p.HasExited){$own=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($own -and $own.Path -eq $file -and $own.StartTime.ToUniversalTime().ToString('o') -ceq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null};if($out.Wait(5000)){[IO.File]::WriteAllText((Join-Path $root ($prefix+'.stdout.txt')),$out.GetAwaiter().GetResult())};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $root ($prefix+'.stderr.txt')),$err.GetAwaiter().GetResult())}}
 return $p.ExitCode
}
if(-not $RunUnit){
 if(Test-Path $exe){throw 'Fresh unit binary required'}
 $compiler=(Get-Command swiftc).Source
 $exit=Child $compiler ('"'+(Join-Path $root 'FactoryViewport.swift')+'" "'+(Join-Path $root 'main.swift')+'" -o "'+$exe+'" -lUser32 -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup') 'compile' 30
 $record=[ordered]@{kind='synthetic-viewport-unit-compile';synthetic=$true;exitCode=$exit;sourceBindings=$bindings;compilerHash=(Get-FileHash $compiler).Hash.ToLowerInvariant();nativeCaseCaptureCount=0}
 if($exit -eq 0){$bytes=[IO.File]::ReadAllBytes($exe);$offset=[BitConverter]::ToInt32($bytes,60);$record.subsystem=[BitConverter]::ToUInt16($bytes,$offset+92);$record.exeHash=(Get-FileHash $exe).Hash.ToLowerInvariant();if($record.subsystem -ne 2){throw 'GUI subsystem required'}}
 $record|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $root 'compile.json');return
}
$record=Get-Content (Join-Path $root 'compile.json') -Raw|ConvertFrom-Json
foreach($b in $record.sourceBindings){if((Get-FileHash (Join-Path $root $b.path)).Hash.ToLowerInvariant() -cne $b.hash){throw 'Unit source drift'}}
if($record.exitCode -ne 0 -or $record.subsystem -ne 2 -or (Get-FileHash $exe).Hash.ToLowerInvariant() -cne $record.exeHash){throw 'Exact owned compiled synthetic unit required'}
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$exit=Child $exe '' 'unit' 5
[ordered]@{kind='synthetic-viewport-unit-result';synthetic=$true;exitCode=$exit;exeHash=$record.exeHash;nativeCaseCaptureCount=0;rendererLoaded=$false;windowOpened=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $root 'unit.json')
