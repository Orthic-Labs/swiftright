// #45: records every WinEvent (out of context, all processes) and the UI Automation text/selection/structure events of one window, with QPC timestamps,
// so the event streams around a layout move can be compared between two hosts (Edge vs SwiftRight). A dedicated thread pumps messages for the WinEvent hook.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;
namespace SRN {
  public static class EventLog {
    delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc proc, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int n);
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w; public IntPtr l; public uint t; public int x; public int y; }
    static readonly List<string> lines = new List<string>();
    static readonly Stopwatch clock = Stopwatch.StartNew();
    static Thread pump; static uint pumpTid; static WinEventProc keep; static IntPtr hook;
    static AutomationElement target; static AutomationEventHandler textChanged, selChanged; static StructureChangedEventHandler structure; static AutomationPropertyChangedEventHandler prop;
    static void Add(string s) { lock (lines) { if (lines.Count < 20000) lines.Add(clock.ElapsedMilliseconds.ToString("D7") + " q=" + Stopwatch.GetTimestamp() + " " + s); } }
    public static void Mark(string s) { Add("MARK " + s); }
    static string Cls(IntPtr h) { var sb = new System.Text.StringBuilder(128); GetClassName(h, sb, 128); return sb.ToString(); }
    public static void Start(IntPtr window) {
      lock (lines) lines.Clear();
      var ready = new ManualResetEvent(false);
      pump = new Thread(() => {
        pumpTid = GetCurrentThreadId();
        keep = (hk, ev, hwnd, idObj, idChild, th, tm) => {
          // skip the noisiest generic events with no information for this question
          if (ev == 0x800C /*NAMECHANGE*/ && idObj != -8) { }
          uint pid; GetWindowThreadProcessId(hwnd, out pid);
          string p = "?"; try { p = Process.GetProcessById((int)pid).ProcessName; } catch { }
          Add(string.Format("WINEVENT ev=0x{0:X4} hwnd=0x{1:X} cls={2} proc={3} obj={4} child={5}", ev, hwnd.ToInt64(), Cls(hwnd), p, idObj, idChild));
        };
        hook = SetWinEventHook(0x0001, 0x7FFFFFFF, IntPtr.Zero, keep, 0, 0, 0x0002 /*OUTOFCONTEXT*/ | 0x0001 /*SKIPOWNTHREAD*/);
        ready.Set();
        MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref m); DispatchMessage(ref m); }
        UnhookWinEvent(hook);
      });
      pump.IsBackground = true; pump.Start(); ready.WaitOne(3000);
      try {
        target = AutomationElement.FromHandle(window);
        textChanged = (s, e) => Add("UIA TextChanged src=" + Desc(s));
        selChanged = (s, e) => Add("UIA TextSelectionChanged src=" + Desc(s));
        structure = (s, e) => Add("UIA StructureChanged " + e.StructureChangeType + " src=" + Desc(s));
        prop = (s, e) => Add("UIA Property " + e.Property.ProgrammaticName + " src=" + Desc(s));
        Automation.AddAutomationEventHandler(TextPattern.TextChangedEvent, target, TreeScope.Subtree, textChanged);
        Automation.AddAutomationEventHandler(TextPattern.TextSelectionChangedEvent, target, TreeScope.Subtree, selChanged);
        Automation.AddStructureChangedEventHandler(target, TreeScope.Subtree, structure);
        Automation.AddAutomationPropertyChangedEventHandler(target, TreeScope.Subtree, prop, AutomationElement.BoundingRectangleProperty);
        Add("UIA handlers attached to hwnd=0x" + window.ToInt64().ToString("X"));
      } catch (Exception ex) { Add("UIA attach error " + ex.Message); }
    }
    static string Desc(object s) { try { var e = (AutomationElement)s; return e.Current.ControlType.ProgrammaticName + "/" + e.Current.Name; } catch { return "?"; } }
    public static string[] Stop() {
      try { Automation.RemoveAllEventHandlers(); } catch { }
      if (pumpTid != 0) PostThreadMessage(pumpTid, 0x0012 /*WM_QUIT*/, IntPtr.Zero, IntPtr.Zero);
      if (pump != null) pump.Join(2000);
      lock (lines) return lines.ToArray();
    }
  }
}
