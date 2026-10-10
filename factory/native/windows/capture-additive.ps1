# Run only from interactive session under coordinator-owned desktop.lock.
# Uses targeted UIA reads. No global input, foreground/focus or lock mutation.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$LockOwner,[int]$Runs=20)
$ErrorActionPreference='Stop'
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Native capture requires interactive desktop task' }
if ($Runs -ne 20) { throw 'Native lane requires 20 independent replays' }
$root='D:\Claude\swiftright\factory\native\windows\'
$packagePath=[IO.Path]::GetFullPath($Package)
if(-not $packagePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside factory'}
$plan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
if($plan.synthetic){throw 'Synthetic plan cannot enter native lane'}
if(-not $plan.executionEligible -or $plan.hostMode -ne 'renderer'){throw 'Probe is not eligible native renderer host'}
if($plan.stage -ne 'D:\Claude\sr0-r10' -or $plan.rendererSha256 -ne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'){throw 'Unexpected stage or renderer pin'}
if(-not $plan.closureBinding -or -not $plan.closureBinding.tupleHash){throw 'Explicit CLOSED closure binding required'}
$closure=Join-Path $packagePath 'sr0-status-closed.md'
if((Get-FileHash -LiteralPath $closure).Hash.ToLowerInvariant() -ne $plan.closureBinding.statusHash.Replace('sha256:','')){throw 'Closure status hash drift'}
$overall=[regex]::Matches((Get-Content -Raw $closure),'(?m)^\*\*Overall:\s*(.+?)\*\*')
if($overall.Count -ne 1 -or $overall[0].Groups[1].Value -notmatch '^SR0 is CLOSED\b' -or $overall[0].Groups[1].Value -notmatch '(?i)tuple\s*0?10\b'){throw 'Unique CLOSED tuple10 declaration required'}
$closureReceiptPath=Join-Path $packagePath 'closure-receipt.json'
if(-not $plan.closureBinding.receiptHash -or (Get-FileHash -LiteralPath $closureReceiptPath).Hash.ToLowerInvariant() -ne $plan.closureBinding.receiptHash.Replace('sha256:','')){throw 'Exact closure receipt hash required'}
$closureReceipt=Get-Content -Raw $closureReceiptPath|ConvertFrom-Json
if((Get-Content -Raw $closureReceiptPath) -match '"synthetic"\s*:\s*true|"producer"\s*:\s*"test-fixture"'){throw 'Synthetic closure receipt rejected'}
if($closureReceipt.tuple -cne '10' -or $closureReceipt.decision -cne 'CLOSED' -or $closureReceipt.statusHash -cne $plan.closureBinding.statusHash -or $closureReceipt.closedAt -cne $plan.closureBinding.closedAt -or $plan.closureBinding.tuple -cne '10' -or $plan.closureBinding.decision -cne 'CLOSED'){throw 'Closure receipt/status/time binding differs'}
if($closureReceipt.closedAt -notmatch 'Z$' -or [DateTimeOffset]::Parse($closureReceipt.closedAt) -gt [DateTimeOffset]::UtcNow){throw 'Valid past UTC closure timestamp required'}
if((Get-FileHash -LiteralPath (Join-Path $packagePath 'sr0-tuple10-staging.md')).Hash.ToLowerInvariant() -ne $plan.closureBinding.tuple10StagingHash.Replace('sha256:','')){throw 'Tuple10 staging receipt drift'}
. (Join-Path $PSScriptRoot 'pixels-background.ps1')
. (Join-Path $PSScriptRoot 'verify-runtime-source.ps1')
Assert-FactoryRuntimeSource $plan $packagePath
if((Get-FileHash -LiteralPath (Join-Path $packagePath 'tuple.json')).Hash.ToLowerInvariant() -ne $plan.closureBinding.tupleHash.Replace('sha256:','')){throw 'Changed-runtime tuple drift'}
$compiled=Get-Content -Raw (Join-Path $packagePath 'observation.json')|ConvertFrom-Json
$compiledPlan=Join-Path $packagePath 'plan.json'
if($compiled.synthetic -or $compiled.observedAt -notmatch 'Z$' -or [DateTimeOffset]::Parse($compiled.observedAt) -le [DateTimeOffset]::Parse($closureReceipt.closedAt)){throw 'Actual compile must follow closure'}
if($plan.compileBinding){
 $compiledPlan=Join-Path $packagePath 'compile-plan.json'
 if((Get-FileHash -LiteralPath $compiledPlan).Hash.ToLowerInvariant() -ne $plan.compileBinding.planHash.Replace('sha256:','')){throw 'Archived compile plan drift'}
 if((Get-FileHash -LiteralPath (Join-Path $packagePath 'observation.json')).Hash.ToLowerInvariant() -ne $plan.compileBinding.observationHash.Replace('sha256:','')){throw 'Archived compile observation drift'}
 $prior=Get-Content -Raw $compiledPlan|ConvertFrom-Json
 if($prior.sourceHash -ne $plan.sourceHash -or $prior.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $prior.rendererSha256 -ne $plan.rendererSha256){throw 'Postcompile source/runtime/renderer binding changed'}
}
if($compiled.exitCode -ne 0 -or $compiled.sourceHash -cne $plan.sourceHash -or $compiled.runtimeSourceCommit -cne $plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -cne $plan.runtimeSourceTreeHash -or $compiled.stageSourceCommit -cne $plan.stageSourceCommit -or $compiled.rendererSha256 -cne $plan.rendererSha256){throw 'Successful exact compiled source/runtime/stage identity required'}
if($compiled.planSha256 -and (Get-FileHash -LiteralPath $compiledPlan).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Compile plan drift'}
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Executable outside package'}
function Check-Lock {if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -ne $LockOwner){throw 'Desktop lock ownership lost'}}
Check-Lock
foreach($binding in $plan.sourceBindings){
 $inputPath=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
 if(-not $inputPath.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source binding escapes package'}
 if((Get-FileHash -LiteralPath $inputPath).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Source binding drift'}
}
if((Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -ne $compiled.exeSha256){throw 'Executable drift'}
$exeBytes=[IO.File]::ReadAllBytes($exe);$peOffset=[BitConverter]::ToInt32($exeBytes,60)
if([BitConverter]::ToUInt16($exeBytes,$peOffset+24+68) -ne 2){throw 'Background-only renderer requires GUI subsystem'}
if((Get-FileHash -LiteralPath 'D:\Claude\sr0-r10\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class FactoryDesktop {
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int cx,int cy,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,System.Text.StringBuilder name,int size);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,System.Text.StringBuilder text,int size);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
[FactoryDesktop]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))|Out-Null
function Assert-Background([int]$childPID,[string]$directory,[IntPtr]$before) {
 $fg=[FactoryDesktop]::GetForegroundWindow();[uint32]$fgpid=0
 [FactoryDesktop]::GetWindowThreadProcessId($fg,[ref]$fgpid)|Out-Null
 if($fgpid -eq $childPID){
  $cls=[Text.StringBuilder]::new(256);$title=[Text.StringBuilder]::new(256)
  [FactoryDesktop]::GetClassName($fg,$cls,256)|Out-Null;[FactoryDesktop]::GetWindowText($fg,$title,256)|Out-Null
  [ordered]@{foregroundBefore=$before.ToInt64();foregroundAfter=$fg.ToInt64();foregroundPID=$fgpid;foregroundClass=$cls.ToString();foregroundTitle=$title.ToString();createNoWindow=$true;guard='owned-foreground-abort'}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $directory 'launch-observation.json')
  throw 'Background-only guard: owned process foreground'
 }
}
function Read-UIA($node,[int]$depth=0) {
 if($depth -gt 40){throw 'UIA depth bound exceeded'}
 $c=$node.Current
 $record=[ordered]@{name=$c.Name;automationId=$c.AutomationId;controlType=$c.ControlType.ProgrammaticName;enabled=$c.IsEnabled;patterns=@($node.GetSupportedPatterns()|ForEach-Object{$_.ProgrammaticName});offscreen=$c.IsOffscreen;bounds=@($c.BoundingRectangle.X,$c.BoundingRectangle.Y,$c.BoundingRectangle.Width,$c.BoundingRectangle.Height);children=@()}
 $walker=[Windows.Automation.TreeWalker]::RawViewWalker
 $child=$walker.GetFirstChild($node);$count=0
 while($null -ne $child){if(++$count -gt 1000){throw 'UIA child bound exceeded'};$record.children+=Read-UIA $child ($depth+1);$child=$walker.GetNextSibling($child)}
 return $record
}
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$records=@()
for($i=1;$i -le 20;$i++){
 Check-Lock
 $dir=Join-Path $packagePath ('native-{0:00}' -f $i)
 if(Test-Path -LiteralPath $dir){throw 'Replay output exists; prepare fresh package'}
 New-Item -ItemType Directory -Path $dir|Out-Null
 $foregroundBefore=[FactoryDesktop]::GetForegroundWindow()
 $startInfo=[Diagnostics.ProcessStartInfo]::new($exe)
 $startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true
 $startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($startInfo)
 $stdoutTask=$p.StandardOutput.ReadToEndAsync();$stderrTask=$p.StandardError.ReadToEndAsync()
 [ordered]@{pid=$p.Id;path=$exe;startedAt=$p.StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-process.json')
 try {
  $deadline=[DateTime]::UtcNow.AddSeconds(6)
  do{$p.Refresh();Assert-Background $p.Id $dir $foregroundBefore;if($p.HasExited){throw 'Renderer exited before capture'};if([DateTime]::UtcNow -gt $deadline){throw 'Renderer window deadline'};Start-Sleep -Milliseconds 100}while($null -eq $p.MainWindowHandle -or $p.MainWindowHandle -eq [IntPtr]::Zero)
  $hwnd=$p.MainWindowHandle
  $foregroundAfter=[FactoryDesktop]::GetForegroundWindow()
  $windowClass=[Text.StringBuilder]::new(256);$windowTitle=[Text.StringBuilder]::new(256)
  [FactoryDesktop]::GetClassName($foregroundAfter,$windowClass,256)|Out-Null;[FactoryDesktop]::GetWindowText($foregroundAfter,$windowTitle,256)|Out-Null
  [ordered]@{foregroundBefore=$foregroundBefore.ToInt64();foregroundAfter=$foregroundAfter.ToInt64();ownedWindow=$hwnd.ToInt64();foregroundClass=$windowClass.ToString();foregroundTitle=$windowTitle.ToString();createNoWindow=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'launch-observation.json')
  if($foregroundAfter -eq $hwnd){throw 'Background-only guard: owned window activated'}
  # Keep ordinary test window behind user's windows, without activation.
  [FactoryDesktop]::SetWindowPos($hwnd,[IntPtr]::new(1),0,0,0,0,0x0013)|Out-Null
  for($pause=0;$pause -lt 5;$pause++){Assert-Background $p.Id $dir $foregroundBefore;Start-Sleep -Milliseconds 100}
  Check-Lock
  $element=[Windows.Automation.AutomationElement]::FromHandle($hwnd)
  Assert-Background $p.Id $dir $foregroundBefore
  $uia=Read-UIA $element
  Assert-Background $p.Id $dir $foregroundBefore
  $uia|ConvertTo-Json -Depth 80|Set-Content -Encoding UTF8 (Join-Path $dir 'native.uia.json')
  $fgAtCapture=([FactoryDesktop]::GetForegroundWindow() -eq $hwnd)
  if($fgAtCapture){throw 'Background-only guard: owned window foreground at capture'}
  $r=$element.Current.BoundingRectangle
  if($r.Width -le 0 -or $r.Height -le 0 -or $r.Width -gt 4096 -or $r.Height -gt 4096){throw 'Invalid native screenshot bounds'}
  $pixels=Capture-FactoryPixels $hwnd $p.Id $dir {Assert-Background $p.Id $dir $foregroundBefore;Check-Lock}
  Assert-Background $p.Id $dir $foregroundBefore
  $exitDeadline=[DateTime]::UtcNow.AddSeconds(15)
  while(-not $p.WaitForExit(100)){
   Assert-Background $p.Id $dir $foregroundBefore;Check-Lock
   if([DateTime]::UtcNow -gt $exitDeadline){& taskkill /PID $p.Id /T /F|Out-Null;throw 'Owned renderer child deadline'}
  }
  Assert-Background $p.Id $dir $foregroundBefore
  if(-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)){throw 'Owned output stream deadline'}
  [IO.File]::WriteAllText((Join-Path $dir 'host.stdout.txt'),$stdoutTask.GetAwaiter().GetResult())
  [IO.File]::WriteAllText((Join-Path $dir 'host.stderr.txt'),$stderrTask.GetAwaiter().GetResult())
  $hostOutput=Get-Content -Raw (Join-Path $dir 'host.stdout.txt')
  $validHost=($p.ExitCode -eq 0 -and $hostOutput -match 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' -and $hostOutput -match 'FACTORY_RENDERER_READY' -and $hostOutput -match 'FACTORY_COMMIT' -and $hostOutput -notmatch 'FACTORY_(RENDER|STARTUP)_ERROR')
  $records += [ordered]@{foregroundBeforeLaunch=$foregroundBefore.ToInt64();foregroundAfterWindow=$foregroundAfter.ToInt64();activationVeto='thread-cbt';hostValid=$validHost;probeForegroundAtCapture=$fgAtCapture;dpiAwarenessRequested='per-monitor-v2';backgroundPlacementRequested=$true;index=$i;case=$plan.case;manifestHash=$plan.manifestHash;exitCode=$p.ExitCode;exeSha256=$compiled.exeSha256;rendererSha256=$plan.rendererSha256;sourceHash=$plan.sourceHash;captureMethod='PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen';pixelObservation=$pixels;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;stageSourceCommit=$plan.stageSourceCommit;occlusionQualified=$false;nativeParity='hold';reason='Background capture retains raw screen pixels; unobscured rendering requires separate verification';files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
 } finally {if(-not $p.HasExited){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null;if($p.HasExited -and $stdoutTask.Wait(5000) -and $stderrTask.Wait(5000)){[IO.File]::WriteAllText((Join-Path $dir 'host.stdout.txt'),$stdoutTask.GetAwaiter().GetResult());[IO.File]::WriteAllText((Join-Path $dir 'host.stderr.txt'),$stderrTask.GetAwaiter().GetResult())}}
}
Check-Lock
if((Get-FileHash -LiteralPath 'D:\Claude\sr0-r10\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift after native batch'}
$records|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $packagePath 'native-observation.json')

if(@($records|Where-Object{-not $_.hostValid}).Count -gt 0){throw 'Native observations contain renderer failures'}
