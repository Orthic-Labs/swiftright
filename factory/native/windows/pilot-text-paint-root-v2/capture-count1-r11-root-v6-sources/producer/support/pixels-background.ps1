# Factory-owned HWND only. Read-only adaptation of BridgeSmoke drive-pixels.ps1.
# No activation/input. Caller supplies foreground/ownership abort callback.
function Capture-FactoryPixels([IntPtr]$Hwnd,[int]$ChildPID,[string]$Directory,[scriptblock]$Guard) {
 Add-Type -AssemblyName System.Drawing
 if(-not ('FactoryPixels' -as [type])) {
 Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices; using System.Threading.Tasks;
public static class FactoryPixels {
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 public static long[] Owners(IntPtr h,int w,int height) {
  POINT o=new POINT(); if(!ClientToScreen(h,ref o))throw new Exception("ClientToScreen failed"); long[] owners=new long[25]; int i=0;
  foreach(int x in new int[]{1,w/4,w/2,3*w/4,w-2})foreach(int y in new int[]{1,height/4,height/2,3*height/4,height-2}) {POINT p=new POINT();p.x=o.x+x;p.y=o.y+y;owners[i++]=GetAncestor(WindowFromPoint(p),2).ToInt64();} return owners;
 }
 public static Task<bool> Capture(IntPtr h,int w,int height,string path,bool print) {
  return Task.Run(()=>{using(Bitmap b=new Bitmap(w,height,PixelFormat.Format32bppArgb)){using(Graphics g=Graphics.FromImage(b)){if(print){g.Clear(Color.Magenta);IntPtr dc=g.GetHdc();try{if(!PrintWindow(h,dc,3))return false;}finally{g.ReleaseHdc(dc);}}else{POINT o=new POINT();if(!ClientToScreen(h,ref o))throw new Exception("ClientToScreen failed");g.CopyFromScreen(o.x,o.y,0,0,new Size(w,height),CopyPixelOperation.SourceCopy);}}b.Save(path,ImageFormat.Png);return true;}});
 }
}
'@
 }
 & $Guard
 [uint32]$actualPID=0;[FactoryPixels]::GetWindowThreadProcessId($Hwnd,[ref]$actualPID)|Out-Null
 if($actualPID -ne $ChildPID){throw 'Pixel HWND does not belong to owned child'}
 $rect=[FactoryPixels+RECT]::new();if(-not [FactoryPixels]::GetClientRect($Hwnd,[ref]$rect)){throw 'Client rectangle unavailable'}
 $w=$rect.right-$rect.left;$h=$rect.bottom-$rect.top
 if($w -lt 3 -or $h -lt 3 -or $w -gt 4096 -or $h -gt 4096){throw 'Pixel bounds invalid'}
 $rows=@()
 foreach($repeat in 1,2){
  & $Guard
  $ownersBefore=[FactoryPixels]::Owners($Hwnd,$w,$h)
  foreach($mode in 'printwindow','screen'){
   & $Guard
   $name=if($repeat -eq 1){'native.'+$mode+'.png'}else{'native.'+$mode+'.repeat.png'}
   $path=Join-Path $Directory $name
   $task=[FactoryPixels]::Capture($Hwnd,$w,$h,$path,($mode -eq 'printwindow'))
   $deadline=[DateTime]::UtcNow.AddSeconds(5)
   while(-not $task.IsCompleted){& $Guard;if([DateTime]::UtcNow -gt $deadline){throw 'Owned pixel readback deadline'};Start-Sleep -Milliseconds 100}
   if(-not $task.GetAwaiter().GetResult()){throw 'PrintWindow returned false'}
   & $Guard
   $rows += [ordered]@{repeat=$repeat;method=$mode;path=$name;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
  }
  $ownersAfter=[FactoryPixels]::Owners($Hwnd,$w,$h)
  $rows += [ordered]@{repeat=$repeat;control='natural-desktop-occlusion-grid';ownersBefore=$ownersBefore;ownersAfter=$ownersAfter;unoccludedSampled=(@($ownersBefore+$ownersAfter|Where-Object{$_ -ne $Hwnd.ToInt64()}).Count -eq 0)}
  Start-Sleep -Milliseconds 100
 }
 $pw=@($rows|Where-Object{$_.method -eq 'printwindow'});$screen=@($rows|Where-Object{$_.method -eq 'screen'})
 $result=[ordered]@{kind='factory-background-pixel-observation';hwnd=$Hwnd.ToInt64();pid=$ChildPID;width=$w;height=$h;dpi=[FactoryPixels]::GetDpiForWindow($Hwnd);printWindowFlags=3;printWindowFlagNames='PW_CLIENTONLY|PW_RENDERFULLCONTENT';samples=$rows;printWindowRepeatStable=($pw[0].sha256 -eq $pw[1].sha256);screenRepeatStable=($screen[0].sha256 -eq $screen[1].sha256);methodsEqual=($pw[0].sha256 -eq $screen[0].sha256);controlledOcclusionQualification=$false;providerReadbackExport=$false;nativeParity='hold';reason='Natural occlusion observations and repeats are controls, not proof of background occluded PrintWindow qualification'}
 $result|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $Directory 'native.pixels.json')
 return $result
}
