$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r3\matrix-controls-v5';$base='D:\Claude\swiftright\.work\sr0-r12-typecheck\src';$driver='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r3\f3-ready-diagnosis-v1\drive-fixture-noactivate-focus-r6-diagnostic.ps1'
$out='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\F3-vstack-ready-r6-r2'
$worker=Join-Path $stage 'worker-v4.ps1';$co=Join-Path $stage 'coordinator-v4.ps1'
$wh='efa1bc833afa0ab9b04caa8e41f5dd8a685613c488075e91422ef19973dc0079';$ch='3a3a815c'
$manifest=[IO.File]::ReadAllText('D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r3\stage-manifest.json')|ConvertFrom-Json
foreach($r in $manifest.files){$f=Join-Path 'D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r3' ($r.path -replace '/','\');if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $f).Length -ne $r.bytes){throw ('Pinned source drift '+$r.path)}}
$ch=(Get-FileHash -LiteralPath $co).Hash.ToLowerInvariant();if((Get-FileHash -LiteralPath $worker).Hash.ToLowerInvariant() -cne $wh){throw 'Worker drift'}
if((Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant() -cne '0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c'){throw 'Driver drift'}
if(Test-Path -LiteralPath $out){throw 'Fresh smoke root required'};[IO.Directory]::CreateDirectory($out)|Out-Null
$proof=[IO.File]::ReadAllText('D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r3\actual-typecheck-r3.json')|ConvertFrom-Json
if($proof.status -cne 'passed' -or $proof.psFilesParsed -ne 9 -or $proof.csharpHelpersCompiled -ne 6 -or $proof.headlessRuns -ne 2 -or $proof.windowRuns -ne 0 -or $proof.lockActions -ne 0 -or @($proof.kernelControls).Count -ne 2 -or @($proof.kernelControls|Where-Object{-not $_.stillRunningRejected -or -not $_.stdoutDrained -or -not $_.stderrDrained}).Count -ne 0){throw 'Actual v6/r6 headless proof absent'}
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class RootMatrixNativeTerminal { [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms); [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint code); }
'@
function Quote([string]$s){return '"'+$s.Replace('"','\"')+'"'}
$configs=@(,@('F3','vstack-1s'))
$rows=@()
foreach($cfg in $configs){
 $fixture=$cfg[0];$variant=$cfg[1];$label=$fixture+$(if($variant){'-'+$variant}else{''});$dir=Join-Path $out ($label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir)|Out-Null
 $argv=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$co,'-Base',$base,'-Worker',$worker,'-Driver',$driver,'-ExpectDriver','0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c','-ExpectWorker',$wh,'-ExpectExe','87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374','-ExpectDll','7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2','-OutRoot',$dir,'-Fixture',$fixture,'-KeyMode','char');if($variant){$argv+=@('-Variant',$variant)}
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.Arguments=(($argv|ForEach-Object{Quote ([string]$_)})-join ' ');$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($psi);$handle=$proc.Handle;$so=$proc.StandardOutput.ReadToEndAsync();$se=$proc.StandardError.ReadToEndAsync();$proc.WaitForExit();$proc.Refresh();[uint32]$code=259;$wait=[RootMatrixNativeTerminal]::WaitForSingleObject($handle,0);$readable=[RootMatrixNativeTerminal]::GetExitCodeProcess($handle,[ref]$code);$od=$so.Wait(15000);$ed=$se.Wait(15000)
 $stdout=if($od){$so.Result}else{'<drain-timeout>'};$stderr=if($ed){$se.Result}else{'<drain-timeout>'};[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stdout.txt'),$stdout);[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stderr.txt'),$stderr)
 $r=[ordered]@{kind='root-full16-smoke-case-v1';fixture=$fixture;variant=$variant;workerHash=$wh;coordinatorHash=$ch;originalHandleRetained=($handle -ne [IntPtr]::Zero);kernelWait=$wait;kernelExitReadable=$readable;kernelExit=$code;dotnetExit=$proc.ExitCode;stdoutDrained=$od;stderrDrained=$ed;qualification='smoke-only';out=$dir}
 [IO.File]::WriteAllText((Join-Path $dir 'root-smoke.json'),($r|ConvertTo-Json -Depth 6));$rows+=,$r
 if($wait -ne 0 -or -not $readable -or $code -eq 259 -or $code -ne 0 -or $proc.ExitCode -ne 0 -or -not $od -or -not $ed){throw ('Smoke failed '+$label+' raw preserved at '+$dir)}
 Write-Output ('PASS smoke '+$label)
}
[IO.File]::WriteAllText((Join-Path $out 'root-smoke-summary.json'),(@{kind='root-full16-smoke-v1';status='passed';configs=1;count=1;rows=$rows;qualification='smoke-only'}|ConvertTo-Json -Depth 8));Write-Output 'SMOKE_PASS configs=1 count=1'
