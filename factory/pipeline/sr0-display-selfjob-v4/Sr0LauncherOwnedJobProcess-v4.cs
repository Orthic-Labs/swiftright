using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

// Launcher-only outer job owner. It never terminates current launcher process.
public sealed class Sr0LauncherOwnedJobProcessV4 : IDisposable
{
    public const uint JobMemoryOnlyFlags = 0x200;
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
    public sealed class Snapshot { public ulong JobMemoryLimitBytes, PeakJobMemoryUsedBytes; public uint LimitFlags, ActiveProcessCount; }
    public sealed class CleanupSnapshot { public uint SelfPid, BeforeCount, AfterCount, TerminatedCount, OpenFailedCount, ForeignSkippedCount; public bool Attempted, AllTerminal, SelfOnly; }

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

    private Sr0LauncherOwnedJobProcessV4(IntPtr value) { job=value; }
    private static void Fail(string message) { throw new InvalidOperationException(message + " win32=" + Marshal.GetLastWin32Error()); }
    public static void ValidateFlagsForControl(uint requestedFlags) { if (requestedFlags != JobMemoryOnlyFlags) throw new InvalidOperationException("Only JOB_OBJECT_LIMIT_JOB_MEMORY is admitted"); }
    public static void RequireOnlyCurrent(Snapshot snapshot) { if (snapshot == null || snapshot.ActiveProcessCount != 1) throw new InvalidOperationException("Live owned child process remains in launcher job"); }

    public static Sr0LauncherOwnedJobProcessV4 CreateCurrentProcess(ulong budgetBytes)
    {
        if (budgetBytes != 1073741824UL) throw new ArgumentOutOfRangeException("budgetBytes", "Only exact 1GiB job budget is admitted");
        ValidateFlagsForControl(JobMemoryOnlyFlags);
        IntPtr handle=CreateJobObject(IntPtr.Zero, null); if (handle==IntPtr.Zero) Fail("CreateJobObject failed");
        var info=new ExtendedLimitInformation(); info.BasicLimitInformation.LimitFlags=JobMemoryOnlyFlags; info.JobMemoryLimit=new UIntPtr(budgetBytes);
        if (!SetInformationJobObject(handle, JobObjectExtendedLimitInformation, ref info, (uint)Marshal.SizeOf(typeof(ExtendedLimitInformation)))) { CloseHandle(handle); Fail("SetInformationJobObject failed"); }
        if (!AssignProcessToJobObject(handle, GetCurrentProcess())) { CloseHandle(handle); Fail("AssignProcessToJobObject failed"); }
        var owner=new Sr0LauncherOwnedJobProcessV4(handle); var proof=owner.QueryPeakJobMemory();
        if (proof.LimitFlags != JobMemoryOnlyFlags || proof.JobMemoryLimitBytes != budgetBytes || proof.PeakJobMemoryUsedBytes > budgetBytes || proof.ActiveProcessCount != 1) { owner.Dispose(); throw new InvalidOperationException("Initial launcher job memory proof failed"); }
        return owner;
    }

    public Snapshot QueryPeakJobMemory()
    {
        if (disposed) throw new ObjectDisposedException("Sr0LauncherOwnedJobProcessV4");
        var ext=new ExtendedLimitInformation(); uint returned; uint extSize=(uint)Marshal.SizeOf(typeof(ExtendedLimitInformation));
        if (!QueryInformationJobObjectExtended(job, JobObjectExtendedLimitInformation, ref ext, extSize, out returned)) Fail("launcher extended query failed");
        if (returned < extSize) throw new InvalidOperationException("launcher extended byte proof short");
        var basic=new BasicAccountingInformation(); uint basicSize=(uint)Marshal.SizeOf(typeof(BasicAccountingInformation));
        if (!QueryInformationJobObjectAccounting(job, JobObjectBasicAccountingInformation, ref basic, basicSize, out returned)) Fail("launcher active query failed");
        if (returned < basicSize) throw new InvalidOperationException("launcher active byte proof short");
        ulong limit=ext.JobMemoryLimit.ToUInt64(), peak=ext.PeakJobMemoryUsed.ToUInt64();
        if (ext.BasicLimitInformation.LimitFlags != JobMemoryOnlyFlags || limit == 0) throw new InvalidOperationException("launcher cap configuration proof failed");
        return new Snapshot { JobMemoryLimitBytes=limit, PeakJobMemoryUsedBytes=peak, LimitFlags=ext.BasicLimitInformation.LimitFlags, ActiveProcessCount=basic.ActiveProcesses };
    }

    public Snapshot WaitForOnlyCurrent(uint timeoutMilliseconds)
    {
        var timer=Stopwatch.StartNew(); Snapshot latest=QueryPeakJobMemory();
        while (latest.ActiveProcessCount != 1 && timer.ElapsedMilliseconds < timeoutMilliseconds) { Thread.Sleep(25); latest=QueryPeakJobMemory(); }
        return latest;
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
                    uint assigned=(uint)Marshal.ReadInt32(buffer, 0); uint listed=(uint)Marshal.ReadInt32(buffer, 4); int max=(size-8)/IntPtr.Size; if (listed > (uint)max) throw new InvalidOperationException("launcher process list count exceeds bounded buffer"); uint expected=(uint)(8+(listed*IntPtr.Size)); if (returned < expected || assigned != listed) throw new InvalidOperationException("launcher process list count/length mismatch"); int count=(int)listed; var ids=new uint[count];
                    var seen=new HashSet<uint>(); for (int i=0;i<count;i++) { ids[i]=(uint)Marshal.ReadIntPtr(buffer, 8+(i*IntPtr.Size)).ToInt64(); if(ids[i]==0 || !seen.Add(ids[i])) throw new InvalidOperationException("launcher process list identity is incomplete"); }
                    return ids;
                }
                if ((uint)Marshal.GetLastWin32Error() != ErrorInsufficientBuffer) Fail("launcher process list query failed");
            }
            finally { Marshal.FreeHGlobal(buffer); }
            size*=2;
        }
        throw new InvalidOperationException("launcher process list exceeded bounded query size");
    }

    public bool IsOwnedHandle(IntPtr processHandle)
    {
        if (processHandle == IntPtr.Zero) return false; bool member; return IsProcessInJob(processHandle, job, out member) && member;
    }

    // Terminates only current job members other than this launcher, then proves active count.
    public CleanupSnapshot TerminateOwnedChildren(uint exitCode, uint timeoutMilliseconds)
    {
        uint self=GetCurrentProcessId(); uint[] before=QueryOwnedProcessIds(); uint terminated=0, openFailed=0, foreignSkipped=0; bool attempted=false;
        var timer=Stopwatch.StartNew(); uint[] after=before;
        while (timer.ElapsedMilliseconds < timeoutMilliseconds)
        {
            after=QueryOwnedProcessIds(); bool onlySelf=true; foreach(uint pid in after) if(pid != self) { onlySelf=false; break; }
            if (onlySelf) break;
            foreach(uint pid in after)
            {
                if (pid == self) continue;
                IntPtr child=OpenProcess(ProcessTerminate|ProcessQueryLimitedInformation|Synchronize, false, pid);
                if (child==IntPtr.Zero) { openFailed++; continue; }
                try
                {
                    bool member; if (!IsProcessInJob(child, job, out member) || !member) { foreignSkipped++; continue; }
                    attempted=true; if (TerminateProcess(child, exitCode)) terminated++; int wait=(int)Math.Max(0L, Math.Min(1000L, (long)timeoutMilliseconds-timer.ElapsedMilliseconds)); WaitForSingleObject(child, (uint)wait); uint ignored; GetExitCodeProcess(child, out ignored);
                }
                finally { CloseHandle(child); }
            }
            Thread.Sleep(25);
        }
        after=QueryOwnedProcessIds();
        bool selfOnly=true; foreach(uint pid in after) if(pid != self) { selfOnly=false; break; }
        return new CleanupSnapshot { SelfPid=self, BeforeCount=(uint)before.Length, AfterCount=(uint)after.Length, TerminatedCount=terminated, OpenFailedCount=openFailed, ForeignSkippedCount=foreignSkipped, Attempted=attempted, AllTerminal=selfOnly, SelfOnly=selfOnly };
    }

    public void Dispose() { if (!disposed) { disposed=true; if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; } } GC.SuppressFinalize(this); }
    ~Sr0LauncherOwnedJobProcessV4() { Dispose(); }
}
