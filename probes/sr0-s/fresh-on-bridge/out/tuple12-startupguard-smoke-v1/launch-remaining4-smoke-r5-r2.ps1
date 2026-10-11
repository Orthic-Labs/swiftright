$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5\matrix-controls-v6';$base='D:\Claude\swiftright\.work\sr0-r12-typecheck\src';$driver='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5\f3-ready-diagnosis-v1\drive-fixture-noactivate-focus-r6-diagnostic.ps1'
$out='D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Remaining4-smoke-r5-r2'
$worker=Join-Path $stage 'worker-v5.ps1';$co=Join-Path $stage 'coordinator-v5.ps1'
$wh='b039d4dce888e3dabbb7c3109bcd64abbf2b6313fdc818b4b11398460cdbac39';$ch='3a3a815c'
$manifest=[IO.File]::ReadAllText('D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5\stage-manifest.json')|ConvertFrom-Json
foreach($r in $manifest.files){$f=Join-Path 'D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5' ($r.path -replace '/','\');if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $f).Length -ne $r.bytes){throw ('Pinned source drift '+$r.path)}}
$ch=(Get-FileHash -LiteralPath $co).Hash.ToLowerInvariant();if($ch -cne 'e85c3c8f57b8e36d0df440bd60a884d28ce516824f8c127b5577345d1f982d6f'){throw 'Coordinator drift'};if((Get-FileHash -LiteralPath $worker).Hash.ToLowerInvariant() -cne $wh){throw 'Worker drift'}
if((Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant() -cne '0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c'){throw 'Driver drift'}
if(Test-Path -LiteralPath $out){throw 'Fresh smoke root required'};[IO.Directory]::CreateDirectory($out)|Out-Null
$proof=[IO.File]::ReadAllText('D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5\actual-typecheck-r5.json')|ConvertFrom-Json
if($proof.status -cne 'passed' -or $proof.psFilesParsed -ne 4 -or $proof.csharpHelpersCompiled -ne 2 -or $proof.headlessRuns -ne 1 -or $proof.windowRuns -ne 0 -or $proof.lockActions -ne 0 -or -not $proof.kernelControl.originalHandleRetained -or -not $proof.kernelControl.stillRunningRejected -or -not $proof.kernelControl.stdoutDrained -or -not $proof.kernelControl.stderrDrained){throw 'Actual r5 headless proof absent'}
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class RootMatrixNativeTerminal { [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms); [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint code); }
'@
function Quote([string]$s){return '"'+$s.Replace('"','\"')+'"'}
$configs=@([pscustomobject]@{Fixture='F6';Variant='reduced'},[pscustomobject]@{Fixture='F7';Variant=''},[pscustomobject]@{Fixture='F8';Variant=''},[pscustomobject]@{Fixture='F9';Variant=''})
$rows=@()
foreach($cfg in $configs){
 $fixture=$cfg.Fixture;$variant=$cfg.Variant;$label=$fixture+$(if($variant){'-'+$variant}else{''});$dir=Join-Path $out ($label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir)|Out-Null
 $argv=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$co,'-Base',$base,'-Worker',$worker,'-Driver',$driver,'-ExpectDriver','0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c','-ExpectWorker',$wh,'-ExpectExe','87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374','-ExpectDll','7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2','-OutRoot',$dir,'-Fixture',$fixture,'-KeyMode','char');if($variant){$argv+=@('-Variant',$variant)}
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.Arguments=(($argv|ForEach-Object{Quote ([string]$_)})-join ' ');$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($psi);$handle=$proc.Handle;$so=$proc.StandardOutput.ReadToEndAsync();$se=$proc.StandardError.ReadToEndAsync();$proc.WaitForExit();$proc.Refresh();[uint32]$code=259;$wait=[RootMatrixNativeTerminal]::WaitForSingleObject($handle,0);$readable=[RootMatrixNativeTerminal]::GetExitCodeProcess($handle,[ref]$code);$od=$so.Wait(15000);$ed=$se.Wait(15000)
 $stdout=if($od){$so.Result}else{'<drain-timeout>'};$stderr=if($ed){$se.Result}else{'<drain-timeout>'};[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stdout.txt'),$stdout);[IO.File]::WriteAllText((Join-Path $dir 'root-coordinator.stderr.txt'),$stderr)
 $r=[ordered]@{kind='root-full16-smoke-case-v1';fixture=$fixture;variant=$variant;workerHash=$wh;coordinatorHash=$ch;originalHandleRetained=($handle -ne [IntPtr]::Zero);kernelWait=$wait;kernelExitReadable=$readable;kernelExit=$code;dotnetExit=$proc.ExitCode;stdoutDrained=$od;stderrDrained=$ed;qualification='smoke-only';out=$dir}
 [IO.File]::WriteAllText((Join-Path $dir 'root-smoke.json'),($r|ConvertTo-Json -Depth 6));$rows+=,$r
 if($wait -ne 0 -or -not $readable -or $code -eq 259 -or $code -ne 0 -or $proc.ExitCode -ne 0 -or -not $od -or -not $ed){throw ('Smoke failed '+$label+' raw preserved at '+$dir)}
 Write-Output ('PASS smoke '+$label)
}
[IO.File]::WriteAllText((Join-Path $out 'root-smoke-summary.json'),(@{kind='root-full16-smoke-v1';status='passed';configs=4;count=4;rows=$rows;qualification='smoke-only'}|ConvertTo-Json -Depth 8));Write-Output 'SMOKE_PASS configs=4 count=4'
