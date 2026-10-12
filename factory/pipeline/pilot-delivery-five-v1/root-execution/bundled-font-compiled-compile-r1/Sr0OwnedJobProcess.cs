using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;

// Small shared boundary for tuple12 owned Windows processes.  Callers retain
// every kernel handle until terminal, stream-drain, and job-active proofs pass.
public static class Sr0OwnedJobProcess
{
    public const uint CreateSuspendedFlag = 0x00000004;
    public const uint CreateNoWindow = 0x08000000;
    public const uint CreateUnicodeEnvironment = 0x00000400;
    public const uint HandleFlagInherit = 0x00000001;
    public const uint StartfUseStdHandles = 0x00000100;
    public const uint Infinite = 0xffffffff;
    public const uint WaitObject0 = 0;
    public const uint WaitTimeout = 0x00000102;
    public const int JobObjectExtendedLimitInformation = 9;
    public const int JobObjectBasicAccountingInformation = 1;
    public const int JobObjectLimitFlagsInformation = 2;
    public const uint JobObjectLimitKillOnJobClose = 0x00002000;
    public const uint JobObjectLimitJobMemory = 0x00000200;
    public const uint JobObjectLimitProcessMemory = 0x00000100;

    [StructLayout(LayoutKind.Sequential)]
    public struct BasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ExtendedLimitInformation
    {
        public BasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct BasicAccountingInformation
    {
        public long TotalUserTime;
        public long TotalKernelTime;
        public long ThisPeriodTotalUserTime;
        public long ThisPeriodTotalKernelTime;
        public uint TotalPageFaultCount;
        public uint TotalProcesses;
        public uint ActiveProcesses;
        public uint TotalTerminatedProcesses;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SecurityAttributes
    {
        public int Length;
        public IntPtr SecurityDescriptor;
        public int InheritHandle;
    }

    // STARTUPINFO is 104 bytes on x64.  Keep this exact field order/alignment;
    // passing IntPtr.Zero here makes CreateProcess reject redirected handles.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Cb;
        public IntPtr Reserved;
        public IntPtr Desktop;
        public IntPtr Title;
        public int X;
        public int Y;
        public int XSize;
        public int YSize;
        public int XCountChars;
        public int YCountChars;
        public int FillAttribute;
        public int Flags;
        public short ShowWindow;
        public short Reserved2;
        public IntPtr Reserved3;
        public IntPtr StdInput;
        public IntPtr StdOutput;
        public IntPtr StdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr Process;
        public IntPtr Thread;
        public uint ProcessId;
        public uint ThreadId;
    }

    private static readonly ConcurrentDictionary<IntPtr, bool> Created =
        new ConcurrentDictionary<IntPtr, bool>();

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr job, int infoClass, ref ExtendedLimitInformation info, uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool QueryInformationJobObject(
        IntPtr job, int infoClass, IntPtr info, uint length, out uint returnedLength);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "AssignProcessToJobObject")]
    private static extern bool AssignProcessToJobObjectNative(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "TerminateJobObject")]
    private static extern bool TerminateJobObjectNative(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "TerminateProcess")]
    private static extern bool TerminateProcessNative(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "WaitForSingleObject")]
    private static extern uint WaitForSingleObjectNative(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "GetExitCodeProcess")]
    private static extern bool GetExitCodeProcessNative(IntPtr process, out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CreatePipe(
        out IntPtr readHandle, out IntPtr writeHandle,
        ref SecurityAttributes attributes, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetHandleInformation(
        IntPtr handle, uint mask, uint flags);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcess(
        string applicationName, StringBuilder commandLine,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles,
        uint creationFlags, IntPtr environment, string currentDirectory,
        ref StartupInfo startupInfo, out ProcessInformation processInformation);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "ResumeThread")]
    private static extern uint ResumeThreadNative(IntPtr thread);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "CloseHandle")]
    private static extern bool CloseHandleNative(IntPtr handle);

    public static IntPtr CreateJob()
    {
        return CreateJobObject(IntPtr.Zero, null);
    }

    public static bool ConfigureJob(IntPtr job, ulong memoryBytes)
    {
        return ConfigureJobWithFlags(
            job, JobObjectLimitKillOnJobClose | JobObjectLimitJobMemory,
            memoryBytes);
    }

    public static bool ConfigureJobWithFlags(
        IntPtr job, uint limitFlags, ulong memoryBytes)
    {
        var info = new ExtendedLimitInformation();
        info.BasicLimitInformation.LimitFlags = limitFlags;
        if ((limitFlags & JobObjectLimitProcessMemory) != 0)
            info.ProcessMemoryLimit = (UIntPtr)memoryBytes;
        info.JobMemoryLimit = (UIntPtr)memoryBytes;
        return SetInformationJobObject(
            job, JobObjectExtendedLimitInformation, ref info,
            (uint)Marshal.SizeOf(typeof(ExtendedLimitInformation)));
    }

    public static bool ReadJobFlags(IntPtr job, out uint flags)
    {
        flags = 0;
        int size = Marshal.SizeOf(typeof(ExtendedLimitInformation));
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            uint returned;
            if (!QueryInformationJobObject(
                    job, JobObjectExtendedLimitInformation, buffer,
                    (uint)size, out returned)) return false;
            var info = (ExtendedLimitInformation)Marshal.PtrToStructure(
                buffer, typeof(ExtendedLimitInformation));
            flags = info.BasicLimitInformation.LimitFlags;
            return returned >= (uint)size;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static bool ReadActiveProcessCount(IntPtr job, out uint active)
    {
        active = 0;
        int size = Marshal.SizeOf(typeof(BasicAccountingInformation));
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            uint returned;
            if (!QueryInformationJobObject(
                    job, JobObjectBasicAccountingInformation, buffer,
                    (uint)size, out returned)) return false;
            var info = (BasicAccountingInformation)Marshal.PtrToStructure(
                buffer, typeof(BasicAccountingInformation));
            active = info.ActiveProcesses;
            return returned >= (uint)size;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static string QuoteWindowsArgument(string value)
    {
        if (value == null) throw new ArgumentNullException("value");
        var result = new StringBuilder(value.Length + 2);
        result.Append('"');
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"')
            {
                result.Append('\\', slashes * 2 + 1);
                result.Append('"');
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }

    public static string BuildCommandLine(string application, string arguments)
    {
        return QuoteWindowsArgument(application) +
            (String.IsNullOrEmpty(arguments) ? String.Empty : " " + arguments);
    }

    public static bool CreateSuspended(
        string application, string commandLine, string currentDirectory,
        out IntPtr process, out IntPtr thread,
        out IntPtr stdoutRead, out IntPtr stderrRead, out uint processId)
    {
        process = IntPtr.Zero;
        thread = IntPtr.Zero;
        stdoutRead = IntPtr.Zero;
        stderrRead = IntPtr.Zero;
        processId = 0;
        IntPtr stdoutWrite = IntPtr.Zero;
        IntPtr stderrWrite = IntPtr.Zero;
        var attributes = new SecurityAttributes();
        attributes.Length = Marshal.SizeOf(typeof(SecurityAttributes));
        attributes.InheritHandle = 1;
        try
        {
            if (!CreatePipe(out stdoutRead, out stdoutWrite, ref attributes, 0) ||
                !CreatePipe(out stderrRead, out stderrWrite, ref attributes, 0) ||
                !SetHandleInformation(stdoutRead, HandleFlagInherit, 0) ||
                !SetHandleInformation(stderrRead, HandleFlagInherit, 0)) return false;

            var startup = new StartupInfo();
            startup.Cb = Marshal.SizeOf(typeof(StartupInfo));
            startup.Flags = (int)StartfUseStdHandles;
            startup.StdOutput = stdoutWrite;
            startup.StdError = stderrWrite;
            var info = new ProcessInformation();
            var command = new StringBuilder(commandLine);
            bool created = CreateProcess(
                application, command, IntPtr.Zero, IntPtr.Zero, true,
                CreateSuspendedFlag | CreateNoWindow | CreateUnicodeEnvironment,
                IntPtr.Zero, currentDirectory, ref startup, out info);
            if (!created) return false;
            process = info.Process;
            thread = info.Thread;
            processId = info.ProcessId;
            Created[process] = false;
            return true;
        }
        finally
        {
            if (stdoutWrite != IntPtr.Zero) CloseHandleNative(stdoutWrite);
            if (stderrWrite != IntPtr.Zero) CloseHandleNative(stderrWrite);
            if (process == IntPtr.Zero)
            {
                if (stdoutRead != IntPtr.Zero) CloseHandleNative(stdoutRead);
                if (stderrRead != IntPtr.Zero) CloseHandleNative(stderrRead);
                stdoutRead = IntPtr.Zero;
                stderrRead = IntPtr.Zero;
            }
        }
    }

    public static bool AssignProcessToJobObject(IntPtr job, IntPtr process)
    {
        bool assigned = AssignProcessToJobObjectNative(job, process);
        if (assigned) Created[process] = true;
        return assigned;
    }

    // ResumeThread is deliberately guarded by the helper's real assignment map.
    public static uint ResumeThread(IntPtr thread, IntPtr process)
    {
        bool assigned;
        if (!Created.TryGetValue(process, out assigned) || !assigned)
            throw new InvalidOperationException("resume refused before job assignment");
        return ResumeThreadNative(thread);
    }

    public static uint WaitForSingleObject(IntPtr handle, uint milliseconds)
    {
        return WaitForSingleObjectNative(handle, milliseconds);
    }

    public static bool GetExitCodeProcess(IntPtr process, out uint exitCode)
    {
        return GetExitCodeProcessNative(process, out exitCode);
    }

    public static bool TerminateJobObject(IntPtr job, uint exitCode)
    {
        return TerminateJobObjectNative(job, exitCode);
    }

    public static bool TerminateProcess(IntPtr process, uint exitCode)
    {
        return TerminateProcessNative(process, exitCode);
    }

    public static bool CloseHandle(IntPtr handle)
    {
        bool ignored;
        Created.TryRemove(handle, out ignored);
        return CloseHandleNative(handle);
    }
}
