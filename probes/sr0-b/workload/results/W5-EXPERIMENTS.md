# W5 experiments (sr0-findings.md section 8.4 steps 1-5), 10 Oct 2026

Host: Dell XPS 15 9530 (BIOS 1.31.0), tuple 08: `D:\Claude\sr0-r08\workload`, WorkloadWin.exe `0815DF49...`, renderer `E280F4A9...` (both passed explicitly to
`run-workload.ps1 -Base ... -ExpectDll ...`; ARTIFACT_OK in every run). Workload, window (client 2560x1396 px at 2.5 scale), 10 s warm-up + 60 s measured, 10 keys/s, W4/W5
criteria unchanged. No source change, no NVIDIA setting change. Desktop lock held `W5 2026-10-10T15:08:33` to ~15:21, then written `free`.
Raw data: `results/w5/` (this directory). PresentMon CSVs (about 5 MB each) stay on the Dell under `D:\Claude\sr0-r08\workload\runs\w5ab-<tag>\presentmon.csv`.
Scripts (new, probes only): `scripts/gpu-routing.ps1`, `scripts/run-interactive.ps1`, `scripts/w5-ab.ps1`, `scripts/dll-strings.ps1`.

## Step 1: routing facts

Sources: `w5/routing-interactive.txt` (run inside the interactive session, the same context as the workload), `w5/routing-ssh-session0.txt` (same script over SSH, session 0),
`w5/dxdiag-interactive.txt` (`dxdiag /t`), per-run `w5/<tag>/resources-meta.json`, `resources.csv`, `stderr.txt`.

| Fact | Value |
|---|---|
| Adapters (DXGI) | RTX 4070 Laptop, LUID `0x00000000_0x00018254`, 7949 MB, driver 32.0.16.1692 (616.92), WDDM 3.2; Intel Iris Xe, LUID `0x00000000_0x00017e7d`, 128 MB, driver 32.0.101.7084 (1/15/2026), WDDM 3.2; Microsoft Basic Render, `0x0001821f` |
| Adapter owning the display output | **Intel** `0x17e7d`. `QueryDisplayConfig` active path: source and target adapter LUID both `0x17e7d` (panel `DISPLAY\SDC414D`, internal, 3456x2160 at 60 Hz). nvidia-smi: `display_active = Disabled`. dxdiag: Intel "Output Type: Internal", NVIDIA "Current Mode: Unknown" |
| DXGI enumeration order in the interactive session | index 0 = NVIDIA (`0x18254`), 1 = Intel, 2 = Basic Render. DXGI exposes `\\.\DISPLAY1` under the NVIDIA adapter's `EnumOutputs` even though the display path is on Intel (hybrid mapping), so an output listed under an adapter does not prove ownership |
| DXGI order over SSH (session 0) | **Intel first**, NVIDIA second, no outputs. Adapter order depends on the session, so any enumeration taken over SSH says nothing about the workload process (relevant to G6) |
| Adapter the renderer used | Default runs (tuple 08): RTX (`gpu_adapter` in RESOURCES). In this series the per-process GPU Engine counters show the process's work on `0x18254` in R runs (3D 2.1 %, copy engine 27.0-27.5 %, no activity on Intel) and on `0x17e7d` in I runs (3D 33.6 %, copy 0 %) |
| Buffers | gpui composition swap chain, 3 flip-sequential buffers (section 2.3 source citation, not re-read here), client 2560x1396 px (`stderr.txt`: `client=2560x1396px`) = 14,295,040 B (13.6 MiB) per buffer. `meta.json` reports 2400x1600 (960x640 DIP at 2.5); the renderer's logged client size is the one used here |
| HAGS | `HwSchMode` value absent under `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` (OS default). dxdiag: Intel `DriverSupportState:AlwaysOff Enabled:False`; **NVIDIA `Stable Enabled:True`**. So HAGS is on for the RTX; PresentMon's HAGS timing caveat applies to RTX runs |
| Other | dxdiag "Microsoft Graphics Hybrid: Supported"; Intel MPO 3 planes; power scheme High performance, on AC (battery status 2, 94 %); no `UserGpuPreferences` entry for WorkloadWin.exe before the experiment |
| Renderer startup log | Prints window, DPI, pacing and AX lines only. It does not print an adapter, LUID or buffer size (the adapter comes from the sampler's GPU Engine counters) |

Result for the section 2.4 hypothesis: the NVIDIA copy engine is busy 27 % of the time for the workload process while its 3D engine is 2 %. That measures the cross-adapter
copy cost (RTX renders, Intel owns the display) and shows shading throughput is not the limit on the RTX. Causation of individual misses is still not established.

## Step 2: Intel versus RTX, interleaved (order I R I R I R, one 60 s measured run per invocation, same session)

Mechanism: `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, value name = full path of WorkloadWin.exe, data `GpuPreference=1;` (I, power saving, Intel) or `GpuPreference=2;`
(R, high performance, RTX). Before: `<absent>`. After: `<absent>` (the value this task added was removed; `w5/pref-log.txt`). Both settings took effect on the first run (resource counters above).
Per-app preference behaviour was UNVERIFIED against a Microsoft page; it is now confirmed on this host by the counters.

| run | adapter (counters) | missed vblanks | W5 p95 ms | W4 p95 ms | msUntilRenderComplete p50 / p95 / p99 / max | dropped presents | overlay `nvspcap64.dll` |
|---|---|---|---|---|---|---|---|
| I1 | Intel | 4 | 16.7535 | 48.43 | 8.34 / 8.54 / 8.70 / 9.74 | 4 of 3600 | not loaded |
| R1 | RTX | 2 | 16.7424 | 42.65 | 6.11 / 9.52 / 11.06 / 19.62 | 2 of 3601 | loaded |
| I2 | Intel | 5 | 16.7227 | 48.53 | 8.36 / 8.54 / 8.73 / 17.75 | 5 of 3601 | not loaded |
| R2 | RTX | 1 | 16.7338 | 48.26 | 6.10 / 9.54 / 11.06 / 15.06 | 1 of 3601 | loaded |
| I3 | Intel | 3 | 16.7375 | 48.50 | 8.37 / 8.57 / 8.74 / 10.33 | 3 of 3601 | not loaded |
| R3 | RTX | 3 | 16.7452 | 48.72 | 6.14 / 9.44 / 11.09 / 14.13 | 3 of 3601 | loaded |

Medians: Intel 4 missed (3, 4, 5), RTX 2 missed (1, 2, 3). Every run misses the W5 criterion (0 missed); every run passes W5 p95 (limit 16.7646), W4 p95 (limit 50), CAL, W1.
No run was disturbed (no user input, no foreground change). I1 started with `swift-build`/`swift-frontend` running on the host (context only); the other five saw none.

Reading (labelled):
- Measured: moving rendering to the Intel adapter removes the cross-adapter copy and the 9-12 ms render-complete bursts (Intel p99 8.7 ms, tight), but does not reduce missed vblanks; the RTX runs had equal or fewer (1-3 vs 3-5).
- Inference: with render-complete flat at 8.4-8.7 ms on Intel the remaining misses there are not GPU-copy bursts; this fits the earlier finding that late UI-thread paints cause the misses (step 7 of the plan).
  Three runs per arm cannot separate 2 from 4 statistically; the difference is not claimed as an effect.
- Confound: the overlay hook loads only in the RTX runs (NVIDIA processes are present in all). Adapter and overlay therefore move together in this series; step 3 below is observation only.
- Two Intel runs have a render-complete max spike (17.75 ms in I2); the RTX max is 14.1-19.6 ms.

## Step 3: overlay hook (observation only, nothing changed)

`nvspcap64.dll` is loaded in the workload process in every RTX run (pre and post: 109 modules) and in no Intel run (91 modules). `nvcontainer`, `NVDisplay.Container` and `NVIDIA Overlay`
processes were running throughout. An overlay-off run (U2) is still PENDING: it needs a NVIDIA setting change, which was excluded here.

## Step 4: direct-dGPU display routing (report only)

Not available on this machine by anything I can change in software, and I changed nothing. Evidence: the XPS 15 9530 routes the internal panel through the Intel iGPU
(`QueryDisplayConfig` path on `0x17e7d`; NVIDIA `display_active = Disabled`, no NVIDIA display path); dxdiag lists "Microsoft Graphics Hybrid: Supported" (an iGPU-owned-display hybrid) with the
RTX as the render-offload device. I found no MUX or Advanced Optimus indicator in WMI, dxdiag or nvidia-smi (`display_mode` query reports "deprecated"). Whether the 9530 has a MUX was not looked up (no source fetched; UNVERIFIED). A BIOS or Dell Optimizer GPU mode setting could not be inspected over SSH. Conclusion: treat dGPU-direct display as unavailable here; the supported alternatives are
render on the iGPU (step 2, I runs) or accept the copy (R runs).

## Step 5: waitable swap chain, latency 1 versus 2 (not run; proposal)

Not exposed without source changes. Evidence: `w5/dll-strings.txt` (scan of the `E280F4A9` renderer DLL) holds one gpui environment knob, `GPUI_DISABLE_DIRECT_COMPOSITION`, and no latency or swap-chain flag
setting (a DXGI flag constant or a COM vtable call leaves no string, so this shows only that no environment switch exists, which also matches section 2.3). gpui 0.2.2 source was not re-read in this task.
Proposal (renderer or gpui patch, Adrian's decision per the exact-pin rule): create the swap chain with `DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT`, call `IDXGISwapChain2::SetMaximumFrameLatency(1|2)`, wait on
`GetFrameLatencyWaitableObject()` before drawing, and log `Present` duration and `msUntilRenderComplete` per frame; run 3 + 3 interleaved on RTX with the workload and criteria above.
The measured need is weak: Present returns in the same frame on every run (3D 2 %), so queue depth is not the observed limiter; priority below the late-paint fix.

## Files

`w5/routing-interactive.txt`, `w5/routing-ssh-session0.txt`, `w5/dxdiag-interactive.txt`, `w5/pref-log.txt`, `w5/dll-strings.txt`, and per run (`w5/I1 R1 I2 R2 I3 R3/`):
`analysis-console.txt` (thresholds, resources, context, render-complete line), `result-workload.txt`, `orchestrator.log`, `host-quiet.txt`, `resources.csv`, `resources-meta.json`, `stderr.txt`, `modules.txt`, `meta.json`.
