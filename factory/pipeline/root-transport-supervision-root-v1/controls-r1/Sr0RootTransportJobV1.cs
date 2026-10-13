using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

// Root transport owner: current process + descendants, exactly 256 MiB, memory-only.
// Kill-on-close is intentionally absent; callers prove quiescence before disposal.
public sealed class Sr0RootTransportJobV1 : IDisposable
{
    public const uint JobMemoryOnlyFlags = 0x200;
    public const ulong BudgetBytes = 268435456UL;
    private const int JobObjectBasicAccountingInformation = 1;
    private const int JobObjectBasicProcessIdList = 3;
    private const int JobObjectExtendedLimitInformation = 9;
    private const uint ProcessTerminate = 0x0001;
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint Synchronize = 0x00100000;
    private const uint ErrorInsufficientBuffer = 122;
    private IntPtr job;
    private bool disposed;

    [StructLayout(LayoutKind.Sequential)] private struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)] private struct BasicLimitInformation { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimitInformation { public BasicLimitInformation BasicLimitInformation; public IoCounters IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    [StructLayout(LayoutKind.Sequential)] private struct BasicAccountingInformation { public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime; public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses; }
    public sealed class Snapshot { public ulong LimitBytes, PeakBytes; public uint LimitFlags, ActiveCount; }
    public sealed class CleanupSnapshot { public uint BeforeCount, AfterCount, TerminatedCount, OpenFailedCount; public bool Attempted, SelfOnly; }

    [DllImport("kernel32.dll", EntryPoint="CreateJobObjectW", SetLastError=true, CharSet=CharSet.Unicode)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", EntryPoint="SetInformationJobObject", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr handle, int infoClass, ref ExtendedLimitInformation info, uint length);
    [DllImport("kernel32.dll", EntryPoint="QueryInformationJobObject", SetLastError=true)] private static extern bool QueryInformationJobObject(IntPtr handle, int infoClass, IntPtr info, uint length, out uint returned);
    [DllImport("kernel32.dll", EntryPoint="QueryInformationJobObject", SetLastError=true)] private static extern bool QueryInformationJobObjectExtended(IntPtr handle, int infoClass, ref ExtendedLimitInformation info, uint length, out uint returned);
    [DllImport("kernel32.dll", EntryPoint="QueryInformationJobObject", SetLastError=true)] private static extern bool QueryInformationJobObjectAccounting(IntPtr handle, int infoClass, ref BasicAccountingInformation info, uint length, out uint returned);
    [DllImport("kernel32.dll", EntryPoint="AssignProcessToJobObject", SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr jobHandle, IntPtr processHandle);
    [DllImport("kernel32.dll", EntryPoint="OpenProcess", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", EntryPoint="IsProcessInJob", SetLastError=true)] private static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
    [DllImport("kernel32.dll", EntryPoint="TerminateProcess", SetLastError=true)] private static extern bool TerminateProcess(IntPtr process, uint exitCode);
    [DllImport("kernel32.dll", EntryPoint="WaitForSingleObject", SetLastError=true)] private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", EntryPoint="GetExitCodeProcess", SetLastError=true)] private static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", EntryPoint="CloseHandle", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", EntryPoint="GetCurrentProcess", SetLastError=true)] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", EntryPoint="GetCurrentProcessId", SetLastError=true)] private static extern uint GetCurrentProcessId();

    private Sr0RootTransportJobV1(IntPtr value) { job=value; }
    private static void Fail(string message) { throw new InvalidOperationException(message + " win32=" + Marshal.GetLastWin32Error()); }
    public static long SignedDword(uint value) { return unchecked((int)value); }
    public static bool Terminal(IntPtr process, out uint code) { code=259u; if (process==IntPtr.Zero) return false; if (WaitForSingleObject(process,0u)!=0u) return false; if (!GetExitCodeProcess(process,out code)) return false; return code!=259u; }
    public static void RequireMemoryOnly(Snapshot s) { if (s == null || s.LimitFlags != JobMemoryOnlyFlags || s.LimitBytes != BudgetBytes || s.PeakBytes > s.LimitBytes) throw new InvalidOperationException("root transport job proof failed"); }

    public static Sr0RootTransportJobV1 CreateCurrentProcess()
    {
        IntPtr handle=CreateJobObject(IntPtr.Zero, null); if (handle==IntPtr.Zero) Fail("CreateJobObject failed");
        var info=new ExtendedLimitInformation(); info.BasicLimitInformation.LimitFlags=JobMemoryOnlyFlags; info.JobMemoryLimit=new UIntPtr(BudgetBytes);
        if (!SetInformationJobObject(handle, JobObjectExtendedLimitInformation, ref info, (uint)Marshal.SizeOf(typeof(ExtendedLimitInformation)))) { CloseHandle(handle); Fail("SetInformationJobObject failed"); }
        if (!AssignProcessToJobObject(handle, GetCurrentProcess())) { CloseHandle(handle); Fail("AssignProcessToJobObject failed"); }
        var owner=new Sr0RootTransportJobV1(handle); var proof=owner.Query(); RequireMemoryOnly(proof); if (proof.ActiveCount != 1) { owner.Dispose(); throw new InvalidOperationException("root transport initial active proof failed"); } return owner;
    }

    public Snapshot Query()
    {
        if (disposed) throw new ObjectDisposedException("Sr0RootTransportJobV1");
        var ext=new ExtendedLimitInformation(); uint returned; uint extSize=(uint)Marshal.SizeOf(typeof(ExtendedLimitInformation));
        if (!QueryInformationJobObjectExtended(job, JobObjectExtendedLimitInformation, ref ext, extSize, out returned)) Fail("root transport extended query failed"); if (returned < extSize) throw new InvalidOperationException("root transport extended proof short");
        var basic=new BasicAccountingInformation(); uint basicSize=(uint)Marshal.SizeOf(typeof(BasicAccountingInformation));
        if (!QueryInformationJobObjectAccounting(job, JobObjectBasicAccountingInformation, ref basic, basicSize, out returned)) Fail("root transport active query failed"); if (returned < basicSize) throw new InvalidOperationException("root transport active proof short");
        ulong limit=ext.JobMemoryLimit.ToUInt64(), peak=ext.PeakJobMemoryUsed.ToUInt64(); if (ext.BasicLimitInformation.LimitFlags != JobMemoryOnlyFlags || limit != BudgetBytes || peak > limit) throw new InvalidOperationException("root transport cap proof failed");
        return new Snapshot { LimitBytes=limit, PeakBytes=peak, LimitFlags=ext.BasicLimitInformation.LimitFlags, ActiveCount=basic.ActiveProcesses };
    }

    public Snapshot WaitForOnlyCurrent(uint timeoutMilliseconds)
    {
        var timer=Stopwatch.StartNew(); Snapshot latest=Query(); while (latest.ActiveCount != 1 && timer.ElapsedMilliseconds < timeoutMilliseconds) { Thread.Sleep(25); latest=Query(); } return latest;
    }

    private uint[] QueryOwnedProcessIds()
    {
        int size=4096;
        while (size <= 1048576)
        {
            IntPtr buffer=Marshal.AllocHGlobal(size);
            try
            {
                uint returned;
                if (QueryInformationJobObject(job, JobObjectBasicProcessIdList, buffer, (uint)size, out returned))
                {
                    uint assigned=(uint)Marshal.ReadInt32(buffer, 0), listed=(uint)Marshal.ReadInt32(buffer, 4); int max=(size-8)/IntPtr.Size; if (listed > (uint)max || listed > Int32.MaxValue) throw new InvalidOperationException("root transport process list exceeds bounded buffer"); uint expected=8u+(listed*(uint)IntPtr.Size); if (returned < expected || assigned != listed) throw new InvalidOperationException("root transport process list count mismatch"); var ids=new uint[(int)listed]; var seen=new HashSet<uint>(); for (int i=0;i<ids.Length;i++) { ids[i]=(uint)Marshal.ReadIntPtr(buffer,8+(i*IntPtr.Size)).ToInt64(); if(ids[i]==0 || !seen.Add(ids[i])) throw new InvalidOperationException("root transport process identity incomplete"); } return ids;
                }
                if ((uint)Marshal.GetLastWin32Error() != ErrorInsufficientBuffer) Fail("root transport process list query failed");
            }
            finally { Marshal.FreeHGlobal(buffer); }
            size*=2;
        }
        throw new InvalidOperationException("root transport process list exceeded bounded query");
    }

    public CleanupSnapshot TerminateOwnedChildren(uint exitCode, uint timeoutMilliseconds)
    {
        uint self=GetCurrentProcessId(), terminated=0, openFailed=0, before=(uint)QueryOwnedProcessIds().Length, after=before; bool attempted=false; var timer=Stopwatch.StartNew();
        while(timer.ElapsedMilliseconds < timeoutMilliseconds)
        {
            var ids=QueryOwnedProcessIds(); bool onlySelf=true; foreach(uint pid in ids) if(pid != self){onlySelf=false;break;} if(onlySelf){after=(uint)ids.Length;break;}
            foreach(uint pid in ids){if(pid==self)continue;IntPtr child=OpenProcess(ProcessTerminate|ProcessQueryLimitedInformation|Synchronize,false,pid);if(child==IntPtr.Zero){openFailed++;continue;}try{bool member;if(!IsProcessInJob(child,job,out member)||!member)continue;attempted=true;if(TerminateProcess(child,exitCode))terminated++;WaitForSingleObject(child,1000);}finally{CloseHandle(child);}}
            Thread.Sleep(25); after=(uint)QueryOwnedProcessIds().Length;
        }
        var finalIds=QueryOwnedProcessIds(); after=(uint)finalIds.Length; bool selfOnly=true; foreach(uint pid in finalIds) if(pid != self){selfOnly=false;break;} return new CleanupSnapshot{BeforeCount=before,AfterCount=after,TerminatedCount=terminated,OpenFailedCount=openFailed,Attempted=attempted,SelfOnly=selfOnly};
    }

    public void Dispose(){if(!disposed){disposed=true;if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}}GC.SuppressFinalize(this);} ~Sr0RootTransportJobV1(){Dispose();}
}
