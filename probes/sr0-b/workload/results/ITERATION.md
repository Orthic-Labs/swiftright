# R10 performance iteration log (Windows Dell, hybrid laptop: display on Intel Iris Xe, renderer on RTX 4070)

One entry per timed run (3 x 60 s). Source of every number: `D:\Claude\sr0b-workload\runs\<tag>\` (`result-workload.txt`, `report\`, `presentmon.csv`,
per-run `render-frames.csv` when the build has the trace). exe = WorkloadWin.exe, dll = swiftright_render.dll (sha256 prefixes).

## Findings carried between runs

* PresentMon, run 20261009-233129-full r1 (renderer 329E73D0, default pacing): a present is displayed two vblanks later (k=2) exactly when
  `present phase after vblank + msUntilRenderComplete < 16.67 ms`, otherwise three (k=3) and the stream shows a 33 ms gap (a missed vblank).
  `msUntilRenderComplete` is 5.5 ms at the floor, 6.1 at the median, p90 7.4, p99 11.1 (the 13 MB back buffer is copied across PCIe to the iGPU
  that owns the display: NVIDIA copy engine 27 % busy). The presents of that run sat at 7 ms after the vblank (the fixed 5.5 ms wait after WM_PAINT),
  a quarter of them later than 10 ms.
* `DwmGetCompositionTimingInfo` fails on this host for a NULL handle and for the desktop window (HRESULT 0x88980090); the first pacing version therefore ran
  entirely on its fixed fallback wait (`fallback_waits=4109 of 4109`, `paint_start_after_vblank n=0` in the shutdown line).
* Every frame of the workload re-sends ~597 node upserts (continuous scrolling moves every row); host_tick is 5.3-6.5 ms mean on the UI thread.
* r1 of 233129 typed four characters ('.', ',', '.', ' ') that the harness never injects: another process's input (heardright_next_bin took the foreground at
  keys 319/320; foreground thefts by heardright_next_bin, ChatGPT, explorer Task Switching and SearchHost are in every recent run). Not a duplication.

## it1-329e-pace0  (23:46 IST, renderer 329E73D0, exe 8E0264F0, `-PaintPhaseMs 0`, no trace)

A/B of the paint pacing on the same artifacts: `SWR_PAINT_PHASE_MS=0` reached the app (stderr: `paint pacing off (SWR_PAINT_PHASE_MS=0)`, `pacing[phase_us=0 ...]`,
result line `paint_phase_ms=0`). Previous run 233129 (default pacing) in brackets.

| | r1 | r2 | r3 | default pacing r1/r2/r3 |
|---|---|---|---|---|
| missed vblanks | 66 | 243 (voided: SearchHost took the foreground at key 10, 10 keys injected) | **5** | 442 / 383 / 441 |
| W5 p95 (ms) | 16.704 | 333 | 16.751 | 33.33 / 33.33 / 33.34 |
| CAL p95 (ms) | 0.21 | (void) | 0.15 | 13.1 / 12.9 / 12.7 |
| W4 p95 (ms) | 43.3 | (void) | 48.7 | 44.7 / 55.5 / 57.1 |
| leak slope MB/min | 6.43 | 4.64 | 5.83 | 6.01 / 5.74 / 5.90 |
| W6 p99 (ms) | 14.2 | 27.0 | 10.1 | 10.3 / 10.0 / 10.7 |

Result: pacing off is far better (5 vs 441 missed vblanks in the undisturbed run, CAL passes, W4 passes). r1 and r2 ran with other desktop activity
(ChatGPT app and Task Switching took the foreground in r1, total CPU 34 % against 20 % in r3; SearchHost in r2). Undisturbed r3: 3913 of 4205 presents land at
phase 1-2 ms after the vblank, all displayed at k=2; the 5 misses are presents delayed by UI-thread work (phase 4-15 ms).

## it2-d7d7-pace2p5  (23:55 IST, renderer D7D75660 = new edge-clock pacing, default 2.5 ms, trace on; exe 8E0264F0)

New build: the pacing thread loops on `DwmFlush()` itself and posts the paint at `edge + phase` (replaces the failed DwmGetCompositionTimingInfo path); per-frame trace
(`SWR_FRAME_LOG`), allocator counters, memory samples. Host quiet (total CPU 13.5-18.7 %), no user-input record yet in this harness version.

| | r1 | r2 | r3 |
|---|---|---|---|
| missed vblanks | 21 | 29 | 30 |
| W5 p95 (ms) | 16.743 | 16.745 | 16.742 |
| CAL p95 (ms) | 0.12 | 0.13 | 0.13 |
| W4 p95 / p50 (ms) | 42.0 / 38.4 | 46.2 / 42.3 | 45.5 / 34.6 |
| leak slope MB/min | 5.43 | 6.38 | 6.24 |
| W6 p99 (ms) | 9.4 | 8.7 | 9.7 |

Pacing works as designed (edge -> paint start p50 2.97 ms, p99 5.5; present phase after vblank p50 4.2 ms; paint message to handler 0.05 ms p50; UI thread idle at post time in
96.7 % of periods), CAL and W5 p95 pass, versus 383-442 missed and CAL 13 ms with the old pacing. Missed vblanks by cause (miss_class.py, per run):
late paint (UI thread busy at post time, paint 5-9 ms after its edge): 13 / 20 / 22; slow GPU (three consecutive frames with msUntilRenderComplete 10.5-14 ms,
present phase 4.2 + R > 16.67; about every 7.4 s): 8 / 8 / 8. The UI thread's per-period chain is paint (+2.8, 0.7 ms) -> host tick (+3.5, 4.2 ms, includes the 597-node scroll
commit) -> present/AX publish (+8, 1.3 ms) -> every third period a host drain of 4-6.5 ms (the 20 async row updates per second) + its commit + AX publish (ends ~+16) ->
a key handler (ime callback, 3 ms) lands on the tail of that chain 10 times a second. Phase 4.2 leaves 12.5 ms for the GPU; the old fixed 7 ms left 9.7.

## memtest (00:10 IST, diagnostic app launches, not harness runs: no PresentMon, no keys, 75 s each, renderer 93A28B41, `SWR_MEM_DEEP=1`)

Where does the private-bytes growth come from (default: 5.99 MB/min in the measured window)?

| variant | private slope MB/min | Rust live bytes | present mean (AX publish) | Rust allocations in 70 s |
|---|---|---|---|---|
| default (AX every commit) | 5.99 | 7.2 MB flat | 1.26 ms | 52.8 M |
| `SWR_AX_OFF=1` | 4.87 | 7.0 MB flat | 0.005 ms | 16.7 M |
| `SWR_AX_MIN_MS=100` | 4.88 | 7.0 MB flat | 0.14 ms | 21.3 M |

* The Rust heap does not grow (live bytes flat 7-12 MB; `rust_live` slope 0.2-0.8 MB/min). The growth is in the process heap (`GetProcessHeaps`[0], shared by Swift, Rust and
  COM): allocated +2.2 MB/min but committed +5.7 MB/min between 10 s and 65 s (fragmentation under allocation churn), levelling off (allocated flat after ~35 s). Image and
  mapped memory are constant. Not a leak in the usual sense: a warm-up curve that is still bending down at 70 s.
* AX is active in every run (a UIA client is attached to the desktop): publishing the whole tree on every commit is a tenth of the UI thread and ~1 MB/min of the growth.
  Throttling AccessKit publication to once per 100 ms (trailing publish, so a client sees the newest state within 100 ms) removes it.
* The remaining ~4.9 MB/min is Swift/DirectWrite/driver churn that this renderer does not own; the renderer's own churn is cut separately (shared strings/runs on commit).

## it3 interleaved A/B (00:23-00:41 IST, renderer 709E05CB, exe 8E0264F0; order A1 B1 A2 B2; same session, harness with context recording, no quiet-host gate)

Renderer 709E05CB = trace + allocator counters + AX publication every 100 ms (trailing) + semantic strings/runs shared on commit; `SWR_PAINT_PHASE_MS` default 0.
A = default (pacing off). B = `-PaintPhaseMs 1.0` (edge-clock pacing, paint 1.0 ms after the DWM composition edge, present ~2.7 ms after the vblank).
`nvspcap64.dll` (NVIDIA capture/overlay hook) is loaded in the workload process in every run; NVIDIA Overlay, nvcontainer and NVDisplay.Container are running.
Host load over the key script: total CPU 14-21 %, `membrane` 6 % of the machine, everything else < 0.6 %.

| sub-run | missed vblanks | W5 p95 | CAL p95 | W4 p95 (p50) | leak MB/min | disturbed (user input) |
|---|---|---|---|---|---|---|
| A1 r1 | 1 | 16.751 | 0.15 | 43.3 (39.6) | 6.35 | no |
| A1 r2 | 5 | 16.746 | 0.15 | 48.9 (45.1) | 6.58 | no |
| A1 r3 | 1 | 16.750 | 0.16 | 45.4 (41.7) | 6.02 | no |
| B1 r1 | 6 | 16.741 | 0.13 | 47.3 (35.3) | 6.32 | no |
| B1 r2 | 7 | 16.758 | 0.13 | 47.5 (43.9) | 9.90 | no |
| B1 r3 | 4 | 16.746 | 0.13 | 46.4 (42.5) | 5.41 | no |
| A2 r1 | 2 | 16.744 | 0.15 | 48.8 (36.7) | 6.63 | no |
| A2 r2 | VOID: window occluded (Adrian Alt-Tabbed to the Claude app at key 82; PresentMon: 3498 presents, 256 displayed) | | | | | yes, 118 input events |
| A2 r3 | 8 | 16.747 | 0.17 | 40.7 (36.8) | 6.51 | no (one foreground change: pulse-hub) |
| B2 r1 | 13 | 16.767 | 0.15 | 47.4 (35.2) | 6.83 | yes, 50 input events, 7 foreground changes |
| B2 r2 | 6 | 16.753 | 0.12 | 41.4 (37.7) | 7.26 | no |
| B2 r3 | 10 | 16.744 | 0.12 | 47.2 (35.0) | 5.98 | no |

Medians (disturbed sub-runs kept, the void one dropped): A missed 2 (1, 1, 2, 5, 8), W4 p95 45.4, leak 6.5; B missed 6.5 (4, 6, 6, 7, 10, 13), W4 p95 47.2, leak 6.6.
Decision: pacing stays OFF (default 0): fewer missed vblanks (2 vs 6.5), lower W4 p95 (45.4 vs 47.2). The earlier 2.5 ms pacing (it2: 21-30 missed) is worse still.
All other thresholds of the valid A sub-runs pass (W1 all, W2, W3, W6, CAL, W5 p95, W4 p95, key delivery, window metrics). Failing: missed vblanks (1-8, target 0) and the leak slope (6.0-6.6, limit 5).
Where the remaining misses come from (trace of A1, miss_class.py): every one is a paint delayed 3-7 ms by the UI thread (a 3 ms key handler or a 4-6 ms host drain on the edge) in a
frame whose render-complete time is also high (9-12 ms against a median of 6.2: three-frame GPU bursts every few seconds); either alone fits in the period.
Rust allocations per 70 s: 55.5 M (it2) -> 12 M (709E): -78 % (shared strings/runs + AX every 100 ms). The private-bytes slope did not move, so the growth is not the renderer's own heap.

## it4a-709e-off-nores  (00:43 IST, renderer 709E05CB, default config, `-NoResources`: no GPU-counter sampler) - is the measurement tool the cause?

Missed vblanks 2 / 13 / 1 (r2 disturbed: 96 user input events, foreground change to wezterm-gui), W5 p95 16.743 / 16.731 / 16.753, CAL 0.14 / 0.18 / 0.13, W4 p95 47.9 / 48.7 / 48.7.
Same as the sampled A arm (1 5 1 2 8): the resource sampler is not what causes the misses, nor the leak (renderer trace private-bytes slope 6.5 / 5.2 / 5.6 MB/min without it).

## it5-7533-final  (00:48 IST, renderer 7533963D = final source, exe 8E0264F0, defaults: pacing off, AX 100 ms; `r10-20261010-renderer7533-windows.txt`)

Final source = 709E05CB plus comment/doc edits only; the rebuild is not bit-identical (7533963D), so this run measures the artifact that goes with the committed source.

| | r1 | r2 | r3 |
|---|---|---|---|
| missed vblanks | 2 | 1 | 7 (disturbed: 38 user input events, `claude` took the foreground; a 2.0 s presentation gap) |
| W5 p95 (ms) | 16.728 | 16.726 | 16.730 |
| CAL p95 (ms) | 0.15 | 0.17 | 49.2 (same gap) |
| W4 p95 (ms) | 43.7 | 48.7 | 49.0 (p99 1532: the gap) |
| leak slope MB/min (sampler) | 5.46 | 5.61 | 7.35 |
| user input | 2 events | none | 38 events |
| total CPU avg % | 9.3 | 13.0 | 9.9 |

## What is left (targets from the brief: W4 p95 <= 50, W5 0 missed and p95 <= 16.77, CAL <= 2, W1 all pass, leak <= 5 MB/min, on 3 consecutive runs)

* Met on every undisturbed sub-run: W1 (all), W2, W3, W6, CAL (0.12-0.18 ms), W5 p95 (16.73-16.75), W4 p95 (40.7-48.9), key delivery, window metrics.
* Not met: missed vblanks (1-8 per 60 s in undisturbed runs, median 2) and the private-bytes slope (5.2-6.6, median ~6).
* Missed vblanks: each one is a 3-7 ms late paint (key handler or host drain on the paint edge) on top of a GPU burst (msUntilRenderComplete 9-12 ms for three frames; median 6.2 ms, floor 5.5 ms,
  p99 11 ms, max 14). The 6 ms floor is the 13 MB back buffer crossing PCIe from the RTX 4070 to the Intel iGPU that owns the display (NVIDIA copy engine 27 % busy); `nvspcap64.dll`
  (NVIDIA capture/overlay hook) is injected into the process as well. Whether the overlay is part of the burst/floor cannot be told without turning it off: ask Adrian for ONE run with the NVIDIA overlay
  / in-game capture off (no setting was touched here). Rendering on the Intel iGPU would remove the copy (GPUI enumerates adapter 0, which is the NVIDIA on this machine).
* Private bytes: Rust heap flat (7-13 MB); Swift graph objects flat (headless bench heap census); growth is in the shared process heap (committed +5.7 MB/min, allocated +2.2) and levels off
  after ~35 s, i.e. a warm-up curve that still bends at 70 s and sits inside the 10-70 s window. Candidates not owned by the renderer: DirectWrite/D3D/UIA allocations, the NVIDIA hook.
* Interference seen in the runs (all recorded, none voided except A2 r2 occluded): Adrian's Alt-Tab/Claude/wezterm use, ChatGPT/codex, heardright_next_bin (it typed '.', ',', '.', ' ' into the window in 233129 r1).

## Run accounting

Timed workload invocations (3 x 60 s each): it1, it2, it3a1, it3b1, it3a2, it3b2, it4a, it5 = 8 in all, 6 of them after the coordinator's run-cap message (it3a1 .. it5 counting the A/B quartet, the no-resource run and the final one).
Not measurement runs: one harness smoke test (1 x 6 s, no PresentMon), one memory diagnostic (3 app launches x 75 s, no PresentMon, no keys), headless Mac bench runs.
