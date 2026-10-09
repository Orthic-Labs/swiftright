// SR0 lane R9: native-interaction helpers (C# 5, compiled by Windows PowerShell 5.1 Add-Type).
// Nothing here runs at load time. Input functions are only called by the gated drivers in native-common.ps1.
// Input policy: keys are sent as virtual keys (wVk + scan code). KEYEVENTF_UNICODE (VK_PACKET) is never used, because
// Unicode packets bypass the IME (probes/sr0-d/ime-text-node/RESULT.md).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;

namespace SRN {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }

  public sealed class WinInfo {
    public long Hwnd; public uint Pid; public string Cls; public string Title;
    public int L; public int T; public int R; public int B; public bool Visible; public long ExStyle;
  }

  public static class N {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool LockSetForegroundWindow(uint lockCode);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint map);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int n, IntPtr[] list);
    [DllImport("user32.dll")] public static extern short GetKeyState(int vk);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int index);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr h);
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr h);
    [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr h, IntPtr himc);
    [DllImport("uiautomationcore.dll")] public static extern bool UiaClientsAreListening();

    public const uint WM_INPUTLANGCHANGEREQUEST = 0x0050;
    public const uint WM_IME_CONTROL = 0x0283;
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x1;
    public const uint KEYEVENTF_KEYUP = 0x2;
    // IMC_* sub-commands of WM_IME_CONTROL (imm.h)
    public const int IMC_GETCONVERSIONMODE = 0x1;
    public const int IMC_SETCONVERSIONMODE = 0x2;
    public const int IMC_GETOPENSTATUS = 0x5;
    public const int IMC_SETOPENSTATUS = 0x6;

    public static int InputSize() { return Marshal.SizeOf(typeof(INPUT)); }

    static bool IsExtended(ushort vk) {
      switch (vk) {
        case 0x21: case 0x22: case 0x23: case 0x24: // PgUp PgDn End Home
        case 0x25: case 0x26: case 0x27: case 0x28: // arrows
        case 0x2D: case 0x2E: case 0x6F: case 0xA3: case 0xA5: return true; // Ins Del Divide RCtrl RAlt
        default: return false;
      }
    }

    /// One virtual-key event through SendInput (never KEYEVENTF_UNICODE). Returns true when the OS accepted it.
    public static bool SendVk(ushort vk, bool up) {
      INPUT[] a = new INPUT[1];
      a[0].type = 1; // INPUT_KEYBOARD
      a[0].u.ki.wVk = vk;
      a[0].u.ki.wScan = (ushort)MapVirtualKeyW(vk, 0);
      uint flags = 0;
      if (IsExtended(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
      if (up) flags |= KEYEVENTF_KEYUP;
      a[0].u.ki.dwFlags = flags;
      return SendInput(1, a, Marshal.SizeOf(typeof(INPUT))) == 1;
    }

    public static string ForegroundDescription() {
      IntPtr f = GetForegroundWindow();
      return Describe(f);
    }

    public static string Describe(IntPtr h) {
      if (h == IntPtr.Zero) return "hwnd=0";
      StringBuilder c = new StringBuilder(256); StringBuilder t = new StringBuilder(256);
      GetClassNameW(h, c, 256); GetWindowTextW(h, t, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      return "hwnd=" + h.ToInt64() + " pid=" + pid + " class=[" + c + "] title=[" + t + "]";
    }

    public static List<WinInfo> TopWindows() {
      List<WinInfo> res = new List<WinInfo>();
      EnumWindows(delegate(IntPtr h, IntPtr l) {
        WinInfo w = new WinInfo();
        w.Hwnd = h.ToInt64();
        uint pid; GetWindowThreadProcessId(h, out pid); w.Pid = pid;
        StringBuilder c = new StringBuilder(256); StringBuilder t = new StringBuilder(256);
        GetClassNameW(h, c, 256); GetWindowTextW(h, t, 256);
        w.Cls = c.ToString(); w.Title = t.ToString();
        RECT r; GetWindowRect(h, out r); w.L = r.Left; w.T = r.Top; w.R = r.Right; w.B = r.Bottom;
        w.Visible = IsWindowVisible(h);
        w.ExStyle = GetWindowLongW(h, -20);
        res.Add(w);
        return true;
      }, IntPtr.Zero);
      return res;
    }

    /// HKLs of the calling session whose language id is 0x0411 (Japanese).
    public static long[] JapaneseHkls() {
      int n = GetKeyboardLayoutList(0, null);
      IntPtr[] list = new IntPtr[n];
      GetKeyboardLayoutList(n, list);
      List<long> res = new List<long>();
      for (int i = 0; i < n; i++) { if ((list[i].ToInt64() & 0xFFFF) == 0x0411) res.Add(list[i].ToInt64()); }
      return res.ToArray();
    }

    public static long[] AllHkls() {
      int n = GetKeyboardLayoutList(0, null);
      IntPtr[] list = new IntPtr[n];
      GetKeyboardLayoutList(n, list);
      long[] res = new long[n];
      for (int i = 0; i < n; i++) res[i] = list[i].ToInt64();
      return res;
    }

    /// Keyboard layout of another thread (read only, works across processes).
    public static long LayoutOfThread(uint tid) { return GetKeyboardLayout(tid).ToInt64(); }

    /// WM_IME_CONTROL to the target thread's default IME window; the message is processed on the target's thread.
    /// Returns the IMC result, or -1 when the default IME window is missing or the call failed or timed out.
    public static long ImeControl(IntPtr hwnd, int cmd, long data) {
      IntPtr ime = ImmGetDefaultIMEWnd(hwnd);
      if (ime == IntPtr.Zero) return -1;
      IntPtr res;
      IntPtr ok = SendMessageTimeout(ime, WM_IME_CONTROL, new IntPtr(cmd), new IntPtr(data), SMTO_ABORTIFHUNG, 2000, out res);
      if (ok == IntPtr.Zero) return -1;
      return res.ToInt64();
    }

    /// Cross-process ImmGetContext. Expected to return 0 (an HIMC belongs to the owning thread); recorded as evidence.
    public static long ProbeImmContext(IntPtr hwnd) {
      IntPtr h = ImmGetContext(hwnd);
      long v = h.ToInt64();
      if (h != IntPtr.Zero) ImmReleaseContext(hwnd, h);
      return v;
    }
  }

  /// Collects the lines a child process writes (stdout or stderr) without needing the PowerShell pipeline.
  public sealed class LineTap {
    readonly List<string> lines = new List<string>();
    public LineTap(Process p, bool stderr) {
      if (stderr) p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { Add(e.Data); };
      else p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { Add(e.Data); };
    }
    void Add(string d) { if (d == null) return; lock (lines) { lines.Add(d); } }
    public string[] Snapshot() { lock (lines) { return lines.ToArray(); } }
    public int Count { get { lock (lines) { return lines.Count; } } }
  }

  /// UI Automation event listener for one window's process. Handlers run on UIA threads and only append to a list.
  public sealed class UiaTap {
    public sealed class Ev { public long Ms; public string Kind; public string Name; public string Type; public string Id; public string Extra; }
    readonly List<Ev> events = new List<Ev>();
    readonly Stopwatch sw = Stopwatch.StartNew();
    readonly AutomationElement root;
    readonly int pid;
    bool started;
    public UiaTap(AutomationElement root, int pid) { this.root = root; this.pid = pid; }
    public long Ms { get { return sw.ElapsedMilliseconds; } }

    void Add(string kind, AutomationElement e, string extra) {
      Ev ev = new Ev(); ev.Ms = sw.ElapsedMilliseconds; ev.Kind = kind; ev.Extra = extra;
      try {
        if (e != null) {
          if (pid != 0 && e.Current.ProcessId != pid) return;
          ev.Name = e.Current.Name; ev.Type = e.Current.ControlType.ProgrammaticName; ev.Id = e.Current.AutomationId;
        }
      } catch (Exception ex) { ev.Name = "<err " + ex.GetType().Name + ">"; }
      lock (events) { events.Add(ev); }
    }
    void OnFocus(object s, AutomationFocusChangedEventArgs a) {
      AutomationElement e = null;
      try { e = s as AutomationElement; } catch (Exception) { }
      Add("focus", e, null);
    }
    void OnAuto(object s, AutomationEventArgs a) { Add(a.EventId.ProgrammaticName, s as AutomationElement, null); }
    void OnProp(object s, AutomationPropertyChangedEventArgs a) {
      string nv = a.NewValue == null ? "null" : a.NewValue.ToString();
      Add("prop:" + a.Property.ProgrammaticName, s as AutomationElement, nv);
    }
    void OnStruct(object s, StructureChangedEventArgs a) { Add("structure", s as AutomationElement, a.StructureChangeType.ToString()); }

    public void Start() {
      Automation.AddAutomationFocusChangedEventHandler(OnFocus);
      Automation.AddAutomationEventHandler(TextPattern.TextChangedEvent, root, TreeScope.Subtree, OnAuto);
      Automation.AddAutomationEventHandler(TextPattern.TextSelectionChangedEvent, root, TreeScope.Subtree, OnAuto);
      Automation.AddAutomationEventHandler(InvokePattern.InvokedEvent, root, TreeScope.Subtree, OnAuto);
      Automation.AddAutomationPropertyChangedEventHandler(root, TreeScope.Subtree, OnProp, ValuePattern.ValueProperty, AutomationElement.NameProperty);
      Automation.AddStructureChangedEventHandler(root, TreeScope.Subtree, OnStruct);
      started = true;
    }
    public void Stop() { if (started) { started = false; Automation.RemoveAllEventHandlers(); } }
    public Ev[] Snapshot() { lock (events) { return events.ToArray(); } }
    public int Count { get { lock (events) { return events.Count; } } }
  }
}
