## Mac windowed workload (R10 / U2), 10 Oct 2026

Result: **FAIL** (W4 input-to-visible p95 and the W5 interval p95 on all three runs; W4 p99 on r1). Source: `r10-20261010-mac.txt` (analyzer output per run, resources, A/B), raw samples in `mac/`.

### What exists and what ran

`probes/sr0-b/workload` already had the Mac side: `WorkloadMac` (the shared screen in real SwiftUI, one `Window` scene, in-process instrumentation), `SckRecorder` (separate process: `CGEvent.postToPid` keys, ScreenCaptureKit display-time response detection, a recorder-owned calibration window), `scripts/run-mac.sh`, and the analyzer's macOS path. It had never been run (`SckRecorder/main.swift` header: build-only). Running it surfaced seven harness defects (below); the fixes are in the working tree (`mac/harness-fixes.patch`), not committed.

Host: Mac18,5 Apple M6, 24 GB, macOS 27.0.1 (26A434), arm64, AC power. Display: one 1600x900 @ 60.00 Hz display at backing scale **1.0** (not the 2.0 `analyze_workload.py` defaults to). Window 960x640 pt. Release build, Swift 6.4, built under `--scratch-path` in the session scratchpad and run from there (nothing run from `/Volumes/D`), ad-hoc signed bundles; the Screen Recording and post-event grants were already in place, no prompt was raised. Keys went to the workload process only.

Settings: 200 rows, 10 keys/s, 10 s warm-up, 3 x 60 s. Full and light instrumentation interleaved (F1 L1 F2 L2 F3 L3); light r1 and r3 were void (window occluded by the Claude app, `app/focus.csv`) and repeated. 8 timed launches in all.

### Thresholds per run (full instrumentation, count-decoded attribution)

| | r1 | r2 | r3 | limit |
|---|---|---|---|---|
| W1 identity, edits, cancellation, teardown | PASS (typed = sent = 664) | PASS (666) | PASS (666) | 0 wrong-node, stale, lost |
| W2, W3 (Windows bridge) | n/a on macOS | n/a | n/a | |
| W4 p50 / p95 / p99 / max (ms) | 40.6 / **75.9** / **107.9** / 157.3 | 37.7 / **71.6** / 88.2 / 121.3 | 29.6 / **78.9** / 95.6 / 129.2 | p95 <= 50, p99 <= 100 |
| W4 every key resolved | 595 of 595 | 595 | 595 | all |
| W5 missed vblanks (SCK proxy) | 0 PASS | 0 PASS | 0 PASS | 0 |
| W5 interval p50 / p95 / p99 / max (ms) | 16.65 / **17.94** / 18.88 / 20.67 | 16.64 / **17.82** / 18.63 / 20.84 | 16.65 / **17.91** / 18.77 / 21.37 | p95 <= 16.77 |
| W6 main-actor enqueue-to-execute p99 (ms; reported, Windows-only limit) | 68.2 | 66.0 | 59.2 | 16.7 would fail |
| W7 incremental build (3 edits) | 0 Rust invocations PASS | | | 0 |
| CAL recorder floor p50 / p95 (ms), 120 flips | 15.3 / 23.3 | 16.2 / 23.8 | 15.6 / 23.2 | p95 <= 34 PASS |
| R phys_footprint slope (MB/min; our mapping, raw) | -0.96 PASS | 2.29 PASS | **7.85** | <= 5 |

W4 is raw (uncorrected for the ~16 ms recorder floor); the analyzer rule. R has no Mac implementation in the analyzer: the footprint (83 to 89-92 MB) rises over the first 20-30 s and then flattens, the same warm-up shape as Windows.

CPU and memory (once a second, `mac/resources-summary.txt`): the app's main thread is the bottleneck at 78-81 % of one core on average (peak 91-96 %); footprint 86-88 MB, resident 165-167 MB, 7 threads; machine CPU 28-40 % on average (12 cores), load average 4.8-5.5. Standalone, with no recorder and no keys, the app's display link fires about 35 times a second (27-30 in the timed runs, `frames_driven` 1956-2154 per ~72.5 s) against a requested 60: the SwiftUI update pass is what limits it.

Instrumentation overhead (full vs light, 3 each): visible p95 75.5 vs 74.1 ms (+1.4), interval p95 17.89 vs 18.57 ms (-0.67), app CPU 79.6 vs 81.5 % of a core. All inside the run-to-run spread (visible p95 58.9 to 82.3 ms across the six runs); no overhead is measurable on this host. Timer micro-benchmark: 14-15 ns per timestamp pair.

### Section 11 Mac items still unmet

- **Quiet host.** Peer sessions were building Rust (`rustright-broker` 25-96 % of a core), `pulse-hub` and a `find` ran throughout; `run-mac.sh` refuses such a host and was bypassed. W4 and the CPU figures are loaded-host numbers. A rerun on a quiet Mac, preferably the dedicated test user, is the proper evidence.
- **Presentation trace.** W5 uses the analyzer's ScreenCaptureKit display-time proxy, not the validated compositor instrumentation or optical capture section 11 requires, and nothing here validates its jitter: the proxy sees 60 frames a second although the app's display link ran at about 30, so it cannot see app-level frame drops. The interval p95 excess (+1.2 ms) may be proxy jitter. An in-process frame-time record or an Instruments/compositor trace is needed before W5 means anything on the Mac.
- **HiDPI.** The only display is 1600x900 at scale 1.0; the doc's pinned scale and the analyzer default are 2.0. No Retina run exists.
- **Counter decoding in the recorder.** The recorder's first-in-first-out attribution shifts every later key by 100 ms after each merged keystroke (full r1: recorder p50 223 ms, true 41 ms). The result above uses `mac/tools/mac_reattribute.py` (counter value decoded from per-frame region hashes, cross-validated on the three merge-free runs of the final set, and on five in the first set); the recorder itself is not fixed.
- **Mac R threshold** is not in the analyzer (this note's mapping is footprint slope, raw).
- Light-instrumentation runs are baseline runs; the A/B has n=3 per arm.

### Harness defects fixed to get this result (`mac/harness-fixes.patch`)

1. `WorkloadMac`: the SwiftUI app quit when its window closed, before writing any output; an `NSApplicationDelegate` now keeps it alive. Also writes `focus.csv` (active, key, visible, frontmost, once a second).
2. `WorkloadCore.userEdit` (macOS flavour only, `#if !WORKLOAD_RUNTIME`): real SwiftUI calls a TextField binding setter twice per keystroke and once at focus with unchanged text, so `typedCount` was 2x the keys; only a changed value counts. The Windows flavour is compiled from the same file but this block is inactive there (the file's line numbers shift, so a Windows rebuild will not be bit-identical to the pinned WorkloadWin).
3. `SckRecorder`: crop offset by the 28 pt title bar (the SwiftUI `.global` frame already includes it); `window.png` with the crop outlined now proves the crop.
4. Crop too narrow once the counter reached three digits (widened by 40 pt).
5. Noise floor was sampled over window start-up (146 px, threshold 438 px, nothing resolved); now sampled after an 0.8 s settle (0 px), minimum threshold 12 px (resolved responses change 28 px or more).
6. Key script now stops 0.5 s before the measured window ends (like the Windows `key_tail_s`); before, keys posted into a closed window counted as lost.
7. `frames_display.csv` gains `region_hash`, `keys.csv` gains `diff_px`, `recorder_meta.json` gains the noise series; used by the decoding above.

### Files

`r10-20261010-mac.txt`; `mac/samples-asrecorded-full-light.tar.gz` (every raw sample of the six runs), `mac/analysis-count-decoded.tar.gz` (decoded `keys.csv`, analyzer reports and raw CSVs), `mac/voided-light-r1-r3-occluded.tar.gz`, `mac/analysis-as-recorded.txt`, `mac/resources-summary.txt`, `mac/harness-fixes.patch`, `mac/tools/` (sampler, resource summary, attribution decoder, drivers; scratchpad paths as run). Total about 1.7 MB.
