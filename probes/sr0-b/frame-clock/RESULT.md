# SR0-B frame-clock probe: RESULT

Overall: **partial**. The on-demand frame clock works: zero paints and zero ticks over 3 s idle in every run, all 5000 jobs and 500 MainActor hops complete with zero thread or re-entrancy violations, and job latency p99 is at most 1.63 ms (max 13.6 ms). **Not achieved:** the presented-frame interval (the SR0 criterion, p95 at or under 16.7 ms). The only interval measured is the paint cadence on the CPU side, and its p95 is 16.79 to 20.65 ms, so it fails in all 10 runs. Presented-frame counters from DWM were not reachable for gpui's swap chain (details below). The earlier 300 to 660 ms job stalls did not recur, so there was nothing over 16.7 ms to attribute at the job level.

Probe location: `probes/sr0-b/frame-clock/` (gpui-drain untouched). Windows artifacts: `D:\Claude\sr0b-frame-clock\`. Nothing committed or pushed.

## Design

- **Frame clock, no timer.** The 16 ms gpui timer is removed. gpui 0.2.2 on Windows (`src/platform/windows/platform.rs:240-270`) runs a VSync thread that calls `RedrawWindow(RDW_INVALIDATE)` every vblank. WM_PAINT then calls `on_request_frame` (`src/window.rs:1023-1060`), which first runs `Window::on_next_frame` callbacks and then draws only if the window is dirty. Each paint while `ANIMATING` calls `window.request_animation_frame()` (`src/window.rs:1654`). Frames stop when `ANIMATING` is cleared, because no paint then requests the next one.
- **Ticks.** Each animated paint records a tick request and signals the drain task (`signal_notify`). The drain task, which runs outside any GPUI borrow, calls the host's `tick(ctx, timestamp_ns)` after the drain callback. Swift advances its counter and calls `swr_submit_commit(seq)`; the next paint shows the committed value. The `KICK` path (`swr_set_animating(1)`) notifies the root view to start the chain.
- **Events.** Every WAKE (with source), DRAIN, PAINT (with animating flag and committed seq) and TICK is written with QPC timestamps into a preallocated 131072-slot ring (`swr_dump` writes `events.csv`, `dwm.csv`, `meta.txt`).
- **DWM sampler.** A thread polls `DwmFlush` and `DwmGetCompositionTimingInfo` on the probe's own HWND (found through `EnumWindows` by PID), and records the foreground flag. `EnumDisplaySettingsW` gives the monitor refresh.
- **Stall analysis.** `swr_report` prints, for each job over 16.7 ms, the overlapping wake/drain/paint/tick intervals, uncovered gaps and a cause line. In this batch there were no such jobs, so the stall path printed nothing.
- **Workload** as gpui-drain (5000 jobs at 1 kHz, 500 MainActor hops), plus continuous animation during it. Phases: idle A (3 s after a 1 s settle, animation off), workload, idle B (3 s after animation stops and a 300 ms settle).
- **A/B.** `--timer-res-1` calls `timeBeginPeriod(1)` before `swr_run`. Runs are interleaved (base-1, tbp-1, base-2, ...), 5 each.
- **ABI 0.2** (probe-only): `tick` appended to `swr_host_callbacks`; new exports `swr_set_timer_resolution`, `swr_set_animating`, `swr_submit_commit`, `swr_paints`, `swr_ticks_requested`, `swr_dump`, `swr_report`.

## Commands and request IDs

- Rust build, iteration 1: `rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc` in `swiftright-render-probe/`. `rr-1791489878849-19c46c5dfc78e8f6` **FAILED**: `E0308` in `src/lib.rs:316` (`qpc_to_ns` takes `i64`, target is `u64`). Fixed.
- Rust build, iteration 2: `rr-1791490911432-6dca8835a146a515` **SUCCEEDED** (exit 0). Used for the first two batches.
- Rust build, iteration 3 (DWM counters now queried with the probe HWND, plus foreground flag): `rr-1791492125625-4f269621277a0a9c` **SUCCEEDED**. Used for the final batch. Max 4 build-fix iterations; 3 used.
- Swift build (once, unchanged afterwards): `scripts/build-swift.ps1` on Windows, `swift build -c release`, `Build complete! (13.29 secs)`, exit 0. Warnings only (`stateLock` used from async context; same pattern as gpui-drain).
- Payload: DLL and import lib from the remote build's `target\x86_64-pc-windows-msvc\release\` into `payload\bin` and `payload\lib`; `include` synced from the Mac; DLL copied beside `SwiftHost.exe`.
- Desktop runs: one-shot interactive scheduled task per batch (`Register-ScheduledTask`, user `adrds`, `LogonType Interactive`), running `scripts/run-desktop.ps1 -Runs 5`, then `Unregister-ScheduledTask`. Each unregistered after the result file's `finished=` line.
  - `SR0F-20261009-020656`: all 10 runs failed with exit -1073741515 (DLL not found beside the exe). Invalid, no data.
  - `SR0F-20261009-021000`: DLL fixed. Valid run, but DWM queried with a NULL HWND, so the DWM frame counter is 0. Superseded.
  - `SR0F-20261009-021500`: final batch, iteration-3 DLL. **Results: `result-batch-20261009-021500.txt`** (same directory as this file; per-run artifacts in `D:\Claude\sr0b-frame-clock\runs\20261009-022720\<variant>-<n>\`).

## Verbatim output (base-1, trimmed to the run block; full batch in `result-batch-20261009-021500.txt`)

```
=== RUN base-1 start=2026-10-09T02:27:20.6072379+05:30
focus_samples: total=49 window_visible=47 window_foreground=47
initial_thread_id=31352 timer_resolution_1ms_requested=0 out=<runRoot>\base-1
bootstrap_query_rc=0 abi=0.2 pointer_width=64 fn_table_size=9
main_queue_wake_handle=Optional(0x00000000000002a4)
[sr0-b rust] loop_ready_calls=1 drain_calls=5150 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=5500 wake_wait_failures=0 paints=304 stale_paints=1 ticks_requested=301 ticks_delivered=301 commits=301 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
producer enqueue_rate_hz=1000.1985594180156 hops_enqueued=500
jobs_run=5000/5000 jobs_done_counter=5000
latency_ms p50=0.0579 p95=0.1254 p99=0.3774 max=1.4873
tick_entry_ms p50=0.3119 p95=0.4277 p99=0.5060 max=0.6431 n=301
tick_to_commit_ms p50=0.0003 p95=0.0004 p99=0.0007 max=0.0016 n=301
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=5149 selftest_swift_result=1
mainactor_hops=500/500
idle_A_paints=0 idle_A_ticks=0 workload_ticks=301 ticks_delivered=301
idle_B_paints=0 idle_B_ticks=0
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false phases_done=true
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
window_ticks ws=40933651242 we=40983770580 idleA=[40903628859,40933651201] idleB=[40986860138,41016887158]
[frame-clock] monitor enum_display_hz=60 (ok=true) dwm_rate_hz=60.009 qpc_freq=10000000 dwm_samples=29 dwm_fast_returns=0 event_count=11558 event_drops=0
[frame-clock] presented_interval_ms(dwm) n=0 p50=NaN p95=NaN p99=NaN max=NaN
[frame-clock] dwm_samples_foreground=0/29 probe_hwnd_found=true
[frame-clock] presented_frames_in_workload=0 dwm_count_jumps=0 dwm_displayed_in_idle_A=0 dwm_displayed_in_idle_B=0 (desktop-global counters)
[frame-clock] paint_interval_ms(rust) n=300 p50=16.660 p95=16.898 p99=17.130 max=17.458
[frame-clock] paint_duration_ms(rust) n=301 p50=0.007 p95=0.013 p99=0.080 max=0.103
[frame-clock] paints_in_workload=301 paints_idle_A=0 paints_idle_B=0
[frame-clock] ticks_idle_A_or_B=0
[frame-clock] job_latency_over_16.7ms=0 of 5000
[frame-clock] stall_cause_tally={}
swr_dump_rc=0
verdict=PASS
exit=0 end=2026-10-09T02:27:33.7395202+05:30
```

## Results: 10 runs (5 base, 5 with timeBeginPeriod(1)), 60 Hz display

Monitor: `EnumDisplaySettingsW` reports 60 Hz; DWM rate 60.000 to 60.009 Hz.

| Run | Job latency ms p50 / p95 / p99 / max | Paint interval ms p50 / p95 / p99 / max (n) | Tick entry ms p50 / p95 | Tick-to-commit ms p50 / p99 | Focus: visible / foreground of samples | Idle A/B paints, ticks | Verdict |
|---|---|---|---|---|---|---|---|
| base-1 | 0.0579 / 0.1254 / 0.3774 / 1.4873 | 16.660 / 16.898 / 17.130 / 17.458 (300) | 0.3119 / 0.4277 | 0.0003 / 0.0007 | 47/49 visible, 47 fg | A 0p 0t, B 0p 0t | PASS |
| tbp-1 | 0.0604 / 0.1154 / 0.3072 / 0.5350 | 16.662 / 16.875 / 17.133 / 17.736 (299) | 0.2803 / 0.3951 | 0.0003 / 0.0007 | 49/51 visible, 49 fg | A 0p 0t, B 0p 0t | PASS |
| base-2 | 0.0603 / 0.1113 / 0.2893 / 1.1570 | 16.668 / 16.956 / 17.376 / 17.509 (299) | 0.2631 / 0.3522 | 0.0003 / 0.0006 | 48/50 visible, 48 fg | A 0p 0t, B 0p 0t | PASS |
| tbp-2 | 0.0333 / 0.2061 / 0.3895 / 4.0550 | 16.661 / 16.843 / 17.067 / 17.283 (300) | 1.2130 / 5.6244 | 0.0003 / 0.0005 | 48/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |
| base-3 | 0.0411 / 0.1937 / 0.5204 / 2.9718 | 16.664 / 17.023 / 18.627 / 19.655 (299) | 0.6111 / 4.0728 | 0.0003 / 0.0006 | 48/50 visible, 5 fg | A 0p 0t, B 0p 0t | PASS |
| tbp-3 | 0.0411 / 0.1704 / 0.2922 / 1.2979 | 16.665 / 16.789 / 17.109 / 19.602 (299) | 0.6797 / 4.3933 | 0.0003 / 0.0005 | 48/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |
| base-4 | 0.0796 / 0.7329 / 1.6311 / 11.8092 | 16.670 / 20.648 / 27.447 / 50.692 (298) | 0.6387 / 5.0577 | 0.0003 / 0.0006 | 48/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |
| tbp-4 | 0.0547 / 0.2806 / 0.8154 / 13.5598 | 16.663 / 19.443 / 21.080 / 21.307 (299) | 0.6420 / 3.1978 | 0.0003 / 0.0005 | 47/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |
| base-5 | 0.0506 / 0.1714 / 0.4330 / 1.1215 | 16.663 / 19.083 / 19.508 / 20.039 (300) | 0.4187 / 2.4166 | 0.0003 / 0.0005 | 47/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |
| tbp-5 | 0.0474 / 0.1823 / 0.4625 / 4.1171 | 16.657 / 19.050 / 19.361 / 19.704 (299) | 0.6199 / 2.2685 | 0.0003 / 0.0005 | 47/50 visible, 0 fg | A 0p 0t, B 0p 0t | PASS |

Paint interval is the CPU-side interval between consecutive animated paints (Rust `PAINT` events). It is **not** a presented-frame interval.

Across runs (base vs tbp, 5 each): job p99 ranges 0.29 to 1.63 ms (base) and 0.31 to 0.82 ms (tbp); paint p50 is 16.66 ms in every run; paint p95 is 16.79 to 20.65 ms. The timeBeginPeriod difference is within run-to-run noise at this sample size, so there is no claim that it helps or hurts.

## PASS / FAIL

| Criterion | Target | Result | Verdict |
|---|---|---|---|
| Idle frames over 3 s, no animation (paints and ticks) | 0 | 0 paints, 0 ticks, idle A and B, all 10 runs | PASS |
| Ticks only while animating; coalesced delivery | ticks follow animated paints | ticks = animated paints in every run (299 to 301 each; 1:1) | PASS |
| All jobs executed | 5000/5000 | 5000/5000, all 10 runs | PASS |
| MainActor hops | 500/500 | 500/500, all 10 runs | PASS |
| Thread violations and re-entrancy | 0 | 0 and 0 (self-test detected = 1) | PASS |
| Job enqueue to execute p99 | at or under 16.7 ms | 0.29 to 1.63 ms | PASS |
| Jobs over 16.7 ms | none expected | 0 of 50,000 (max 13.56 ms) | PASS |
| Tick to commit cost | measured | p50 0.3 us, p99 0.5 to 0.8 us | MEASURED (no budget in §11) |
| Presented-frame interval p95 at or under 16.7 ms (60 Hz) | 16.7 ms | **Not measured.** DWM frame counter stayed 0 with the probe HWND; swap chain is private to gpui | **NOT ACHIEVED** |
| Paint-cadence p95 at or under 16.7 ms (CPU-side proxy) | 16.7 ms | 16.79 to 20.65 ms; fails in all 10 runs | FAIL (proxy) |
| Paint-cadence p99 at or under 33.4 ms (proxy) | 33.4 ms | 17.07 to 27.45 ms | PASS (proxy) |
| Stale paints during animation | low | 1 per run (the first paint after the kick) | PASS |
| Foreground focus of the probe window | visible and focused | foreground in run 1 and 2 of base and tbp only; 0 after that | UNRESOLVED (see below) |

## Stall attribution

Jobs over 16.7 ms: **none** (0 of 50,000 across 10 runs). The 300 to 660 ms job stalls from gpui-drain did not recur. They cannot be attributed from this data.

Paint gaps over 16.7 ms (CPU-side, workload window): base-1 93, tbp-1 98, base-2 90, tbp-2 92, base-3 98, tbp-3 84, base-4 143, tbp-4 104, base-5 93, tbp-5 95. Nearly all are 16.7 to 21 ms, meaning one vblank late by a fraction of a millisecond. In these gaps the UI thread was idle between vblanks (only job drains of about 5 µs, one per 1 ms). These are vsync wait jitter, not UI blocking.

Paint gaps over 25 ms: **4, all in base-4** (26.75, 33.29, 27.45 and 50.69 ms; none in the other 9 runs).
- The UI thread stayed live throughout: job drains kept running about every 1 ms (4 to 10 µs each) and wakes continued. Drains kept running after each paint returned, so the thread was not blocked in `window.present()` (DXGI Present) or in a paint.
- No PAINT event occurred during the gap, so the frame trigger was late. The trigger is gpui's VSync thread (`DwmFlush` then `RedrawWindow`) and WM_PAINT delivery, both outside this probe's instrumentation.
- **Attribution: unresolved.** The data excludes UI-thread blocking in drains, paint or Present. It does not identify the late trigger. The probe's own DWM sampler logged only 27 to 34 samples per run (about 2 to 3 per second), which suggests `DwmFlush` returned sparsely in this session, but that is not proven as the cause.

Tick delivery tails: tick entry p95 is 0.35 to 0.43 ms in base-1, base-2 and tbp-1, but 2.2 to 5.6 ms in the other runs. The 50 ms tick entry in base-4 is not tied to the 50 ms paint gap (its own paint started 0.5 ms before its tick), so it is not attributed.

## Focus

Foreground status was not stable. The probe window was foreground in 47 to 49 of its samples in base-1, tbp-1 and base-2, and in 0 to 5 samples in every later run. Cause unknown. The likely candidate is the desktop session's focus changing during the batch; nothing in the probe changed focus. Window visibility was 47 to 49 of 50 samples in all runs. This is an observation, not a verified cause.

## Gaps, open items, and what was not done

- **Presented-frame interval (SR0 criterion) not measured.** `DwmGetCompositionTimingInfo` returned `cFrameDisplayed = 0` for every sample with the probe HWND, both with NULL and with the probe window. The swap chain is owned by gpui's DirectX renderer and is not reachable from this probe. Alternatives not tried in this slice: `IDXGISwapChain::GetFrameStatistics` (needs gpui's swap chain handle, i.e. a gpui change), or an external optical or ETW-based capture. Until one of those is in place, SR0 has no measured presented-frame interval.
- **gpui's own vsync thread wakes at vblank even when idle** (`platform.rs:240-270`). The probe proves zero paints and zero ticks at idle, not zero gpui-internal wakeups. Measuring that needs instrumenting gpui.
- Paint-cadence p95 fails the 16.7 ms target in all runs. The gap is a few tenths of a millisecond at p95 and several milliseconds in base-4's tail. Whether this is the frame-trigger issue above or VSync wait jitter is unresolved.
- Single host (`BOGUS-DELL`), 60 Hz monitor, Swift 6.4.0, gpui 0.2.2 and windows 0.61.3. Probe-only ABI 0.2, not frozen. Nothing committed or pushed.

## Primary verification & next step (2026-10-09)

Primary re-read `result-batch-20261009-021500.txt`: idle frames 0, jobs 5000/5000, job p99 ≤ 1.63 ms, CPU paint cadence p50 16.66 ms with p95 up to ~20.7 ms, DWM presented-frame samples n=0. The earlier 300–660 ms stalls did not recur under the display-driven clock.

Presented-frame measurement needs an external ETW consumer such as Microsoft PresentMon against the probe process, or swap-chain frame statistics exposed from inside GPUI. CPU paint cadence is not the §11 presentation endpoint.

## Presented-frame intervals via PresentMon (2026-10-09, batch 030737)

**Setup.** Microsoft PresentMon 2.6.0 CLI (`PresentMon-2.6.0-x64.exe`, official GameTechDev GitHub release) ran elevated through `win` with `--process_name SwiftHost.exe --v1_metrics --timed 300`. `scripts/run-desktop.ps1 -Runs 5` ran meanwhile in the interactive desktop session. The binary was unchanged from batch 021500. Results: `result-presentmon-batch1.txt` (probe output) and `pm-batch1-summary.txt` (per-process PresentMon summary from `pm_an.py`). The raw CSV stays on the host at `D:\Claude\sr0b-frame-clock\presentmon\pm-batch1.csv`.

**Present path.** Every present is `Composed: Flip` with `SyncInterval 0`, so DWM composes frames rather than flipping them independently. `msUntilDisplayed` p50 is about 31–32 ms, roughly two vblanks from present to scan-out.

**Mapping.** PresentMon recorded 8 of the 10 processes. Matching processes to runs by start time (13 s spacing): base-1 was captured only partly, because PresentMon started late. base-2 and tbp-2 have no PresentMon rows; the cause is unknown. The other seven runs map one-to-one.

| Run | Foreground samples | Presents | Dropped | Displayed-change p50 / p95 / p99 ms |
|---|---|---|---|---|
| base-1 (partial) | 0/47 | 301 | 301 | none displayed |
| tbp-1 | 4/47 | 363 | 358 | n=4 |
| base-3 | 48/48 | 361 | 12 | 16.664 / 16.697 / 16.714 |
| tbp-3 | 9/47 | 376 | 315 | 16.667 / 16.699 / 16.706 (n=60) |
| base-4 | 47/47 | 361 | 12 | 16.664 / 16.697 / 16.710 |
| tbp-4 | 23/47 | 361 | 163 | 16.666 / 116.654 / 166.648 |
| base-5 | 35/47 | 367 | 3 | 16.664 / 16.696 / 17.231 |
| tbp-5 | 46/46 | 352 | 5 | 16.665 / 16.689 / 16.703 |

Each run's max (about 3.0–3.1 s) is the gap across the probe's idle phase, when no presents happen by design. It is not a stall.

**Verdict.** In unobscured runs (base-3, base-4, base-5, tbp-5) the presented-frame interval has p95 16.689–16.697 ms, which meets architecture §11 (p95 ≤ 16.7 ms) by about 0.003 ms. p99 is at most 17.23 ms. A batch of four runs is not enough to call this a stable pass.

**Drops follow occlusion.** Mass drops occur only in runs where the probe was not foreground (base-1, tbp-1, tbp-3, tbp-4). In this batch the maximized Claude desktop window covered the probe in those runs. DWM skips frames from occluded windows, so these drops say nothing about the renderer. The future harness must bring the probe to the foreground (or use a clean desktop) before measuring.

**Still open.** base-2 and tbp-2 were not captured, so the next batch should start PresentMon before the first launch and confirm one row set per process. The probe's own `verdict=FAIL` (tbp-1 and tbp-3, exit 1) comes from the CPU paint-cadence check (`paint_interval_ms(rust)` p95 of about 19–20 ms). That is not the §11 endpoint, and its threshold should move to the PresentMon interval. The about 32 ms present-to-display latency is a DWM composition cost to track against the input-latency budget.

## PresentMon batch 2 (2026-10-09, run by the Windows desktop session; copied & checked by primary)

Files: `result-presentmon-batch2.txt`, `pm-batch2-summary.txt`, `pm_an2.py` (raw CSV stays on host at `D:\Claude\sr0b-frame-clock\presentmon\pm-batch2.csv`). PresentMon 2.6.0 elevated, started before run 1; desktop minimised (Win+D) before launches; 20 processes, 19 captured (tbp-10 has no rows, cause unknown); an unrelated modal-loop SwiftHost was excluded.

- 13 clean runs (full foreground, zero drops): displayed-change p50 16.664 ms (one refresh at DWM's 60.008 Hz), p95 16.694–16.702 ms, p99 ≤ 16.95 ms, one missed vblank in total. Six clean runs sit 1–2 µs above the 16.70 ms limit.
- Disturbed runs: drops in base-3 and tbp-6 despite full foreground samples (250 ms sampling may miss transient overlays); focus loss in five runs with no user input. Cause not yet attributed.
- Present-to-display latency 31.7–32.5 ms in every run (two vblanks, Composed: Flip, SyncInterval 0).

Finding for the contract: the §11 presentation limit (p95 ≤ 16.7 ms on a 60 Hz display) sits on the scan-out jitter floor of a 60.008 Hz display. Proposed restatement, pending maintainer decision under §11 change control: zero missed vblanks (displayed interval > 1.5 × measured refresh period) per run, and p95 ≤ measured refresh period + 0.1 ms. Harness must also log foreground window titles and occlusion per sample before disturbed runs can be attributed.

### Harness note: run-desktop.ps1 v2 (script change only, not yet run)

`scripts/run-desktop.ps1` now brings the probe window to the foreground once it exists (SetForegroundWindow, then AllowSetForegroundWindow, then AttachThreadInput) and logs `fg_attempt ... method=... ok=...` per run. Sampling moved from 250 ms to 50 ms and records the foreground HWND, its title and process, probe-foreground state, and visible top-level windows above the probe rect in z-order. It logs one `change` line per state change, plus `fg_samples`, `probe_fg_samples`, `occluded_samples`, `distinct_interrupters` and per-interrupter counts. The `focus_samples` line keeps its format. Parse-checked on Windows only (0 errors); not executed. The C# helper has not been compiled yet, so the first desktop run is the compile check.

## PresentMon batch 3 (2026-10-09, v2 harness; desktop session run, primary-checked)

Files: `result-presentmon-batch3.txt`, `pm-batch3-summary.txt`, `pm_an2.py` (now matches PresentMon rows to runs by first-present time ±4 s). 18/20 processes captured (tbp-6, base-7 missing — third batch with unexplained capture gaps).

Against §11 revision 1 (p95 ≤ refresh 16.664 + 0.1 = 16.764 ms; zero missed vblanks):
- 15 runs with full probe foreground and zero drops: 14 meet p95 (16.696–16.750 ms); **tbp-1 fails at 16.873 ms** (p99 16.967) with no drops and no recorded interrupter. Not yet explained.
- base-1: 6 drops with probe foreground and no occlusion recorded — cause outside the harness's view.
- tbp-8: another session's RightKit test window ("RK2 target window") took foreground for ~8 s and every frame was dropped although rect/z-order occlusion lasted only 0.33 s. Either DWM drops frames for this non-foreground window, or the occluder escapes the rect test. Investigate GPUI's inactive-window behaviour.

Open before SR0-B closes the frame budget: explain tbp-1's p95 tail, the PresentMon capture gaps, and frame drops while not foreground.

## PresentMon batch 4 (2026-10-09, desktop session; rerun after the SxS rebuild)

Capture integrity improved: 30/30 probe PIDs have PresentMon rows (all-process capture, PID matching), no ETW loss lines. The analyzer still marked 0/30 valid:
- **Harness defect (fixed after the batch):** every run was flagged `sparse-samples` because each sample costs ~16 ms on top of the 50 ms sleep (p50 cadence 66 ms) and the threshold was a fixed 80. `run-desktop-v3.ps1` now samples on a 50 ms deadline and requires ≥ 80 % of the samples the actual workload window implies.
- **Desktop contention from this project:** other SwiftRight windows (FreshOnBridge F1, BridgeSmoke from parallel lanes) sat at the probe's rect; nosamp-3 and nosamp-5 dropped every workload frame next to them while the rect/z-order check reported no occlusion. Desktop GUI lanes must now run one at a time.
- **Interactive use of the host:** KeyShot (incl. its update popup), ChatGPT and the Claude window took foreground or occluded the probe in 12 runs.

Undisturbed runs (probe foreground 100 %, no occlusion, invalid only for the harness defect): tbp-1, nosamp-1, base-2, tbp-2, nosamp-2, tbp-3, tbp-4, tbp-6, nosamp-6, base-7, tbp-7 — zero drops, zero missed vblanks, displayed p95 16.684–16.702 ms, inside §11 rev 1 (≤ 16.764 ms). base-3, nosamp-7 and tbp-8 had 1–3 drops (single 33.3 ms intervals).

Batch 5 needs: the fixed harness, no other SwiftRight GUI lane on the desktop, and an idle host for ~10 minutes.
