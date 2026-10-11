using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public class FactoryStreamChild {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string reserved, desktop, title; public int x,y,xs,ys,xc,yc,fill,flags; public short show,cb2; public IntPtr reserved2,input,output,error; }
 [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr process,thread; public int pid,tid; }
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string application,string command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr environment,string directory,ref SI start,out PI process);
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int kind);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 public static int Main(string[] args) {
  if(args[0]=="volume") { byte[] bytes=new byte[384*1024]; for(int i=0;i<bytes.Length;i++)bytes[i]=(byte)(33+i%90); using(Stream s=Console.OpenStandardOutput()){s.Write(bytes,0,bytes.Length);s.Flush();} return 0; }
  if(args[0]=="holder") { File.WriteAllText(args[2],"ready"); DateTime end=DateTime.UtcNow.AddSeconds(15); while(!File.Exists(args[1])&&DateTime.UtcNow<end)Thread.Sleep(20); return File.Exists(args[1])?0:9; }
  if(args[0]=="inherit") {
   SI start=new SI();start.cb=Marshal.SizeOf(typeof(SI));start.flags=0x100;start.input=GetStdHandle(-10);start.output=GetStdHandle(-11);start.error=GetStdHandle(-12);
   PI p;string exe=System.Reflection.Assembly.GetExecutingAssembly().Location;
   string command="\""+exe+"\" holder \""+args[1]+"\" \""+args[2]+"\"";
   if(!CreateProcess(exe,command,IntPtr.Zero,IntPtr.Zero,true,0x08000000,IntPtr.Zero,null,ref start,out p))return 8;
   byte[] bytes=new byte[64*1024];for(int i=0;i<bytes.Length;i++)bytes[i]=(byte)(33+i%90);Stream stdout=Console.OpenStandardOutput();stdout.Write(bytes,0,bytes.Length);stdout.Flush();File.WriteAllText(args[3],p.pid.ToString());CloseHandle(p.thread);CloseHandle(p.process);return 0;
  }
  return 7;
 }
}
