$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.work\takeover-matrix-r5.zip';$root='D:\Claude\swiftright\.work\sr0-takeover-controls-v1\r5'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'ea7d49c177f4ae7d664426fc2df0658e13c4a3e2e5993c9006e008739f1ab08b'){throw 'Source ZIP drift'}
if(Test-Path -LiteralPath $root){throw 'Fresh stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $root
$m=[IO.File]::ReadAllText((Join-Path $root 'stage-manifest.json'))|ConvertFrom-Json
$parsed=0;$compiled=0
foreach($r in $m.files){
 $f=Join-Path $root ($r.path -replace '/','\')
 if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('Source drift '+$r.path)}
 if($f.EndsWith('.ps1')){
  $tokens=$null;$errors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ('Parse failure '+$r.path+': '+($errors|Out-String))};$parsed++
  if($r.path.StartsWith('f3-ready-diagnosis-v1/')){continue}
  $blocks=@($ast.FindAll({param($a) $a -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $a.Value -match 'using System' -and $a.Value -match 'DllImport'},$true))
  foreach($b in $blocks){Add-Type -TypeDefinition $b.Value -ErrorAction Stop;$compiled++}
 }
}
$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 2000; [Console]::Out.WriteLine(''owned-out''); [Console]::Error.WriteLine(''owned-err''); exit 0"';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$proc=[Diagnostics.Process]::Start($psi);$handle=$proc.Handle;$so=$proc.StandardOutput.ReadToEndAsync();$se=$proc.StandardError.ReadToEndAsync()
try{
 [uint32]$wc=259;[uint32]$rc=259
 $ww=[Sr0SmokeKernel.Native]::WaitForSingleObject($handle,0);$wr=[Sr0SmokeKernel.Native]::GetExitCodeProcess($handle,[ref]$wc)
 $rw=[Sr0MatrixRunnerV5Kernel]::WaitForSingleObject($handle,0);$rr=[Sr0MatrixRunnerV5Kernel]::GetExitCodeProcess($handle,[ref]$rc)
 if($ww -eq 0 -or $rw -eq 0 -or -not $wr -or -not $rr -or $wc -ne 259 -or $rc -ne 259){throw 'Still-active fault admitted'}
 if(-not $proc.WaitForExit(10000)){throw 'Owned control deadline'};$proc.Refresh()
 $ww=[Sr0SmokeKernel.Native]::WaitForSingleObject($handle,0);$wr=[Sr0SmokeKernel.Native]::GetExitCodeProcess($handle,[ref]$wc)
 $rw=[Sr0MatrixRunnerV5Kernel]::WaitForSingleObject($handle,0);$rr=[Sr0MatrixRunnerV5Kernel]::GetExitCodeProcess($handle,[ref]$rc)
 $od=$so.Wait(5000);$ed=$se.Wait(5000)
 if($ww -ne 0 -or $rw -ne 0 -or -not $wr -or -not $rr -or $wc -ne 0 -or $rc -ne 0 -or $proc.ExitCode -ne 0 -or -not $od -or -not $ed -or $so.Result.Trim() -cne 'owned-out' -or $se.Result.Trim() -cne 'owned-err'){throw 'Kernel terminal/drain proof failed'}
 $proof=[ordered]@{kind='root-sr0-matrix-r5-typecheck-v1';status='passed';sourceFiles=$m.files.Count;psFilesParsed=$parsed;csharpHelpersCompiled=$compiled;headlessRuns=1;windowRuns=0;lockActions=0;kernelControl=@{originalHandleRetained=($handle -ne [IntPtr]::Zero);stillRunningRejected=$true;workerWait=$ww;runnerWait=$rw;workerExit=$wc;runnerExit=$rc;dotnetExit=$proc.ExitCode;stdoutDrained=$od;stderrDrained=$ed};at=[DateTimeOffset]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText((Join-Path $root 'actual-typecheck-r5.json'),($proof|ConvertTo-Json -Depth 6));$proof|ConvertTo-Json -Depth 6
}finally{if(-not $proc.HasExited){$proc.Kill();$proc.WaitForExit(10000)|Out-Null};$proc.Dispose()}
