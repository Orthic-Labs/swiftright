# Runs inside the interactive session. Per run: launch host, find its window, push to background w/o activation, wait for the first present (settled digest), PrintWindow(flags 3), kill.
# -Frames N (F1 manual clock; env SWIFTRIGHT_CLOCK holds the N clock times): the run launches the host once per frame k with SWIFTRIGHT_FRAME=k and writes native-NN-fKK.png / host-NN-fKK.stdout.txt.
param([Parameter(Mandatory)][string]$Exe,[Parameter(Mandatory)][string]$Out,[int]$Runs=1,[string]$Owner='swiftright-87',[switch]$Shared,[int]$Frames=0,[switch]$FlickerProbe)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class PairNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint f);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int cx,int cy,uint f);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 public static Bitmap Last;
 public static string Grab(IntPtr h){
  RECT r; if(!GetClientRect(h,out r)) return ""; int w=r.right-r.left, ht=r.bottom-r.top; if(w<3||ht<3) return "";
  Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb);
  using(Graphics g=Graphics.FromImage(b)){g.Clear(Color.Magenta);IntPtr dc=g.GetHdc();bool ok;try{ok=PrintWindow(h,dc,3);}finally{g.ReleaseHdc(dc);} if(!ok){b.Dispose();return "";}}
  var d=b.LockBits(new Rectangle(0,0,w,ht),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
  string dg;
  try{ byte[] px=new byte[d.Stride*ht]; Marshal.Copy(d.Scan0,px,0,px.Length); using(var sha=System.Security.Cryptography.SHA256.Create()){ dg=BitConverter.ToString(sha.ComputeHash(px)); } }
  finally{b.UnlockBits(d);}
  if(Last!=null){Last.Dispose();} Last=b; return dg;
 }
 public static string SavePng(string path){ if(Last==null) return "no settled bitmap"; Last.Save(path,ImageFormat.Png); return "ok"; }
 public static string Shot(IntPtr h,string path){
  RECT r; if(!GetClientRect(h,out r)) return "GetClientRect failed"; int w=r.right-r.left, ht=r.bottom-r.top; if(w<3||ht<3) return "bad size "+w+"x"+ht;
  using(Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb)){using(Graphics g=Graphics.FromImage(b)){g.Clear(Color.Magenta);IntPtr dc=g.GetHdc();try{if(!PrintWindow(h,dc,3))return "PrintWindow false";}finally{g.ReleaseHdc(dc);}} b.Save(path,ImageFormat.Png);}
  return "ok";
 }
}
'@
if($FlickerProbe){ Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Globalization; using System.Runtime.InteropServices;
public static class FlickerScreen {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h,IntPtr dc);
 [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dst,int x,int y,int cx,int cy,IntPtr src,int sx,int sy,uint rop);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint flags);
 public static List<Bitmap> Kept=new List<Bitmap>();
 public static void Clear(){ foreach(Bitmap b in Kept){ b.Dispose(); } Kept.Clear(); }
 public static string Save(int idx,string path){ if(idx<0||idx>=Kept.Count) return "no frame "+idx; Kept[idx].Save(path,ImageFormat.Png); return "ok"; }
 // SHA-256 of the 32bpp rows (as PairNative.Grab), share of pixels with R,G,B < 8, rows at least 90% that dark, and 1 when the frame is black (>= 99% dark).
 public static string Stats(Bitmap b){
  int w=b.Width, ht=b.Height;
  var d=b.LockBits(new Rectangle(0,0,w,ht),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
  byte[] px=new byte[d.Stride*ht];
  try{ Marshal.Copy(d.Scan0,px,0,px.Length); } finally{ b.UnlockBits(d); }
  string dg; using(var sha=System.Security.Cryptography.SHA256.Create()){ dg=BitConverter.ToString(sha.ComputeHash(px)); }
  long dark=0; int darkRows=0;
  for(int y=0;y<ht;y++){ int rd=0; int off=y*d.Stride; for(int x=0;x<w;x++){ int i=off+4*x; if(px[i]<8&&px[i+1]<8&&px[i+2]<8) rd++; } dark+=rd; if(rd>=0.9*w) darkRows++; }
  double frac=(double)dark/((double)w*ht);
  return dg+"\t"+frac.ToString("F4",CultureInfo.InvariantCulture)+"\t"+darkRows+"\t"+(frac>=0.99?1:0);
 }
 // One screen grab of the client area: BitBlt from the screen DC (what the desktop composed at this instant), not PrintWindow.
 // Returns idx, digest, darkfrac, darkrows, black, topwin_ours (1 when the topmost window at the client centre is this window), screen rect sx,sy,w,h.
 // A failed grab has idx -1 and its reason in the last field.
 public static string Grab(IntPtr h){
  RECT r; if(!GetClientRect(h,out r)) return "-1\t\t\t\t\t\tgone";
  int w=r.right-r.left, ht=r.bottom-r.top; if(w<3||ht<3) return "-1\t\t\t\t\t\tsize "+w+"x"+ht;
  POINT o=new POINT(); ClientToScreen(h,ref o);
  POINT c=new POINT(); c.x=o.x+w/2; c.y=o.y+ht/2;
  IntPtr top=WindowFromPoint(c);
  int ours=(top!=IntPtr.Zero && (top==h || GetAncestor(top,2)==h))?1:0;
  Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb);
  using(Graphics g=Graphics.FromImage(b)){ IntPtr dc=g.GetHdc(); IntPtr sdc=GetDC(IntPtr.Zero); bool ok; try{ ok=BitBlt(dc,0,0,w,ht,sdc,o.x,o.y,0x00CC0020|0x40000000); } finally{ ReleaseDC(IntPtr.Zero,sdc); g.ReleaseHdc(dc); } if(!ok){ b.Dispose(); return "-1\t\t\t\t\t\tbitblt"; } }
  string s=Stats(b); Kept.Add(b);
  return (Kept.Count-1)+"\t"+s+"\t"+ours+"\t"+o.x+","+o.y+","+w+","+ht;
 }
}
'@
}
[void][PairNative]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$results=@()
try{
 for($i=1;$i -le $Runs;$i++){
  $n='{0:00}' -f $i;$status='ok'
  $fl=$(if($Frames -gt 0){0..($Frames-1)}else{@(-1)})
  foreach($k in $fl){
   $sfx=$(if($k -ge 0){'-f{0:00}' -f $k}else{''});$p=$null;$st='failed'
   try{
    if(-not $Shared -and (Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $Owner){throw 'lock ownership lost'}
    $si=[Diagnostics.ProcessStartInfo]::new($Exe);$si.Arguments='--factory-capture-lease-seconds=40';$si.UseShellExecute=$false;$si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
    if($k -ge 0){$si.EnvironmentVariables['SWIFTRIGHT_FRAME']=[string]$k}
    $p=[Diagnostics.Process]::Start($si);$so=$p.StandardOutput.ReadToEndAsync();$se=$p.StandardError.ReadToEndAsync()
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{Start-Sleep -Milliseconds 100;$p.Refresh();if($p.HasExited){throw "host exited early code=$($p.ExitCode)"};if([DateTime]::UtcNow -gt $deadline){throw 'window deadline'}}while($p.MainWindowHandle -eq [IntPtr]::Zero)
    $h=$p.MainWindowHandle
    if(-not [PairNative]::SetWindowPos($h,[IntPtr]::new(1),0,0,0,0,0x0013)){throw 'SetWindowPos failed'}   # HWND_BOTTOM, NOSIZE|NOMOVE|NOACTIVATE
    # First real present: the client content must be settled (three identical PrintWindow digests, 200 ms apart, 20 s limit) before the
    # capture. The saved frame is the last settled bitmap itself (the bytes that produced the stable digest), not a fresh PrintWindow:
    # a PrintWindow taken after the settle returned a transient black strip (CI 38852596361, removal-move-v1 run 01 frame 01; the settled digests were clean).
    # Every poll digest is kept; any poll that differs from the stable digest is logged as a warning and in settle-NN-fKK.txt.
    $settleStart=[DateTime]::UtcNow;$prevD=$null;$same=0;$digests=@();$settled=$false;$stableD=$null
    # FlickerProbe (-FlickerProbe, probe runs only): the screen region is BitBlt-grabbed at the same instant as each PrintWindow poll; every poll is logged to flicker-NN-fKK.tsv,
    # the screen frame of each poll that differs from the final poll's screen digest is saved. The window is made topmost first so the screen grab is not obscured.
    $sGrabs=@();$pwStats=@()
    if($FlickerProbe){ [FlickerScreen]::Clear(); [void][PairNative]::SetWindowPos($h,[IntPtr]::new(-1),0,0,0,0,0x0013) }   # HWND_TOPMOST, NOSIZE|NOMOVE|NOACTIVATE
    while(-not $settled){
     if([DateTime]::UtcNow -gt $settleStart.AddSeconds(20)){throw 'first present not observed within 20 s'}
     Start-Sleep -Milliseconds 200
     if($FlickerProbe){ $tS=[DateTime]::UtcNow.ToString('HH:mm:ss.fff'); $sg=[FlickerScreen]::Grab($h) }
     $dg=[PairNative]::Grab($h);$digests+=,$dg
     if($FlickerProbe){ $sGrabs+=,@($tS,$sg); $pwStats+=,@([DateTime]::UtcNow.ToString('HH:mm:ss.fff'),$(if($dg -ne ''){[FlickerScreen]::Stats([PairNative]::Last)}else{"empty`t`t`t"})) }
     if($dg -ne '' -and $dg -eq $prevD){$same++}else{$same=0}
     $prevD=$dg;if($same -ge 2){$settled=$true;$stableD=$dg}
    }
    $differs=@();for($q=0;$q -lt $digests.Count;$q++){ if($digests[$q] -ne $stableD){ $differs+=("poll$($q+1)=" + $digests[$q]) } }
    if($differs.Count -gt 0){ Write-Warning ("settle $n$sfx : " + $differs.Count + " of " + $digests.Count + " PrintWindow poll(s) differ from the stable digest: " + ($differs -join ' ')) }
    Set-Content -Path (Join-Path $Out "settle-$n$sfx.txt") -Value ("settled polls=" + $digests.Count + " ms=" + [int]([DateTime]::UtcNow-$settleStart).TotalMilliseconds + " stable=$stableD differing=" + $differs.Count + $(if($differs.Count){' ' + ($differs -join ' ')}else{''}))
    if($FlickerProbe){
     $sStable=($sGrabs[-1][1] -split "`t")[1]
     $tsv=@("poll`tutc_screen`tutc_pw`tscreen_idx`tscreen_digest`tscreen_darkfrac`tscreen_darkrows`tscreen_black`tscreen_topwin_ours`tscreen_rect`tpw_digest`tpw_darkfrac`tpw_darkrows`tpw_black`tscreen_differs`tpw_differs")
     for($q=0;$q -lt $sGrabs.Count;$q++){
      $sf=@($sGrabs[$q][1] -split "`t");$pf=@($pwStats[$q][1] -split "`t")
      $sd=[int]($sf[1] -ne $sStable);$pd=[int]($digests[$q] -ne $stableD)
      $tsv+=((@(($q+1),$sGrabs[$q][0],$pwStats[$q][0])+$sf+$pf+@($sd,$pd)) -join "`t")
      if($sf[0] -ne '-1' -and $sd){[void][FlickerScreen]::Save([int]$sf[0],(Join-Path $Out "flicker-$n$sfx-poll$($q+1)-screen.png"))}
     }
     Set-Content -Path (Join-Path $Out "flicker-$n$sfx.tsv") -Value $tsv
     [FlickerScreen]::Clear()
    }
    $r=[PairNative]::SavePng((Join-Path $Out "native-$n$sfx.png"));if($r -ne 'ok'){throw $r};$st='ok'
   }catch{$st=[string]$_}
   finally{
    if($p){try{if(-not $p.HasExited){$p.Kill()};[void]$p.WaitForExit(10000)}catch{}
     try{[void]$so.Wait(5000);$so.Result|Set-Content (Join-Path $Out "host-$n$sfx.stdout.txt");$se.Result|Set-Content (Join-Path $Out "host-$n$sfx.stderr.txt")}catch{}}
   }
   if($st -ne 'ok'){$status="frame $k`: $st"}
  }
  $results+=[ordered]@{run=$i;status=$status}
 }
}finally{
 ConvertTo-Json -InputObject @($results)|Set-Content (Join-Path $Out 'done.json')
}
