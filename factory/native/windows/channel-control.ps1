# Separate preclosure observational channel control; never production native-case evidence.
param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive owned task required'}
$c=Get-Content -Raw $Config|ConvertFrom-Json
$factory='D:\Claude\swiftright\factory\native\windows\'
foreach($path in @($c.package,$c.runRoot)){if(-not [IO.Path]::GetFullPath($path).StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned factory path required'}}
$plan=Get-Content -Raw (Join-Path $c.package 'plan.json')|ConvertFrom-Json
$compiled=Get-Content -Raw (Join-Path $c.package 'observation.json')|ConvertFrom-Json
if($plan.synthetic -or -not $plan.tupleIndependent -or $plan.executionEligible -or $plan.purpose -notin @('fixed qualification host measurement','fixed channel control host')){throw 'Actual fixed compile-only control host required'}
if($compiled.exitCode -ne 0 -or $compiled.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $compiled.sourceHash -ne $plan.sourceHash -or $compiled.planSha256 -ne (Get-FileHash (Join-Path $c.package 'plan.json')).Hash.ToLowerInvariant()){throw 'Exact compiled host required'}
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith([IO.Path]::GetFullPath($c.package)+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $compiled.exeSha256){throw 'Owned executable hash required'}
$bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
if([BitConverter]::ToUInt16($bytes,$pe+24+68) -ne 2){throw 'GUI PE2 required'}
$stageDll=Join-Path $plan.stage 'renderer\swiftright_render.dll'
if((Get-FileHash $stageDll).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Staged renderer drift'}
foreach($binding in $plan.sourceBindings){$path=[IO.Path]::GetFullPath((Join-Path $c.package $binding.path));if(-not $path.StartsWith([IO.Path]::GetFullPath($c.package)+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $path).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Control host source drift'}}
. (Join-Path $PSScriptRoot 'pixels-background.ps1')
. (Join-Path $PSScriptRoot 'verify-runtime-source.ps1')
Assert-FactoryRuntimeSource $plan $c.package
function Check-Lock {if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -ne $c.owner){throw 'Owned reservation lost'}}
Check-Lock
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
 if($fgpid -eq $childPID -or $fgpid -eq $PID){
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

Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class FactoryOccluder {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateWindowExW(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr owner,IntPtr menu,IntPtr instance,IntPtr param);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h,uint cmd);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr h,IntPtr r,bool erase);
}
'@
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$status='hold-channel-control';$errorText='';$p=$null;$cover=[IntPtr]::Zero;$phases=@();$fgBefore=[FactoryDesktop]::GetForegroundWindow()
try{
 Assert-Background 0 $c.runRoot $fgBefore
 [ordered]@{pid=$PID;path=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;startedAt=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'controller-owned-process.json')
 $info=[Diagnostics.ProcessStartInfo]::new($exe);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 [ordered]@{pid=$p.Id;path=$exe;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'owned-process.json')
 $deadline=[DateTime]::UtcNow.AddSeconds(6)
 do{$p.Refresh();Assert-Background $p.Id $c.runRoot $fgBefore;Check-Lock;if($p.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Control renderer window unavailable'};Start-Sleep -Milliseconds 100}while($p.MainWindowHandle -eq [IntPtr]::Zero)
 $hwnd=$p.MainWindowHandle
 if(-not [FactoryDesktop]::SetWindowPos($hwnd,[IntPtr]::new(1),0,0,0,0,0x0013)){throw 'Background placement failed'}
 $guard={Assert-Background $p.Id $c.runRoot $fgBefore;Check-Lock;if($p.HasExited){throw 'Control renderer exited'}}
 foreach($phase in @('baseline','occluded','restored','content-changed')){
  & $guard
  $dir=Join-Path $c.runRoot $phase;New-Item -ItemType Directory -Path $dir|Out-Null
  if($phase -eq 'occluded'){
   $r=[FactoryOccluder+RECT]::new();$origin=[FactoryOccluder+POINT]::new()
   if(-not [FactoryOccluder]::GetClientRect($hwnd,[ref]$r) -or -not [FactoryOccluder]::ClientToScreen($hwnd,[ref]$origin)){throw 'Owned client control bounds unavailable'}
   $above=[FactoryOccluder]::GetWindow($hwnd,3)
   # Create hidden, nonactivating black static rectangle; atomic show places it immediately above owned background host.
   # HWND_BOTTOM fallback preserves background if no previous z-order sibling exists.
   if($above -eq [IntPtr]::Zero){$above=[IntPtr]::new(1)}
   $cover=[FactoryOccluder]::CreateWindowExW(0x08000080,'STATIC','Factory owned occlusion control',[uint32]2147483652,$origin.x,$origin.y,$r.right,$r.bottom,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero)
   if($cover -eq [IntPtr]::Zero){throw 'Owned hidden occluder unavailable'}
   if(-not [FactoryDesktop]::SetWindowPos($cover,$above,$origin.x,$origin.y,$r.right,$r.bottom,0x0050)){throw 'Owned background occluder placement failed'}
   [FactoryOccluder]::UpdateWindow($cover)|Out-Null
   [ordered]@{hwnd=$cover.ToInt64();insertAfter=$above.ToInt64();target=$hwnd.ToInt64();ownerPID=$PID;exStyle='WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW';style='WS_POPUP|SS_BLACKRECT';x=$origin.x;y=$origin.y;width=$r.right;height=$r.bottom;topmost=$false;inputUsed=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'occluder.json')
  }
  if($phase -eq 'restored'){
   if($cover -ne [IntPtr]::Zero){[FactoryOccluder]::DestroyWindow($cover)|Out-Null;$cover=[IntPtr]::Zero}
   [FactoryOccluder]::InvalidateRect($hwnd,[IntPtr]::Zero,$false)|Out-Null
   [ordered]@{target=$hwnd.ToInt64();request='InvalidateRect(no erase)';contentChangeRequested=$false;providerInvalidationObserved=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'invalidation-control.json')
  }
  if($phase -eq 'content-changed'){for($wait=0;$wait -lt 45;$wait++){& $guard;Start-Sleep -Milliseconds 100}}
  & $guard
  $pixel=Capture-FactoryPixels $hwnd $p.Id $dir $guard
  $phases+=[ordered]@{name=$phase;pixels=$pixel;cover=$cover.ToInt64()}
 }
 $status='completed-observational-channel-control'
}catch{$errorText=[string]$_}
finally{
 if($cover -ne [IntPtr]::Zero){[FactoryOccluder]::DestroyWindow($cover)|Out-Null}
 if($p){if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $exe -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null};if($out.Wait(5000)){[IO.File]::WriteAllText((Join-Path $c.runRoot 'host.stdout.txt'),$out.GetAwaiter().GetResult())};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $c.runRoot 'host.stderr.txt'),$err.GetAwaiter().GetResult())}}
 [ordered]@{kind='preclosure-owned-channel-control';status=$status;error=$errorText;runtimeCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;stageSourceCommit=$plan.stageSourceCommit;rendererHash='sha256:'+$plan.rendererSha256;exeHash='sha256:'+$compiled.exeSha256;foregroundBefore=$fgBefore.ToInt64();foregroundAfter=[FactoryDesktop]::GetForegroundWindow().ToInt64();phases=$phases;nativeCaseCaptureCount=0;frozenTupleBound=$false;qualificationGranted=$false;providerInvalidationObserved=$false;permissionsPromptRequested=$false;stageHashAfter=(Get-FileHash $stageDll).Hash.ToLowerInvariant();finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 18|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'channel-control.json')
 [ordered]@{status=$status;error=$errorText;finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $c.runRoot 'task-result.json')
}
