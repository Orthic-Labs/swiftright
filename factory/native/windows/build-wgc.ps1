# Compile only: factory-owned explicit HWND capture helper; no desktop/capture API call.
param([Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$lane='D:\Claude\swiftright\factory\native\windows\'
$root=[IO.Path]::GetFullPath($RunRoot)
if(-not $root.StartsWith($lane,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path $root)){throw 'Fresh owned build archive required'}
New-Item -ItemType Directory -Path $root|Out-Null
$source=Join-Path $root 'wgc-owned.cpp';Copy-Item (Join-Path $PSScriptRoot 'wgc-owned.cpp') $source
$vcvars='C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat'
if(-not (Test-Path $vcvars)){throw 'Recorded VS toolchain missing'}
$cmd=Join-Path $root 'build.cmd'
@('@echo off',('call "'+$vcvars+'" >nul'),('cl /nologo /std:c++17 /EHsc /DUNICODE /D_UNICODE "'+$source+'" /Fo"'+(Join-Path $root 'wgc-owned.obj')+'" /Fe"'+(Join-Path $root 'FactoryOwnedWGC.exe')+'" /link /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup d3d11.lib dxgi.lib windowsapp.lib windowscodecs.lib ole32.lib user32.lib'))|Set-Content -Encoding ASCII $cmd
$info=[Diagnostics.ProcessStartInfo]::new('cmd.exe');$info.Arguments='/d /c ""'+$cmd+'""';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.WorkingDirectory=$root
$p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$timeout=$false
try{if(-not $p.WaitForExit(120000)){$timeout=$true;throw 'Owned C++ compiler deadline'}}
finally{
 if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started -and $owned.Path -eq $p.MainModule.FileName){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null}
 if($out.Wait(5000)){[IO.File]::WriteAllText((Join-Path $root 'stdout.txt'),$out.GetAwaiter().GetResult())};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $root 'stderr.txt'),$err.GetAwaiter().GetResult())}
 $receipt=[ordered]@{kind='windows-owned-WGC-helper-compile';sourceHash=(Get-FileHash $source).Hash.ToLowerInvariant();exitCode=$p.ExitCode;timedOut=$timeout;nativeWindowOpened=$false;captureInvoked=$false;createNoWindow=$true;finishedAt=[DateTime]::UtcNow.ToString('o')}
 $exe=Join-Path $root 'FactoryOwnedWGC.exe';if(Test-Path $exe){$receipt.exeHash=(Get-FileHash $exe).Hash.ToLowerInvariant()}
 $receipt|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $root 'build-receipt.json')
}
