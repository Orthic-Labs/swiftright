# Runs inside the interactive session. Per run: launch host, find its window, push to background w/o activation, PrintWindow(flags 3), kill.
param([Parameter(Mandatory)][string]$Exe,[Parameter(Mandatory)][string]$Out,[int]$Runs=1,[string]$Owner='swiftright-87',[switch]$Shared)
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
  $n='{0:00}' -f $i;$p=$null;$status='failed'
  try{
   if(-not $Shared -and (Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $Owner){throw 'lock ownership lost'}
   $si=[Diagnostics.ProcessStartInfo]::new($Exe);$si.Arguments='--factory-capture-lease-seconds=40';$si.UseShellExecute=$false;$si.CreateNoWindow=$true
   $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
   $p=[Diagnostics.Process]::Start($si);$so=$p.StandardOutput.ReadToEndAsync();$se=$p.StandardError.ReadToEndAsync()
   $deadline=[DateTime]::UtcNow.AddSeconds(30)
   do{Start-Sleep -Milliseconds 100;$p.Refresh();if($p.HasExited){throw "host exited early code=$($p.ExitCode)"};if([DateTime]::UtcNow -gt $deadline){throw 'window deadline'}}while($p.MainWindowHandle -eq [IntPtr]::Zero)
   $h=$p.MainWindowHandle
   if(-not [PairNative]::SetWindowPos($h,[IntPtr]::new(1),0,0,0,0,0x0013)){throw 'SetWindowPos failed'}   # HWND_BOTTOM, NOSIZE|NOMOVE|NOACTIVATE
   Start-Sleep -Milliseconds 500
   $r=[PairNative]::Shot($h,(Join-Path $Out "native-$n.png"));if($r -ne 'ok'){throw $r};$status='ok'
  }catch{$status=[string]$_}
  finally{
   if($p){try{if(-not $p.HasExited){$p.Kill()};[void]$p.WaitForExit(10000)}catch{}
    try{[void]$so.Wait(5000);$so.Result|Set-Content (Join-Path $Out "host-$n.stdout.txt");$se.Result|Set-Content (Join-Path $Out "host-$n.stderr.txt")}catch{}}
  }
  $results+=[ordered]@{run=$i;status=$status}
 }
}finally{
 ConvertTo-Json -InputObject @($results)|Set-Content (Join-Path $Out 'done.json')
}
