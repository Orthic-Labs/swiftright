using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public sealed class Sr0OwnedJobProcess : IDisposable
{
    public const uint JobMemoryOnlyFlags = 0x200;
    private const int JobObjectBasicAccountingInformation = 1;
    private const int JobObjectExtendedLimitInformation = 9;
    private IntPtr job;
    private bool disposed;

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimitInformation { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimitInformation { public BasicLimitInformation BasicLimitInformation; public IoCounters IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicAccountingInformation { public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime; public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses; }

    public sealed class Snapshot { public ulong JobMemoryLimitBytes, PeakJobMemoryUsedBytes; public uint LimitFlags, ActiveProcessCount; }

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr handle, int infoClass, ref ExtendedLimitInformation info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool QueryInformationJobObject(IntPtr handle, int infoClass, ref ExtendedLimitInformation info, uint length, out uint returned);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool QueryInformationJobObject(IntPtr handle, int infoClass, ref BasicAccountingInformation info, uint length, out uint returned);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr jobHandle, IntPtr processHandle);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();

    private Sr0OwnedJobProcess(IntPtr value) { job=value; }
    private static void Fail(string message) { throw new InvalidOperationException(message + " win32=" + Marshal.GetLastWin32Error()); }
    public static void ValidateFlagsForControl(uint requestedFlags) { if (requestedFlags != JobMemoryOnlyFlags) throw new InvalidOperationException("Only JOB_OBJECT_LIMIT_JOB_MEMORY is admitted"); }
    public static void RequireOnlyCurrent(Snapshot snapshot) { if (snapshot == null || snapshot.ActiveProcessCount != 1) throw new InvalidOperationException("Live child process remains in memory job"); }

    public static Sr0OwnedJobProcess CreateCurrentProcess(ulong budgetBytes)
    {
        if (budgetBytes != 1073741824UL) throw new ArgumentOutOfRangeException("budgetBytes", "Only exact 1GiB job budget is admitted");
        ValidateFlagsForControl(JobMemoryOnlyFlags);
        IntPtr handle=CreateJobObject(IntPtr.Zero, null); if (handle==IntPtr.Zero) Fail("CreateJobObject failed");
        var info=new ExtendedLimitInformation(); info.BasicLimitInformation.LimitFlags=JobMemoryOnlyFlags; info.JobMemoryLimit=new UIntPtr(budgetBytes);
        if (!SetInformationJobObject(handle, JobObjectExtendedLimitInformation, ref info, (uint)Marshal.SizeOf(typeof(ExtendedLimitInformation)))) { CloseHandle(handle); Fail("SetInformationJobObject failed"); }
        if (!AssignProcessToJobObject(handle, GetCurrentProcess())) { CloseHandle(handle); Fail("AssignProcessToJobObject failed"); }
        var owner=new Sr0OwnedJobProcess(handle); var proof=owner.QueryPeakJobMemory();
        if (proof.LimitFlags != JobMemoryOnlyFlags || proof.JobMemoryLimitBytes != budgetBytes || proof.PeakJobMemoryUsedBytes > budgetBytes || proof.ActiveProcessCount != 1) { owner.Dispose(); throw new InvalidOperationException("Initial job memory proof failed"); }
        return owner;
    }

    public Snapshot QueryPeakJobMemory()
    {
        if (disposed) throw new ObjectDisposedException("Sr0OwnedJobProcess");
        var ext=new ExtendedLimitInformation(); uint returned;
        uint extendedSize=(uint)Marshal.SizeOf(typeof(ExtendedLimitInformation));
        if (!QueryInformationJobObject(job, JobObjectExtendedLimitInformation, ref ext, extendedSize, out returned)) Fail("QueryPeakJobMemory extended query failed");
        if (returned < extendedSize) throw new InvalidOperationException("QueryPeakJobMemory extended byte proof short");
        var basic=new BasicAccountingInformation();
        uint basicSize=(uint)Marshal.SizeOf(typeof(BasicAccountingInformation));
        if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation, ref basic, basicSize, out returned)) Fail("QueryPeakJobMemory active query failed");
        if (returned < basicSize) throw new InvalidOperationException("QueryPeakJobMemory active byte proof short");
        ulong limit=ext.JobMemoryLimit.ToUInt64(), peak=ext.PeakJobMemoryUsed.ToUInt64();
        if (ext.BasicLimitInformation.LimitFlags != JobMemoryOnlyFlags || peak > limit) throw new InvalidOperationException("QueryPeakJobMemory cap proof failed");
        return new Snapshot { JobMemoryLimitBytes=limit, PeakJobMemoryUsedBytes=peak, LimitFlags=ext.BasicLimitInformation.LimitFlags, ActiveProcessCount=basic.ActiveProcesses };
    }

    public Snapshot WaitForOnlyCurrent(uint timeoutMilliseconds)
    {
        var timer=Stopwatch.StartNew(); Snapshot latest=QueryPeakJobMemory();
        while (latest.ActiveProcessCount != 1 && timer.ElapsedMilliseconds < timeoutMilliseconds) { Thread.Sleep(25); latest=QueryPeakJobMemory(); }
        return latest;
    }

    public void Dispose() { if (!disposed) { disposed=true; if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; } } GC.SuppressFinalize(this); }
    ~Sr0OwnedJobProcess() { Dispose(); }
}
