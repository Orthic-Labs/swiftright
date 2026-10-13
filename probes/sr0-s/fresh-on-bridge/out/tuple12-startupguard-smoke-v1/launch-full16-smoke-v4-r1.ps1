$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r2\matrix-controls-v4';$base='D:\Claude\swiftright\.work\sr0-r12-typecheck\src';$driver='D:\Claude\swiftright\.work\sr0-matrix-controls-v1\drive-fixture-noactivate-focus-r5.ps1'
$out='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Full16-smoke-v4-r1'
$worker=Join-Path $stage 'worker-v4.ps1';$co=Join-Path $stage 'coordinator-v4.ps1'
$wh='efa1bc833afa0ab9b04caa8e41f5dd8a685613c488075e91422ef19973dc0079';$ch='3a3a815c'
$manifest=[IO.File]::ReadAllText('D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r2\stage-manifest.json')|ConvertFrom-Json
foreach($r in $manifest.files){$f=Join-Path 'D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r2' ($r.path -replace '/','\');if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $f).Length -ne $r.bytes){throw ('Pinned source drift '+$r.path)}}
$ch=(Get-FileHash -LiteralPath $co).Hash.ToLowerInvariant();if((Get-FileHash -LiteralPath $worker).Hash.ToLowerInvariant() -cne $wh){throw 'Worker drift'}
if((Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant() -cne '5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4'){throw 'Driver drift'}
if(Test-Path -LiteralPath $out){throw 'Fresh smoke root required'};[IO.Directory]::CreateDirectory($out)|Out-Null
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class RootMatrixNativeTerminal { [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms); [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint code); }
'@
function Quote([string]$s){return '"'+$s.Replace('"','\"')+'"'}
$configs=@(@('F3','list-0s'),@('F1',''),@('F2',''),@('F3','list-1s'),@('F3','list-3s'),@('F3','vstack-1s'),@('F3','vstack-3s'),@('F3','lazy-1s'),@('F3','lazy-3s'),@('F4',''),@('F5',''),@('F6',''),@('F6','reduced'),@('F7',''),@('F8',''),@('F9',''))
$rows=@()
foreach($cfg in $configs){
 $fixture=$cfg[0];$variant=$cfg[1];$label=$fixture+$(if($variant){'-'+$variant}else{''});$dir=Join-Path $out ($label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir)|Out-Null
 $argv=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$co,'-Base',$base,'-Worker',$worker,'-Driver',$driver,'-ExpectDriver','5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4','-ExpectWorker',$wh,'-ExpectExe','87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374','-ExpectDll','7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2','-OutRoot',$dir,'-Fixture',$fixture,'-KeyMode','char');if($variant){$argv+=@('-Variant',$variant)}
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.Arguments=(($argv|ForEach-Object{Quote ([string]$_)})-join ' ');$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($psi);$handle=$proc.Handle;$so=$proc.StandardOutput.ReadToEndAsync();$se=$proc.StandardError.ReadToEndAsync();$proc.WaitForExit();$proc.Refresh();[uint32]$code=259;$wait=[RootMatrixNativeTerminal]::WaitForSingleObject($handle,0);$readable=[RootMatrixNativeTerminal]::GetExitCodeProcess($handle,[ref]$code);$od=$so.Wait(15000);$ed=$se.Wait(15000)
 $stdout=if($od){$so.Result}else{'<drain-timeout>'};$stderr=if($ed){$se.Result}else{'<drain-timeout>'};[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stdout.txt'),$stdout);[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stderr.txt'),$stderr)
 $r=[ordered]@{kind='root-full16-smoke-case-v1';fixture=$fixture;variant=$variant;workerHash=$wh;coordinatorHash=$ch;originalHandleRetained=($handle -ne [IntPtr]::Zero);kernelWait=$wait;kernelExitReadable=$readable;kernelExit=$code;dotnetExit=$proc.ExitCode;stdoutDrained=$od;stderrDrained=$ed;qualification='smoke-only';out=$dir}
 [IO.File]::WriteAllText((Join-Path $dir 'root-smoke.json'),($r|ConvertTo-Json -Depth 6));$rows+=,$r
 if($wait -ne 0 -or -not $readable -or $code -eq 259 -or $code -ne 0 -or $proc.ExitCode -ne 0 -or -not $od -or -not $ed){throw ('Smoke failed '+$label+' raw preserved at '+$dir)}
 Write-Output ('PASS smoke '+$label)
}
[IO.File]::WriteAllText((Join-Path $out 'root-smoke-summary.json'),(@{kind='root-full16-smoke-v1';status='passed';configs=16;count=16;rows=$rows;qualification='smoke-only'}|ConvertTo-Json -Depth 8));Write-Output 'SMOKE_PASS configs=16 count=16'
