# SR0-B frame-budget investigation (batch 3 follow-up)

Read-only analysis. No Windows runs, no commits. Budget under test (architecture §11 rev 1): zero missed vblanks per run, displayed-interval p95 <= 16.664 + 0.1 = 16.764 ms.

Evidence base: `RESULT.md`, `result-presentmon-batch3.txt`, `pm-batch3-summary.txt`, `pm_an2.py`, `scripts/run-desktop.ps1`, `swiftright-render-probe/src/lib.rs`, gpui 0.2.2 source (local copy in the session scratchpad `gpui-src/gpui-0.2.2/src/`, identical to docs.rs), PresentMon `main` source and docs fetched from GitHub (`README-ConsoleApplication.md`, `PresentMon/OutputThread.cpp`, `PresentMon/MainThread.cpp`, `PresentMon/CommandLine.cpp`, `PresentData/PresentMonTraceSession.cpp`, `PresentData/PresentMonTraceConsumer.cpp`). Those are `main`, not the 2.6.0 tag; anything flag-related below is marked unverified for 2.6.0 where it matters. The raw PresentMon CSV and per-run `events.csv`/`dwm.csv` are on the Windows host only (`D:\Claude\sr0b-frame-clock\...`), so questions that need per-row timestamps are answered by an offline step 0 in the plan, not guessed.

Confidence labels: **PROVEN** (directly in evidence), **LIKELY** (best fit, one discriminating check outstanding), **UNKNOWN**.

---

## Issue 1: tbp-8, all 301 presents Dropped while another app was foreground

### What the evidence proves

1. **Timeline** (`result-presentmon-batch3.txt:610-654`). Probe foreground from +0.553 s. `rk2|RK2 target window` takes foreground at +1.817 s. Rect/z-order overlap exists only +1.817..+2.151 s. Probe foreground again at +9.808 s. The workload runs from about +4.6 s to +9.6 s (`window_ticks` ws..we = 5.004 s; idle A 3.0 s before it; the first 0.55 s plus 1 s settle). **PROVEN: the measured overlap ended about 2.5 s before the first animated present, and the probe was refocused only after the last one.** So "occluded for 0.33 s" is irrelevant to the 301 drops; something persistent covered the whole workload while `rk2` held foreground.
2. **PresentMon "Dropped" semantics** (`README v1` line 111: dropped = 1 if not displayed; `PresentMonTraceConsumer.cpp`):
   - `:1695-1745` (`TokenState::InFrame`): when DWM starts composing a newer present for the same HWND, the older present is marked `Discarded` only if it has no ScreenTime yet. A comment (`:1731-1738`) says short back-to-back bursts used to be wrongly marked dropped, which is why the ScreenTime guard exists.
   - `:1756-1767` (`TokenState::Discarded`): token discarded with no `InFrame` seen means `FinalState = Discarded`.
   - Consequence: **PROVEN that supersession cannot explain tbp-8.** Supersession drops at most the earlier of two presents inside one composition interval. Presents were 16.7 ms apart (between-presents p95 17.765, `pm-batch3-summary.txt`), i.e. one per vblank, and 301 of 301 were dropped. The only reading consistent with PresentMon's state machine is that **DWM never composed this window's surface** (token discarded without `InFrame`) for the entire workload.
3. **gpui is not the cause. PROVEN from source (gpui 0.2.2, `src/platform/windows/` unless noted):**
   - No branch on occlusion or activation gates drawing. `events.rs:42` routes `WM_ACTIVATE` to `handle_activate_msg` (`:749-762`), which only invokes the `active_status_change` callback; `window.rs:1092-1097` stores it in `Window::active`.
   - Frame path: `window.rs:1018-1062`. If `invalidator.is_dirty()` it draws and presents regardless of `active`. The only `active` use is `needs_present = ... || (active && last_input_timestamp.elapsed() < 1 s)` (`:1039-1042`), a keep-alive that re-presents an unchanged scene after input (to stop display underclocking). It is gated off when inactive, but it does not suppress dirty frames.
   - `directx_renderer.rs:204-206`: `Present(0, DXGI_PRESENT(0))`, then `result.ok()`. `DXGI_STATUS_OCCLUDED` is a success HRESULT, so `.ok()` passes it and gpui never sees or reacts to occlusion. No `DXGI_PRESENT_TEST`, no `IsWindowVisible`/`IsIconic` check on the present path (the only `IsIconic` is `window.rs:700`, a restore path; the `IsWindowVisible` hits at `:784/:793` are not on the present path).
   - Swap chain: `FLIP_SEQUENTIAL`, `BUFFER_COUNT = 3` (`directx_renderer.rs:1040/1068`, `:1389`), consistent with PresentMon's `Composed: Flip`.
   - VSync thread (`platform.rs:240-270`, `vsync.rs:40-55`): `DwmFlush()` then `RedrawWindow(RDW_INVALIDATE)` for every window, every cycle, unconditionally. If `DwmFlush` returns in under 1 ms (or fails) it falls back to `thread::sleep(interval)` (16.666 ms).
4. **The probe kept running normally.** `paints=305`, `ticks_delivered=300`, no stalls (`:629-636`). **But the probe's CPU paint cadence changed regime in this run only:** `paint_interval_ms p50=16.699 p95=17.756 p99=18.396` versus p95 16.83-17.02 in every other run. **PROVEN (observation):** the DwmFlush-driven clock became noisier at the same time DWM stopped composing the window. This fits "DWM not compositing us" (DwmFlush no longer locked to our own composition). It also fits a fall-back to `sleep(16.666 ms)` with 1 ms timer resolution (p50 +0.035 ms, tail from sleep granularity), but that second reading is not proven.
5. **Present count.** tbp-8 has 301 presents; the other 17 captured runs have 360-362. The ~60 extra in normal runs is one second at 60 Hz, which matches gpui's input keep-alive (`window.rs:994` initialises `last_input_timestamp = now()` at window creation; `:3582` refreshes it on any input event). tbp-8 lacks it. **UNKNOWN whether that is the cause**: `active` may have been false (or no input event) at creation. It is a second hint that window state in tbp-8 differed from the start, not only after +1.8 s. Batch 2's inactive base-4 (0/47 foreground) still produced 379 presents with no drop problem, so inactivity alone is not the discriminator.
6. **Foreground alone does not cause drops.** Batch 2 base-4: 0/47 foreground samples, 379 presents, 1 drop, normal intervals. **PROVEN: "not foreground" is not a sufficient condition.**

### Root cause

**LIKELY (not proven): DWM was not composing the probe's HWND from some point at or before +1.8 s until the end of the workload, caused by a state change induced by the other session's RK2 test window that our harness's geometry test could not see.** Ranked candidates:

| # | Candidate | Why plausible | Why unproven |
|---|---|---|---|
| 1 | **Our HWND cloaked or off the current virtual desktop.** The harness only checks cloaking for windows above us (`Cloaked(h)` in the occluder loop); it never checks the probe's own `DWMWA_CLOAKED`, and `ProbeVisible` is only `IsWindowVisible && !IsIconic` (`run-desktop.ps1`, `SR0Probe.Take`). A cloaked window reports visible and is not drawn, and DWM discards its tokens. | Fits visible + painting + zero geometric occluder + all-or-nothing drops. | No sample of our own cloak state exists. |
| 2 | **Full occlusion the rect test mis-measured.** `GetWindowRect` is DPI-virtualised for a DPI-unaware caller (PowerShell), layered/click-through windows are measured as rects but not as opaque coverage, and extended frame bounds are not used. | `rk2` was foreground; its rect test result flipped at +2.151 s while it stayed foreground, which could be a resize/move rather than a hide. | Needs a pixel-level or hit-test check. |
| 3 | Session/desktop/monitor state change (secure desktop, display reconfigure, exclusive fullscreen on the monitor by the test harness). | A test window titled "target window" could drive such changes. | No evidence either way. |
| 4 | PresentMon tracking artefact (ETW loss around the window). | Capture gaps exist elsewhere (issue 3). | 301/301 dropped across 5 s with matching paint-cadence change is not what lost events look like. |

Codex (labelled, `gpt-6.1-sol`; `-m astra` was rejected: "The 'astra' model is not supported when using Codex with a ChatGPT account", so the default model was used) independently ranked cloak/virtual-desktop first and geometry mis-measurement second, with high confidence that `Discarded` without `InFrame` does not uniquely identify occlusion, and warned that `Present(0, DXGI_PRESENT_TEST)` on a flip-model swap chain is not a reliable occlusion oracle (so it would not clear a hypothesis). This agrees with the ranking above.

### What discriminates (see batch-4 plan)

Log, per 50 ms sample and into every `change` line: `DWMWA_CLOAKED` bitmask of the probe HWND; `IVirtualDesktopManager::IsWindowOnCurrentVirtualDesktop(probe)`; a `WindowFromPoint` 7x5 grid over the probe client area (fraction of points that resolve to the probe's root window); per-monitor-DPI-aware physical rects for the probe and the foreground window plus the foreground window's `GWL_EXSTYLE` and `DWMWA_EXTENDED_FRAME_BOUNDS`. Also run the offline step 0 below: the time of each Dropped=1 row against the harness `change` lines.

### Do not do

Do not infer a gpui "stops presenting when inactive" behaviour; the source shows it does not. Do not add a present-test occlusion probe (cannot clear a hypothesis, per above).

---

## Issue 2: tbp-1 p95 16.873 ms with zero drops, no interrupter

### What the evidence proves

1. **tbp-1 is not an unobserved disturbance.** Its only extra "interrupter" is `SwiftHost|SR0-B frame-clock` for one sample at +0.747 s (`:45`): the foreground window was the probe before `Process.MainWindowHandle` existed, so `ProbeFg` was false. Sampling artefact; `focus_samples` total=160, visible=150, foreground=150.
2. **The tail is real in tbp-1's presentation:** displayed-change p95 16.873, p99 16.967, between-presents p95 16.996.
3. **The tail tracks the probe's own CPU paint cadence tail, not the variant.** Ranking all 17 captured valid runs:
   - Displayed-change p95 top three: tbp-1 (16.873), base-6 (16.750), base-9 (16.715).
   - CPU `paint_interval_ms` p95 top three: base-6 (17.023), tbp-1 (17.009), base-9 (16.961).
   - **The same three runs lead both lists.** Chance of that coincidence is 1 in C(17,3) = 1/680. Spearman over all 17 is only 0.43 (n=17, not significant), so the link is strong at the tail and weak in the bulk. Tick-entry p95 correlates 0.35 and DWM-sampler count 0.14 (neither useful).
   - Variant effect: elevated p95 (> 16.72) occurs in 1 of 9 valid tbp runs and in 2 of 8 valid base runs (base-6, base-9 on p99). **No evidence that `timeBeginPeriod(1)` causes or cures the tail**; n is far too small to claim either.
4. **Interval units.** The displayed-interval p50 is exactly one refresh (16.664 ms, DWM 60.008-60.009 Hz). A p95 of 16.873-16.967 ms is not any multiple of a refresh, so these are not missed vblanks (a missed vblank would show about 33.3 ms, and tbp-1 has none). They are either real scan-out timestamp slips of a few hundred microseconds or timestamp noise in PresentMon's ScreenTime. The sum of a long interval and the next short one would stay near 33.33 ms if it is timestamp noise.
5. **The probe's own DWM sampler is a poor vblank clock and a possible perturbation.** It yields only 28-44 samples per ~13 s run (`dwm_samples=`), about 2-3 Hz, although DwmFlush from gpui's vsync thread returns at 60 Hz. Cause **UNKNOWN**. It also adds a second `DwmFlush` waiter thread (`lib.rs:493-526`) beside gpui's. tbp-1 had 39 samples, tbp-6 44, base-2 39 (p95 fine), so the count does not predict tbp-1.

### Root cause

**LIKELY: trigger-side scheduling jitter in the frame path (DwmFlush wake, then WM_PAINT delivery, then Present) produces a small number of presents that land late relative to DWM's composition deadline, which shifts that frame's ScreenTime by a few hundred microseconds without costing a whole vblank.** Support: the same three runs show the tail in CPU paint cadence and in displayed intervals. **UNKNOWN: whether the displacement is in the true scan-out or only in PresentMon's timestamps, and whether the sampler thread contributes.** Nothing in the batch-3 outputs can separate those; the data needed (per-paint QPC against the vblank grid, per-row ScreenTime) is on the host.

### Additional logging that would discriminate

| Question | Logging |
|---|---|
| Real scan-out slip vs timestamp noise? | From PresentMon CSV: per-run min/p1/p5 of displayed interval and lag-1 autocorrelation. A long interval followed by a short one (pair sums to ~33.33 ms) means timestamp/phase noise; a persistent shift or longer tail with no compensating short interval means real slip. Also fit `t_k = t0 + k*T` to the displayed times and report residuals (zero-mean residual = jitter; step of T = missed vblank). |
| Is the late frame caused by a late trigger? | Per-paint phase against the vblank grid: `(paint_qpc - qpcVBlank) mod period`. Needs the DWM sampler at >= 20 Hz without `DwmFlush` (see lib.rs diff). The existing `dwm.csv` already holds `qpcVBlank` per sample but only ~30 samples, which is enough to build a grid (drift over 13 s at +-0.5 tick period error = ~39 us) for an offline pass on batch 3. |
| Does the extra `DwmFlush` waiter perturb? | A/B variant `nosamp` (sampler disabled) in the same interleaved batch. |
| Is it OS/other-process load? | Log per-sample CPU of top non-probe process (or PresentMon's own CPU) around late paints; at minimum log `GetProcessTimes` for the probe and PresentMon. |
| Is it tbp? | Needs more runs; batch-4 doubles the sample count (see plan). |

---

## Issue 3: PresentMon capture gaps (tbp-6 and base-7 in batch 3)

### What the evidence proves

1. **Pattern across batches.** Batch 1: base-2 and tbp-2 missing (adjacent). Batch 2: tbp-10 missing (plus base-1 partial in batch 1 from late start). Batch 3: tbp-6 and base-7 missing (adjacent). Missing runs are adjacent twice out of three, which hints at a time-localised cause (a 13-26 s window) rather than per-process randomness; three events is weak evidence.
2. **The analyzer is not hiding rows.** `pm_an2.py` groups by `ProcessID` and matches runs to processes by first-present time within +-4 s of the expected offset; no "unmatched pm processes" line printed in batch 3, and no process shows the ~720 presents a reused PID would produce. So the two runs genuinely have no rows (PROVEN for batch 3 only; PID reuse by merge is excluded).
3. **PresentMon's targeting logic** (`PresentMon/OutputThread.cpp`, `main`):
   - `:80-90` comment: process lifecycle comes from Kernel-Process ProcessStart/Stop events, but "only if PresentMon is running when the process started"; otherwise it falls back to noticing a new PID on its first present.
   - `:110-145` `IsTargetProcess`: `--process_name` is matched on the canonicalised image name (extension and directory stripped, lowercased) of that start event; **a process whose name cannot be resolved is not a target.**
   - `:294-318` `QueryProcessName`: fallback via `OpenProcess` + `QueryFullProcessImageNameW`; failure leaves the name `<unknown>`, which never matches `--process_name`. `GetPresentProcessInfo` (`:321-360`) caches that decision per PID in `gProcesses`, so a one-time failure drops every later present of that PID silently.
   - `:164-190` start/stop handling: a stop event removes the PID entry; `:436-465` defers a stop only when a present from the same PID is in the current batch.
   - **PROVEN: any failure that leaves a PID with an unresolved name, or a lost ProcessStart event combined with a failed fallback lookup, produces exactly "process ran, zero rows, no error".** Nothing logs this.
4. **ETW buffer sizing** (`PresentData/PresentMonTraceSession.cpp:493-500`): BufferSize 64 KB, MinimumBuffers 256, MaximumBuffers 1024 (about 16-64 MiB). Loss counters exist (`:611-612`, `:703-704`; `MainThread.cpp:448-454` prints "warning: N ETW events were lost" / "buffers were lost" at exit, and `:92` prints `[ETW Status] ... EventsLost= BuffersLost= OverflowedPresents=` when `--track_etw_status` is on). **PROVEN: PresentMon already tells you about loss, but nobody captured its stdout/stderr in batches 1-3**, so loss is neither confirmed nor excluded.
5. **Flags** (`README-ConsoleApplication.md`): `--process_name` (`:14`), `--output_file` (`:21`), `--no_console_stats` (`:25`), `--qpc_time` (`:26`), `--exclude_dropped` (`:29`, do not use), `--write_display_metadata` (`:32`), `--timed` (`:38`), `--no_track_input` (`:42`), `--no_track_gpu` (`:43`), `--session_name` (`:47`), `--stop_existing_session` (`:48`), `--terminate_after_timed` (`:52`). Not in that README but in `CommandLine.cpp` on `main`: `--track_etw_status` (`:486`), `--set_circular_buffer_size` (`:470`, must be a power of two, `:521-522`). **UNVERIFIED that either exists in the 2.6.0 binary**; the batch-4 command checks by running `--help`/the flag and failing fast.

### Root cause

**UNKNOWN. LIKELY ranking** (evidence for each is absent from batches 1-3, so the plan below captures it):

1. Process-attribution failure in PresentMon (name unresolved at first present, `<unknown>`, or ProcessStart missed for a short-lived process whose fallback `OpenProcess` came too late, or stop processed before pending presents). Adjacent failures fit a short period where PresentMon's output thread fell behind (it polls every 100 ms, `OutputThread.cpp:615-620`), since attribution is based on timing relative to pending present events.
2. ETW buffer/event loss in a short window. Plausible but 64 KB x up to 1024 buffers is generous for a 60 Hz single-process load; the capture, however, is desktop-wide (all of DWM, Edge, etc.), so volume is higher than the single process suggests.
3. Harness-side: PresentMon not running (restart/timer expiry) during those launches. Batch 3 PresentMon `--timed 300` covers 20 runs x 13 s = 260 s plus setup, so a timer cut is possible for the last run (consistent with batch 2 tbp-10, the last run) but not for tbp-6 or base-7 (mid-batch).

Codex (labelled): agreed the leading hypothesis is attribution/lifecycle timing, PID reuse unlikely across 13 s launches, and recommended capturing all processes (no `--process_name`), starting capture before the first child, keeping rows including dropped ones, joining offline on harness-recorded PID plus creation time, and keeping ETW loss counters. It could not confirm `--track_etw_status`/`--set_circular_buffer_size` in 2.6 from memory.

---

## Batch-4 plan

### Step 0. Offline re-analysis of existing batch-3 artifacts (no new run; Windows host files)

Do this first; it may settle issues 1 and 2 before any new capture.

On the host (or copied to the Mac), for `pm-batch3.csv`, `runs\20261009-041307\<run>\{events.csv,dwm.csv}`:

```python
# step0.py  (run with python3 -I)
import csv, sys, statistics as st
rows = list(csv.DictReader(open(sys.argv[1], newline='', encoding='utf-8-sig')))
pid = sys.argv[2]; rs = [r for r in rows if r['ProcessID'] == pid]
t0 = float(rs[0]['TimeInSeconds'])
# issue 1: when exactly are Dropped=1 rows (relative to first present, and first-present offset vs run start)
drops = [(float(r['TimeInSeconds']) - t0, r['PresentMode']) for r in rs if r.get('Dropped') == '1']
print('first present t0=%.3f s abs; dropped n=%d first=%.3f last=%.3f' %
      (t0, len(drops), drops[0][0] if drops else -1, drops[-1][0] if drops else -1))
# issue 2: displayed intervals in the workload, with lag-1 pair sums
d = [float(r['msBetweenDisplayChange']) for r in rs
     if r['msBetweenDisplayChange'] not in ('', 'NA') and 0 < float(r['msBetweenDisplayChange']) < 100]
d.sort(); n = len(d)
print('min/p1/p5/p50/p95/p99/max', d[0], d[int(.01*n)], d[int(.05*n)], d[n//2], d[int(.95*n)], d[int(.99*n)], d[-1])
seq = [float(r['msBetweenDisplayChange']) for r in rs
       if r['msBetweenDisplayChange'] not in ('', 'NA') and 0 < float(r['msBetweenDisplayChange']) < 100]
pairs = [(a, b) for a, b in zip(seq, seq[1:]) if a > 16.8]
print('long intervals', len(pairs), 'next interval after long:', [round(b, 3) for a, b in pairs][:20])
```

- Issue 1: pass if all 301 drops fall after +4.6 s (workload) and the `change` timeline shows nothing, which confirms "persistent, invisible to harness". Also check `PresentMode` of the dropped rows.
- Issue 2: for tbp-1, base-6, base-9, compare against two clean runs: tail shape (long followed by short = timestamp noise) and paint phase against the `dwm.csv` vblank grid. If long displayed intervals are paired with a compensating short one, classify as measurement noise and amend the budget wording (§11 rev 2: jitter-aware statistic), not the renderer.

### PresentMon command line (elevated, started 5 s before run 1, kept running 30 s after the last run)

```
PresentMon-2.6.0-x64.exe ^
  --v1_metrics --qpc_time ^
  --no_track_gpu --no_track_input --no_console_stats ^
  --track_etw_status ^
  --write_display_metadata ^
  --session_name SR0B4 --stop_existing_session ^
  --output_file D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.csv ^
  --timed 360 --terminate_after_timed ^
  > D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.console.txt 2>&1
```

Rationale and what to check:
- **No `--process_name` and no `--exclude`:** capture everything and filter by PID offline. Removes `IsTargetProcess`/name-resolution failure from the path (issue 3 root-cause candidate 1). Do not use `--exclude_dropped` (would hide issue 1).
- **`--qpc_time`:** absolute QPC for the CPU start so rows join to the probe's own QPC events and to the harness `qpc_start` (below) without relying on `TimeInSeconds` offsets. Column name differs under `--v1_metrics` (`QPCTime` in 1.x docs; `CPUStartQPC` in 2.x). `pm_an3.py` must sniff the header. Keep step-0 `TimeInSeconds`-based tooling for batch 3 data.
- **`--no_track_gpu --no_track_input`:** lowers ETW volume; neither is a budget metric. **Never** `--no_track_display`.
- **`--no_console_stats`:** the console redraw is CPU work on the same machine; output redirected to a file preserves warnings.
- **`--track_etw_status`:** prints `[ETW Status] BufferFillPct=... EventsLost= BuffersLost= OverflowedPresents=`. If this build rejects the flag ("unrecognized option"), drop it; the exit warnings ("ETW events were lost") still print. Acceptance requires the console file be kept.
- **`--set_circular_buffer_size 16384`:** only add if `--track_etw_status` shows `OverflowedPresents > 0`; this controls the consumer's present queue, not the ETW session buffers. Not enabled by default.
- **`--write_display_metadata`:** adds `VidPnSourceId, LayerIndex, PresentId` for issue 1 (which output and layer the dropped presents targeted).

### Harness diffs (`scripts/run-desktop.ps1`)

1. **Record PID and QPC start; stop relying on time matching.** After `$proc = [System.Diagnostics.Process]::Start($psi)`:

```powershell
$lines.Add("pid run=$id pid=$($proc.Id) start_utc=$([DateTime]::UtcNow.ToString('o')) qpc_start=$([System.Diagnostics.Stopwatch]::GetTimestamp()) creation=$($proc.StartTime.ToUniversalTime().ToString('o'))")
```

(`Stopwatch.GetTimestamp()` is QPC on Windows, 10 MHz here.) At exit add `pid_exit run=$id pid=$($proc.Id) qpc_end=...`.

2. **Make the harness DPI-aware and sample cloak/virtual-desktop/hit-test state of the probe.** In `$probeSrc` add:

```csharp
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags); // GA_ROOT = 2
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);      // GWL_EXSTYLE = -20
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx); // (IntPtr)(-4) per-monitor v2
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size); // 9 = EXTENDED_FRAME_BOUNDS

[ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVirtualDesktopManager {
    [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr h, [MarshalAs(UnmanagedType.Bool)] out bool on);
    [PreserveSig] int GetWindowDesktopId(IntPtr h, out Guid id);
    [PreserveSig] int MoveWindowToDesktop(IntPtr h, ref Guid id);
}
[ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")] class VirtualDesktopManagerCls {}
```

and extend `SR0Snap`/`Take()`:

```csharp
public int ProbeCloaked;        // DWMWA_CLOAKED bitmask for the probe HWND itself
public int OnCurrentDesktop;    // 1/0/-1 (IVirtualDesktopManager)
public int HitPct;              // percent of a 7x5 client-area grid whose WindowFromPoint root == probe
public string FgGeom;           // fg physical rect | ex-style | extended frame bounds

// in Take(probe), before the occluder walk
int c; DwmGetWindowAttribute(probe, 14, out c, 4); s.ProbeCloaked = c;
bool on; s.OnCurrentDesktop = vdm != null && vdm.IsWindowOnCurrentVirtualDesktop(probe, out on) == 0 ? (on ? 1 : 0) : -1;
RECT pr2; GetWindowRect(probe, out pr2);
int hit = 0, tot = 0;
for (int ix = 1; ix <= 7; ix++) for (int iy = 1; iy <= 5; iy++) {
    POINT p; p.X = pr2.Left + (pr2.Right - pr2.Left) * ix / 8; p.Y = pr2.Top + (pr2.Bottom - pr2.Top) * iy / 6;
    IntPtr w = WindowFromPoint(p); tot++;
    if (w != IntPtr.Zero && GetAncestor(w, 2) == probe) hit++;
}
s.HitPct = hit * 100 / tot;
```

Call `SetProcessDpiAwarenessContext((IntPtr)(-4))` once before the first `Take()`. Add `cloaked`, `cur_desktop`, `hit_pct` and (for the foreground window when it is not the probe) `fg_geom` to both the change `$key` and the `change` log line, so any state transition is written even when rect overlap stays zero.

3. **Guard against concurrent sessions.** Before each launch: if `Get-Process rk2*` (or any process in an allow-list-excluded set) exists, log `skip_run id=... reason=rk2-present` and wait (60 s cap) rather than measure through it. Ask Adrian not to run RightKit window tests on this host during the batch; the harness cannot prevent another session from taking foreground.
4. **Mark each run valid or disturbed in the log itself:** `run_state id=... valid=0|1 reason=probe_fg<100%|cloaked|occluded|hit<100|skipped` computed from the samples taken inside the probe's workload window (derive from `window_ticks` after the run, or sample-based when all samples agree). Disturbed runs are reported, never silently dropped (see pass criteria).
5. **Variant matrix:** extend `$variants` with `nosamp` (sampler disabled via `--no-dwm-sampler`, below) and interleave `base, tbp, nosamp` per round; `-Runs 10` gives 30 runs (~6.5 min) and 10 per variant. Run the whole batch twice if time allows, to get ≥ 20 per variant for the tbp question.

### Probe diffs (`swiftright-render-probe/src/lib.rs`, probe-only ABI, unfrozen)

1. **Sampler without `DwmFlush`, at high rate, flag-controlled.** Replace the body of `dwm_sampler()` (`:493-526`):

```rust
static SAMPLER_ENABLED: AtomicBool = AtomicBool::new(true);
#[no_mangle] pub extern "C" fn swr_set_dwm_sampler(on: u32) { SAMPLER_ENABLED.store(on != 0, SeqCst); }

fn dwm_sampler() {
    if !SAMPLER_ENABLED.load(SeqCst) { return; }
    while SAMPLER_RUN.load(SeqCst) {
        let t0 = qpc_now();
        if PROBE_HWND.load(SeqCst) == 0 { unsafe { EnumWindows(find_own_window, 0) }; }
        let hwnd = PROBE_HWND.load(SeqCst);
        let mut ti: DWM_TIMING_INFO = unsafe { std::mem::zeroed() };
        ti.cbSize = std::mem::size_of::<DWM_TIMING_INFO>() as u32;
        let rc = unsafe { DwmGetCompositionTimingInfo(HWND(hwnd as *mut c_void), &mut ti) };
        let t1 = qpc_now();
        if rc.is_ok() { dwm_ring().push(DwmSample { qpc: t1, c_fd: ti.cFrameDisplayed, qpc_fd: ti.qpcFrameDisplayed,
            qpc_vblank: ti.qpcVBlank, c_refresh: ti.cRefresh, rate_num: ti.rateRefresh.uiNumerator,
            rate_den: ti.rateRefresh.uiDenominator, fast: 0, fg: (hwnd != 0 && unsafe { GetForegroundWindow() } as usize == hwnd) as u32 }); }
        std::thread::sleep(Duration::from_millis(8));   // ~125 Hz with tbp, ~64 Hz without (15.6 ms quantum)
    }
}
```

The ring is sized 131072 slots (unchanged); at 125 Hz over 15 s this is under 2,000 entries. `DwmGetCompositionTimingInfo` with `cFrameDisplayed == 0` for our HWND is already known (RESULT.md), so use `qpc_vblank` and `c_refresh` only. Per MS docs `qpcVBlank` is a vblank timestamp (confirm sign/phase by checking monotonic consistency with `c_refresh` before relying on absolute phase). Pass `--no-dwm-sampler` in the SwiftHost arg handling to call `swr_set_dwm_sampler(0)` before `swr_run` (variant `nosamp`).

2. **Per-paint phase in the report.** In `swr_report`, add `paint_phase_ms(vs vblank)` p50/p95/p99 and max, computed as `((paint_qpc - qpc_vblank_k) mod period)` for the nearest preceding sampler row. A tight phase means a locked trigger; a smeared phase with a late-tail cluster is the trigger-jitter signature.
3. **Print present-count-affecting state.** Log `window.is_window_active()` (or the gpui `active` value) at each paint during the first 2 s and when it changes (keep-alive explanation, `window.rs:1039-1042`). One line per transition, not per paint.
4. **Keep the CPU paint-cadence check informational** (it already fails PASS while the §11 endpoint is PresentMon); change its verdict contribution to log-only so `verdict=` stops flagging runs that pass §11.

### Offline analysis (`pm_an3.py`)

Replace time-based process matching with the harness's `pid` lines (`run -> pid, qpc_start`). Filter the capture-all CSV by `ProcessID == pid` and `Application == SwiftHost.exe`. Per run: presents, dropped, displayed-interval p50/p95/p99/max and min/p1/p5, count of intervals > 1.5 x 16.664 ms = 24.996 ms inside the workload window (**missed vblanks**), lag-1 pair statistic, `Dropped` timeline against harness `change` lines, and the first and last present QPC against the probe's `window_ticks`. Print `[ETW Status]` last line and exit warnings from `pm-batch4.console.txt`. Check the CSV header for the correct time column (see `--qpc_time` note).

### Pass criteria

Capture integrity (must pass before any budget claim):
- Every harness-logged PID has >= 355 CSV rows (20 of 20 / N of N, no "no rows" run).
- Console file shows `EventsLost=0`, `BuffersLost=0`, `OverflowedPresents=0`, and no "lost" warnings. If any are non-zero the batch is inconclusive for the affected window and issue 3 gets the loss answer.
- If a PID has no rows in a capture-all CSV, that is a transport/ETW fact, not a naming problem: record it as the answer to issue 3 and attach the console status.

Per-run validity (otherwise the run is reported as disturbed, not counted):
- Probe foreground, not cloaked, on current virtual desktop, hit-test >= 95%, and no foreign process in the foreground for 100% of workload-window samples.

Frame budget (architecture §11 rev 1), over valid runs:
- Zero missed vblanks in every valid run (no displayed interval > 24.996 ms inside the workload window, no `Dropped=1` row).
- Displayed-interval p95 <= 16.764 ms in every valid run. Required valid-run count: >= 9 per variant per 10 launched (>= 27 of 30); report all disturbed runs with their reason.
- Variant claims (e.g. `timeBeginPeriod` effect, sampler effect): do not claim any difference unless the per-run p95 distributions differ by more than the pooled spread across >= 20 valid runs per variant (rank-sum test), and report the p-value; otherwise record "no effect shown".

Issue-specific closeouts:
- Issue 1 closed when a run reproduces drops with a logged state transition (cloak, desktop, hit-test, geometry, or fg-window geometry), or when 3 consecutive batches with the new sampling show no recurrence; label the root cause UNKNOWN in the contract rather than inventing one if neither occurs.
- Issue 2 closed when step 0 or batch 4 shows tail shape (noise vs real slip) and the paint-phase signature for tbp-1-like runs, and the §11 wording is either confirmed or amended by Adrian's change control.
- Issue 3 closed by the ETW-status and PID-join evidence above.

### Things not to do

- Do not drop disturbed runs from tables.
- Do not use `--process_name` in batch 4.
- Do not change gpui; every gpui behaviour found above is within spec for the probe's purposes.
- Do not commit or push anything from this analysis.
