# Runs inside the interactive session. Per run: launch host, find its window, push to background w/o activation, wait for the first present (settled digest), PrintWindow(flags 3), kill.
# -Frames N (F1 manual clock; env SWIFTRIGHT_CLOCK holds the N clock times): the run launches the host once per frame k with SWIFTRIGHT_FRAME=k and writes native-NN-fKK.png / host-NN-fKK.stdout.txt.
param([Parameter(Mandatory)][string]$Exe,[Parameter(Mandatory)][string]$Out,[int]$Runs=1,[string]$Owner='swiftright-87',[switch]$Shared,[int]$Frames=0)
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
    while(-not $settled){
     if([DateTime]::UtcNow -gt $settleStart.AddSeconds(20)){throw 'first present not observed within 20 s'}
     Start-Sleep -Milliseconds 200
     $dg=[PairNative]::Grab($h);$digests+=,$dg
     if($dg -ne '' -and $dg -eq $prevD){$same++}else{$same=0}
     $prevD=$dg;if($same -ge 2){$settled=$true;$stableD=$dg}
    }
    $differs=@();for($q=0;$q -lt $digests.Count;$q++){ if($digests[$q] -ne $stableD){ $differs+=("poll$($q+1)=" + $digests[$q]) } }
    if($differs.Count -gt 0){ Write-Warning ("settle $n$sfx : " + $differs.Count + " of " + $digests.Count + " PrintWindow poll(s) differ from the stable digest: " + ($differs -join ' ')) }
    Set-Content -Path (Join-Path $Out "settle-$n$sfx.txt") -Value ("settled polls=" + $digests.Count + " ms=" + [int]([DateTime]::UtcNow-$settleStart).TotalMilliseconds + " stable=$stableD differing=" + $differs.Count + $(if($differs.Count){' ' + ($differs -join ' ')}else{''}))
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
