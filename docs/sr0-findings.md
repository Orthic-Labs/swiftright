# SR0 findings: everything tried, what worked, what did not, and what is missing

Compiled 10 October 2026 from the repository at HEAD `593e3ab` (the task named `2da92ab`; the only later commit is the R6 result, `probes/sr0-o/R6-RESULT.md`). Sources: `docs/*`, every `RESULT*.md` and `ITERATION.md` under `probes/`, `examples/` and `qualification/`, `render/README-abi-v0.md`, `render/swiftright-render/README.md`, `git log` (219 commits), `probes/sr0-s/COMPARISON.md`, the `gpui 0.2.2` crate source, and Microsoft Learn pages fetched on 10 Oct 2026. Nothing was rerun to write this. Every claim cites a path (with line where useful) or a commit. A claim with no citation is marked UNVERIFIED.

Conventions: "tuple 08" is the final SR0 snapshot (`docs/sr0-snapshot.md` section 2d). Short hashes are sha256 prefixes of binaries or git commits (the context says which). "Dell" is the Windows host (Dell XPS 15 9530, `docs/sr0-snapshot.md:105`). "Mac" is the Mac mini, macOS 27.0.1, arm64.

---

## 1. Outcome

SR0 is **OPEN**, not closed (`docs/sr0-status.md:7`). The final tuple is tuple 08: renderer DLL `E280F4A9…` (ABI 0.6, built from `9c261d4` on `02b3cc0`), runtime `b8702bb`, FreshOnBridge `7673A2D5…`, BridgeSmoke `21992F16…`, WorkloadWin `0815DF49…`, SliceApp MSIX 0.1.0.0 `c80c6947…` / 0.1.1.0 `0ff65165…`, DMGs `b976ac70…` / `75f3cd75…`, `@rightkit/release` 0.2.146 (`docs/sr0-status.md:9`, `qualification/tuple-final.json`). The Windows 20-run matrix, smoke, text geometry, modal paths, real-IME checks, runner, Mac oracle re-record and the Mac package record pass on it. Two criteria fail and are recorded as known limitations pending a decision by Adrian: W5 "zero missed vblanks" (5, 1, 1 per 60 s run) and the MSIX interrupted-update check W08.

| Stage | Status on tuple 08 | Key evidence |
|---|---|---|
| SR0-D dependencies and hosts | PASS (Windows x64, Mac arm64) | `probes/sr0-d/*`; `docs/sr0-status.md:13` |
| SR0-C slice contract | DRAFT v0.1; freeze proposal v1.0 NOT frozen | `conformance/sr0-slice/CONTRACT.md:3`; `docs/sr0-freeze-slice-contract-v1.md:7` |
| SR0-O oracle and comparator | PASS for F1 cross-compare (0 diffs); Mac oracle 16 configs x3 equal accepted baselines; F6 100-run sample decided (see below) | `probes/sr0-o/R6-RESULT.md`; `qualification/out/r8-tuple08/compare-F1.json` |
| SR0-B bridge and measurement | PASS: smoke 40/40, timeout 41/41, TextGeom06 20/20, Modal06 20/20 | `examples/BridgeSmoke/result-smoke-rev08.txt:83-84`; `examples/BridgeGeoModal/result-textgeom08.txt:93`, `result-modal08.txt:268` |
| SR0-S seed comparison | Fresh runtime selected; SwiftCrossUI fork early-disqualified (never ran on the real renderer); matrix 319/320 | `probes/sr0-s/COMPARISON.md`; `probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md` |
| SR0-P packaged qualification | NOT PASS: Windows offline 13/14, W08 FAIL; network W00/W01/W12 PASS; Mac DMG 12/12 and R7 10/10 PASS | `examples/SliceApp/RESULT-R5-08.md`; `RESULT-R7.md` |
| SR0-A automation | Runner run on tuple 08: win-replay 48/48, compare 0 diffs, smoke 40/40 and 41/41, package macOS 12/12, Windows FAIL on W08 only; 119 unit tests | `docs/sr0-status.md:19`; commit `2da92ab` |
| SR0-N native interaction (R9) | IME F7 20/20, F7live 20/21, F8 18/19, Narrator 8/8 automatable; Narrator speech not machine-verifiable | `probes/sr0-b/native-interaction/out/*-tuple08.txt` |
| SR0-W workload (R10) | NOT MET: W5 fails; leak slope 3.21-4.42 MB/min passes | `probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt:40,79,118,285` |

### R6 (Mac oracle, added 10 Oct 2026, commit `593e3ab`, `probes/sr0-o/R6-RESULT.md`)

- mac-oracle stage: all 16 configs, 3 runs each, 3/3 self-test PASS and every canonical trace equals the accepted baseline.
- F1 signed re-record (signed `F1MacRecord.app`, Developer ID, team 6KLGD3LLKF): 3 recordings, 0 diffs against the accepted Mac trace and 0 diffs against the tuple 08 Windows trace; the runner compare stage passes with 0 diffs. The accepted baseline was not replaced.
- F6 100-run sample: 100/100 self-test PASS; in the burst-insert step the A/B completion order is 96 A-first, 4 B-first (runs 13, 23, 24, 25, clustered). Lead decision: the contract treats that pair as unordered. The first animation pair was A-then-B in all 100 runs. The candidate `conformance/candidates/F6/20261010T082727.113Z` is untracked and not promoted.
- **Open gap:** there is no Windows schema-v0 trace for F2 to F9, so the Mac-to-Windows cross-compare covers F1 only (`probes/sr0-o/R6-RESULT.md`, "Not compared").
- Consequence for the docs: `docs/sr0-status.md` rows SR0-O and item 1/5 of the PENDING table, `docs/sr0-freeze-slice-contract-v1.md` section 4 blocker 2 and limitation 4, and `docs/sr0-close-plan.md` lane R6 still say PENDING and predate this result.

---

## 2. Architecture as built

### 2.1 Layers

```
Shared Swift app source (SwiftUI screens)
  macOS: real SwiftUI / AppKit (Apple types)            [docs/architecture.md:115-117]
  Windows: SwiftRight runtime (Swift)                   [probes/sr0-s/fresh-runtime]
      identity, @State, bindings, environment, observation, layout, transactions, focus
        |  commit: one versioned transaction per flush (resolved tree, physical px)
  SwiftRightBridge (Swift package, LoadLibraryW/GetProcAddress, no import-table link)
                                                        [packages/SwiftRightBridge; render/README-abi-v0.md:12]
        |  C bridge ABI 0.6 (render/swiftright-abi/include/swiftright.h; 16 functions, stats 200 B)
  swiftright_render.dll (Rust cdylib: gpui =0.2.2, accesskit =0.25.1, accesskit_windows =0.35.1)
                                                        [render/swiftright-render/Cargo.toml]
        |  Direct3D 11 + DirectComposition + UI Automation (via AccessKit)
  GPU / DWM / UIA clients
```

The Swift runtime owns layout, identity and semantics; Rust owns font shaping, rasterisation, input, IME and AccessKit publication (`docs/architecture.md:132`, `:158-164`). The loop: `swr_run` blocks on the initial thread; the Swift main dispatch queue is drained from a GPUI foreground task through libdispatch's private `_dispatch_main_queue_callback_4CF`, behind a non-reentrant guard on both sides (`probes/sr0-d/dispatch-drain/RESULT.md` sections 1-2; `render/README-abi-v0.md` "Loop"). macOS uses none of this: Apple SwiftUI renders there (the Mac packages carry no renderer, `docs/sr0-snapshot.md:95`).

### 2.2 ABI history (all append-only after 0.4)

| Rev | Commit | Content |
|---|---|---|
| v0 | `b907913` | Header, Rust renderer, Swift bridge, smoke 19/19 |
| 0.4 | `b9651bd` | `identifier` (UIA AutomationId), labels, empty-edit TextPattern |
| 0.5 | `10c4877` | `shutdown_complete`, `live_nodes`, `SWR_PRIM_UNDERLINE`, post-close pump |
| 0.6 | `4df7e67` | Roles 8-14, toggled/selected/disabled, images, menu and dialog modals, `\n` in measure; header last changed `862997c` |
| (no ABI change) | `02b3cc0`, `9c261d4` | Modal lost-wake fix; AX trailing publish re-arm. Startup validation stays `abi 0.6 fn_count=16 stats_size=200` |

Source: `docs/sr0-freeze-bridge-interface.md` sections 1, 5. The header is single source of truth; the loader validates exact struct sizes and function count, so any minor bump needs a host rebuild (`docs/sr0-freeze-bridge-interface.md:103`).

### 2.3 How rendering reaches the GPU on Windows

Evidence base: the `gpui 0.2.2` crate (`src/platform/windows/`). It is not in the Mac cargo registry (`~/.cargo/registry` holds no gpui), so the `.crate` was downloaded from `static.crates.io` into a scratch directory and its sha256 `979b45cf…bee707` was checked equal to the checksum in `render/swiftright-render/Cargo.lock:2108`. Line numbers below are in that crate. The Windows build resolves `gpui 0.2.2` plus `windows 0.61.3` (`Cargo.lock`, gpui dependency list), and `blade-graphics`/`metal`/`wayland` entries in the lock are for other platforms and are not compiled for Windows (`probes/sr0-d/render-composition/DEPENDENCIES.md`, "63 packages were not downloaded for the Windows target").

| Layer | What gpui 0.2.2 does | Source |
|---|---|---|
| Graphics API | **Direct3D 11**, not 12. `D3D11CreateDevice` with feature levels 11_1, 11_0, 10_1, flags `D3D11_CREATE_DEVICE_BGRA_SUPPORT` (+ DEBUG when available) | `directx_devices.rs:149-172`, `:60-75` |
| Adapter choice | `CreateDXGIFactory2` returns an `IDXGIFactory6`, but the code calls plain `EnumAdapters(index)` from 0 and takes the **first adapter that can create a D3D11 device**. `EnumAdapterByGpuPreference` is not used. No GPU-preference setting is read | `directx_devices.rs:109-146` (`get_adapter`, `:123-139`) |
| Shaders / drawing | HLSL (`shaders.hlsl`, `color_text_raster.hlsl`, `alpha_correction.hlsl`); batches for shadows, quads, paths (intermediate MSAA texture), underlines, mono and poly sprites, surfaces. Text via DirectWrite (`direct_write.rs`) | `directx_renderer.rs:286-305`; `ls platform/windows` |
| Swap chain (default) | `IDXGIFactory2::CreateSwapChainForComposition`, `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`, 3 buffers, `B8G8R8A8_UNORM`, premultiplied alpha, `DXGI_SCALING_STRETCH` | `directx_renderer.rs:1021-1044`, `BUFFER_COUNT = 3` at `:1389`, format at `:30` |
| Composition | **DirectComposition**: `DCompositionCreateDevice`, `CreateTargetForHwnd`, a visual that holds the swap chain, `Commit()` | `directx_renderer.rs:93-94`, `:150-154`, `:790-807`, `:1017-1018` |
| Fallback | Environment variable `GPUI_DISABLE_DIRECT_COMPOSITION` switches to `CreateSwapChainForHwnd`, also `FLIP_SEQUENTIAL`, `DXGI_SCALING_NONE`, alpha ignored | `directx_renderer.rs:29`, `:1047-1073`; read at `platform.rs:138` |
| Present | `swap_chain.Present(0, 0)`: sync interval 0, no vblank blocking inside Present | `directx_renderer.rs:205` |
| Frame pacing | A thread named `VSyncProvider` loops on `DwmFlush()` and calls `RedrawWindow(RDW_INVALIDATE)` on every window; `WM_PAINT` then draws. Fallback `Sleep(interval)` if the wait returns early | `vsync.rs:36-55`; `platform.rs:240-262` |
| Device loss | `check_device_lost` on the vsync thread, `WM_GPUI_GPU_DEVICE_LOST` | `platform.rs:251-258`; `events.rs:28` |

What the repository's own runs confirm:

- `WS_EX_NOREDIRECTIONBITMAP` is set on the window (GPUI's composition swap chain), not `LAYERED`/`TRANSPARENT` (`render/README-abi-v0.md:72`; logging code at `render/swiftright-render/src/view.rs:1321`).
- PresentMon reports every present as `Composed: Flip` with `SyncInterval 0`; present-to-display is about 31-32 ms (two vblanks) (`probes/sr0-b/frame-clock/RESULT.md:140`, `:169`). `INVESTIGATION.md:24` records the same `FLIP_SEQUENTIAL` / `BUFFER_COUNT = 3` reading from source.
- The renderer sets an opaque background (`WindowBackgroundAppearance::Opaque`, `view.rs:1280`) after a click-through bug where an alpha-0 client area let clicks fall to the window behind (`probes/sr0-b/modal-loop/RESULT.md`, "Real mouse drag"; `render/README-abi-v0.md:72`).
- The GPU adapter is not set by SwiftRight code: grep of `render/swiftright-render/src` for adapter/preference settings finds none. Which adapter a process gets is whatever `EnumAdapters(0)` returns for it.
- Windows GUI probes cannot run over SSH: `DXGI_ERROR_NOT_CURRENTLY_AVAILABLE` (0x887A0022) in session 0; an interactive desktop session is required (`probes/sr0-b/gpui-drain/RESULT.md`, finding 2).

### 2.4 The hybrid-GPU path measured in R10

The Dell has an Intel Iris Xe iGPU that owns the display and an NVIDIA GeForce RTX 4070 Laptop GPU that renders. From `probes/sr0-b/workload/results/ITERATION.md`:

- The process rendered on the RTX 4070 in every committed run (`gpu_adapter=NVIDIA GeForce RTX 4070 Laptop GPU`, e.g. `r10-20261010-tuple08-renderere280-windows.txt:127`).
- "The 13 MB back buffer is copied across PCIe to the iGPU that owns the display (NVIDIA copy engine 27 % busy)" (`ITERATION.md:10-11`, `:155`).
- `msUntilRenderComplete` is 5.5 ms at the floor, 6.1 ms median, p90 7.4, p99 11.1; a present is displayed two vblanks later only when `present phase after vblank + msUntilRenderComplete < 16.67 ms`, otherwise three (a 33 ms gap = a missed vblank) (`ITERATION.md:8-11`).
- Every remaining missed vblank is a 3-7 ms late paint (a 3 ms key handler or a 4-6 ms host drain on the paint edge) on top of a GPU burst of 9-12 ms render-complete for about three frames every few seconds (`ITERATION.md:100-101`, `:154-155`).
- `nvspcap64.dll` (NVIDIA capture/overlay hook) is loaded in the process; whether it contributes cannot be told without a run with the overlay off, which is PENDING (Adrian) (`ITERATION.md:155-157`).
- The note "Rendering on the Intel iGPU would remove the copy (GPUI enumerates adapter 0, which is the NVIDIA on this machine)" (`ITERATION.md:157`) is a hypothesis; it was not tried. See section 7, gap G7, for an inconsistency about adapter order.

---

## 3. Everything tried, by area

Result key: worked / failed / partial. "Lesson" is the transferable point.

### 3.1 Runtime seed choice

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Fork SwiftCrossUI core with a GPUI backend | failed (early-disqualified) | 17/22 headless, 5 blocked (observation granularity +8 body evals per unrelated change, relayout re-measure, transactions/animation, custom `Layout`, sub-point geometry); 5 overrides ~215 lines plus a reverted sixth; never connected to the renderer. `probes/sr0-s/scui-fork/RESULT.md`; `probes/sr0-s/COMPARISON.md`; commits `b771c20`, `a7b43ac` | A foreign scheduler/invalidation/layout model is a rewrite, not a repair. Source-only assessment (`probes/sr0-s/swiftcrossui-assessment/RESULT.md`) predicted the blockers B2 (async `onDisappear`), B3 (stale task commits), no `Layout`, no transactions, no accessibility. |
| Fresh runtime written to SwiftUI semantics | worked | 46/46 then 62/62 then 84/84 headless on macOS and Windows (`000679e`, `14106d6`, `probes/sr0-s/fresh-runtime/RESULT-tests-final.md`); F1-F9 on the real renderer 15 configs x3, x20 = 300/300 (ABI 0.5, `65e0f29`), 320/320 (tuple 06, `5a67f23`), 319/320 (tuple 08, `820eb26`) | Writing to the contract with an oracle was cheaper than bending a runtime with different semantics. It cost 8 edit cycles on Mac (cap 6) at the start (`fresh-runtime/RESULT.md`, "Fix iterations"). |
| Same-source compile: one screen file on both OSes | worked | `probes/sr0-c/same-source/RESULT.md`: Mac PASS, Windows PASS against declaration-only stubs; `NavigationSplitView` negative fixture fails on Windows only | A first finding ("`{ $row in }` is not portable") was a stub defect: adding `Binding.init(projectedValue:)` restored the original form ("Primary correction"). |
| Negative compile fixtures (`onReceive`, `ObservableObject`, `Timer.publish`) | worked | `probes/sr0-c/negative-fixtures/RESULT.md` | `Timer.publish` compiles on Mac (Foundation exposes it), so the Mac oracle cannot prove that negative; Windows-only check. |

### 3.2 Layout and performance: 0.5 fps to 60 fps (R10)

| Step | Approach | Result | Evidence | Lesson |
|---|---|---|---|---|
| 1 | First real timing of the 200-row workload | failed | `edb1784`: 0.5-0.8 fps, about 0.43 s per input commit, main-actor stalls to 18 s, every threshold FAILS | The headless suite said nothing about commit cost at 200 rows. |
| 2 | Layout measurement cache, O(1) row lookup, incremental backend upserts (`03050c3`) | worked | 200-row commit 300-380 ms to 1.1-4.4 ms (Mac), 1.65-9.3 ms (Dell bench); Windows run `06a0279` about 60 fps median | Causes were in the runtime: layout asked each subtree 3+ times per pass with no memo (~200 of 300 ms); row binding scanned the array per read; node ids hashed whole type names (`fresh-runtime/RESULT.md`, "Commit path scaling"). |
| 3 | Per-row observation, off-screen culling, shared AX snapshot (`02d8335`) | partial | row-update evaluations 1996 to 12; Dell bench 8.8 to 3.0 ms; main-actor p99 passes | Fine-grained observation mattered more than renderer tweaks. |
| 4 | Remaining misses | failed | W5 still fails (section 3.4) | |

Per-threshold outcome on tuple 08: W1, W2 (bridge per input p95 0.45 ms against 1.0), W3 (per frame p95 0.80 ms against 2.0), W6, CAL, W5 p95 and W4 p95 pass; W5 zero missed vblanks fails with 5, 1, 1; leak slope 3.21-4.42 MB/min passes against 5.0 (`docs/sr0-status.md:25-29`; the bridge-time figures are quoted from the tuple 06 run, `docs/sr0-freeze-bridge-interface.md:138`).

### 3.3 Memory leak

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Suspect the renderer heap | failed | Rust live bytes flat at 7-13 MB; growth is in the shared process heap, committed +5.7 MB/min vs allocated +2.2 (memtest, `ITERATION.md:58-73`) | Measure allocated vs committed before blaming an allocator. |
| Throttle AccessKit publication to 100 ms, share semantic strings/runs | partial | renderer allocations -78 %, ~1 MB/min less growth; slope barely moved (`65cd886`, `ITERATION.md:75-102`) | Real saving, wrong target. |
| Headless soak on the workload schedule | worked | Cause: `WorkloadEngine.park` kept the continuation of every cancelled row task (never resumed): `parked` 0 to 4037 in 300 s. Fix `33987c2` (unpark on cancel, prune per-row tables, lazy `Bridge.events`). Slope 5.2-7.35 to 2.97-3.24 MB/min app-only (`ITERATION.md:123-148`) | A soak with heap accounting and per-table sizes (`counters.csv`) found in one pass what four timed runs did not. |

The R threshold now judges the app-only slope (trace tables subtracted) with the raw slope reported beside it; both pass (`ITERATION.md:132-135`). Residual growth is allocator fragmentation that levels off after about 40 s (`ITERATION.md:144-148`).

### 3.4 Paint pacing and missed vblanks

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Fixed wait (~5.5-7 ms) after the vblank before painting (`02d8335`) | failed | missed vblanks 383-442 vs 243-277 unpaced (`9f38123`) | Delaying paint spends the GPU's budget: the present lands 7 ms after the vblank and leaves 9.7 ms for the 6 ms+ PCIe copy. |
| First pacing version used `DwmGetCompositionTimingInfo` | failed | fails on this host (HRESULT 0x88980090); it ran entirely on its fallback wait (`fallback_waits=4109 of 4109`, `ITERATION.md:13-14`) | Do not trust a timing API without checking its return. |
| Edge-clock pacing (a `DwmFlush` loop posts the paint at edge + 2.5 ms) | failed | 21-30 missed vblanks per run (`it2`) | Still worse than none. |
| Interleaved A/B: pacing off vs 1.0 ms | worked (off wins) | medians 2 vs 6.5 missed, W4 p95 45.4 vs 47.2 ms (`it3`, `ITERATION.md:75-102`); default `SWR_PAINT_PHASE_MS=0` (`render/README-abi-v0.md`, "Performance and diagnostics knobs") | Interleave A/B on the same artifact and session; sequential comparisons confounded by host load. |
| Remove the quiet-host gate; measure under normal host use | policy change | gates `825f5d2`, `5ab4a31` replaced by recorded context in `65cd886`; analyzer voids a run only for a stopped/minimised window or saturated CPU (`docs/sr0-status.md:31`) | A "quiet host" is not achievable on a shared dev machine; record disturbances instead of aborting. It also means W5 is measured under realistic interference. |

Counts per run on the final renderer: tuple 08 5, 1, 1 (`r10-20261010-tuple08-renderere280-windows.txt`); tuple 07 0, 2, 6 (commit `61b8698`); undisturbed runs across it3-it5 range 1-8, median 2 (`ITERATION.md:152-153`).

The earlier standalone probe host met the same budget: batch 5, 30/30 valid runs, zero missed vblanks, p95 16.697-16.707 ms (`probes/sr0-b/frame-clock/RESULT.md`, "PresentMon batch 5"; commit `011c83e`). That probe animated a counter, not the 200-row workload, so it does not contradict the W5 failure; its window and buffer size are not recorded in the RESULT file (UNVERIFIED whether they matched).

### 3.5 Frame clock

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| 16 ms GPUI timer | failed | 26-35 fps (`probes/sr0-b/gpui-drain/RESULT.md`, finding 3) | |
| Display-driven on-demand ticks (gpui's `RedrawWindow` per vblank, `request_animation_frame`) | worked | zero paints/ticks over 3 s idle, 1:1 ticks to animated paints, job p99 <= 1.63 ms (`frame-clock/RESULT.md:3`; `8cd7f34`) | Idle must be provably idle. |
| Measure presented-frame interval with `DwmGetCompositionTimingInfo` | failed | `cFrameDisplayed = 0` for the probe HWND; swap chain private to gpui | Use PresentMon/ETW (`RESULT.md:125`). |
| PresentMon batches 1-5 | worked after 3 harness repairs | drops tracked occlusion, not the renderer; fixed 16.7 ms p95 sat on 60.008 Hz scan-out jitter, so §11 was revised with Adrian's approval to "zero missed vblanks and p95 <= refresh + 0.1 ms" (`ca7a04c`, `docs/architecture.md:271`); batch 5 30/30 valid (`011c83e`) | Foreground and occlusion must be logged per sample; desktop GUI lanes must run one at a time (batch 4). |

### 3.6 IME

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| IMM32 text node via GPUI's `EntityInputHandler`, hand-typed with Microsoft Japanese IME | worked | `probes/sr0-d/ime-text-node/RESULT.md` interactive table (marked text, conversion, commit, Escape, UTF-16 ranges); commits `90e90b3`, `487e4ed` | The architecture chose IMM32, not a TSF text store (`docs/architecture.md:162`). |
| Automated input with Unicode packets | failed | `KEYEVENTF_UNICODE` bypasses IME composition; use virtual-key `SendInput` (`ime-text-node/RESULT.md`; `docs/sr0-status.md:59`) | |
| Real IME checks on the bridge (F7, F7live, F8) | worked, one limitation | tuple 08: F7 20/20 (+1 not-run), F7live 20/21, F8 18/19 (`native-ime-*-tuple08.txt`); fixes: runtime IME selection relative to marked text, renderer re-places composition and candidate windows (`15855e1`, `5e36535`) | The first pass (14:44, 9 Oct) found no candidate window because the driver's window search did not match the real Microsoft IME list (an explorer `ApplicationFrameWindow`); eight check/driver repairs followed (`docs/sr0-retry-ledger.md:51`). |
| Candidate list follows a layout move while composing | failed (limitation) | only failing check `candidate-window-follows-layout-move`: renderer re-places the windows (`ime_replace reason=layout`) but Windows 11's modern IME does not move the open list (`native-ime-f8-tuple08.txt:615`) | Likely needs a TSF text store (`ITfContextView::GetTextExt`); routed to SR1. |

Note: the F7 self-test verdict line reads `FAIL (16/18)` in the tuple 08 file because two programmatic assertions (`text-store-keystrokes`, `ime-calls-recorded`) fail by design when a real IME adds calls; a check `f7-selftest-programmatic-asserts-unaffected` encodes that (`native-ime-f7-tuple08.txt:1410-1411`).

### 3.7 Narrator and UI Automation

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| AccessKit `SubclassingAdapter` on GPUI's HWND, hand-authored tree | worked | Invoke/Focus/SetValue reach the handler; UIA walk (`probes/sr0-d/render-composition/DEPENDENCIES.md`, commit `384fcf0`) | The handler only enqueues and wakes; it never calls Swift (`docs/architecture.md:164`). |
| TextPattern through text-run nodes, 250 % DPI | worked | text geometry 35/35 (`fcc999d`), degenerate caret via the raw UIA provider array (`probes/sr0-b/text-geometry/RESULT.md`, run 4) | The managed UIA wrapper hides the zero-width rect; the earlier FAIL was a harness artefact. `accesskit_windows 0.35.1` has no `ITextProvider2`, so caret geometry comes from a one-character range. |
| Narrator automation | worked (automatable part) | 8/8 after the button-focus fix `0993eb2`; 2 checks not automatable (speech is audio only; another UIA client was already listening) (`native-narrator-tuple08.txt:53,82`) | A person listening is still needed (about 2 min, PENDING). |
| Narrator driver registry handling | partial | the first run changed `HKCU:\Software\Microsoft\Narrator` keys and could not restore them (no before-snapshot); later runs restore (`native-narrator-tuple08.txt:85`) | A driver that edits user settings must snapshot first. |

### 3.8 Modal loop

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Drain Swift's queue from the size/move loop timer and during `TaskDialogIndirect` | worked | `drains_sizing=2694`, resize job p99 0.48 ms, `drains_modal=991`, zero nested drains (`modal-loop/RESULT.md`, run 5; `c0b93d8`) | Window-targeted wake messages reach modal loops; thread-only messages do not (`docs/architecture.md:174`). |
| `TaskDialogIndirect` struct | failed then fixed | `E_INVALIDARG` because `TASKDIALOGCONFIG` is `packed(1)` in `commctrl.h` and in the `windows` crate | Mirror Win32 packing exactly; also, any host needs the ComCtl v6 manifest (`gpui-drain/RESULT.md`, finding 1). |
| Injected `SendInput` border drag | failed | cursor reaches `HTBOTTOMRIGHT` but no `WM_NCLBUTTONDOWN`; used `SC_SIZE` instead; a physical drag works (`modal-loop/RESULT.md`, "Real mouse drag") | Harness limit, not a renderer bug. |
| Modal open stall (40 ms) | partial | reported separately as `modal_open_one_off` (bound 50 ms); run 8 max 49.35 ms (`23933e1`); ledger flags this as a re-scope (`docs/sr0-retry-ledger.md:27`) | |
| Lost wake: modal started as a GPUI foreground runnable | failed then fixed | Modal06 on tuple 06: in 2/20 runs the main queue stopped draining for the whole modal (~1.25 s) (`a3c9a9f`). Cause: GPUI runs the foreground queue in snapshots, so the modal ran inside a drain snapshot and the drain task's wake queued behind it. Fix `02b3cc0` posts `WM_SWR_MODAL` handled at top-level dispatch. A/B: legacy 2 stalls in 180 modals, fixed 0 in 360 (`result-modalfix-legacy.txt:128`, `result-modalfix-fixed.txt:178`) | A bug found only by running the real modal path 20x; the earlier probe (single runs) passed. |

### 3.9 AX publish throttle

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Publish the whole AccessKit tree every commit | partial | ~1.2 ms of UI thread per publish with a UIA client attached; about a tenth of UI-thread time (`ITERATION.md:71`) | A UIA client is attached in every run. |
| Throttle to 100 ms with trailing publish (`SWR_AX_MIN_MS=100`) | worked, with a bug | allocations -78 %; but the trailing publish was dropped when the GPUI timer fired before the interval ended, so a selection-only commit never reached AccessKit (TextGeom06 tuple 07 run 05, stale UIA caret rect) | Fix `9c261d4` re-arms while still throttled; TextGeom06 60/60 including one observed re-throttle that healed (`bf11876`, `result-textgeom-axfix.txt:132`). |

### 3.10 Text geometry

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Probe: shaping, physical-pixel commit, paint/commit/AX rect agreement, DPI 240 | partial then worked | first run FAIL on 2 of 9 groups, both expectation errors (word-move count 23 stops incl. document end; degenerate rect); run 4 35/35 (`text-geometry/RESULT.md`) | Read the spec before asserting. |
| On the bridge: TextGeom06 | worked | 20/20, 66 checks each (`result-textgeom08.txt:93`) | |
| Underline and image painting | not asserted | no per-primitive draw counter (`docs/sr0-status.md:16`) | Accepted, not proven painted. |

### 3.11 Packaging

| Area | Approach | Result | Evidence | Lesson |
|---|---|---|---|---|
| RightKit adapter gaps | Preflight of `@rightkit/release` 0.2.135 | gaps named | `probes/sr0-d/release-preflight/RESULT.md`: no MSIX, no MSIX update route, no Swift DLL staging, updater signer hard-wired to Tauri | Route missing mechanics to the shared tool, do not script around it (`docs/architecture.md:236`). |
| `@rightkit/release` 0.2.137 to 0.2.146 | Pinned in `examples/SliceApp/package.json` | worked after waiting | 0.2.138 published without the swiftpm/MSIX flow (`4140b6a`); 0.2.139 added MSIX target (`bed78bd`); 0.2.140 notarize and staple `.app` before DMG (`f02244c`); 0.2.142 RightKit builds the DMG after the staple, workaround removed (`ea879dc`); 0.2.143 Dell trust floor pins its catalog (`b5473b9`); 0.2.144 QA gate (`f4c313f`, `54d480c`); 0.2.145 stage subsystem gate `SWIFT_STAGE_SUBSYSTEM` (`f2def6b`, `63d5598`); 0.2.146 missing QA receipt warns instead of blocking (`a6bc045`) | Four versions were needed for one product: each defect was fixed at the owner. |
| Windows MSIX | Build and sign the pair on the Dell through a non-elevated one-shot task | worked | R2 `b476c85`; tuple 06 `4496474`; tuple 07 `0c00316`; tuple 08 `d4d2ca4` (`RESULT-R5-08.md`: `signtool verify /pa` OK, layout pin OK, subsystem 2, `swift-only-proof` `ok: true`) | Compare PE files by Authenticode digest: RightKit re-signs every PE with a new timestamp, so raw hashes never match the pin (`RESULT-R2.md` defect 1; fix `1ab091c`). |
| Console window on packaged launch | Product bug: console-subsystem exe | worked after repair `0751951` | `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup`, log to `%LOCALAPPDATA%\SliceApp\slice-app.log`; found by the Sandbox W04 check (`RESULT-R5.md`, "Product fix") | The clean-machine check caught what the dev machine hid. The log is opened exclusively by the CRT; a shared-read variant is not committed (`RESULT-R5.md`). |
| Mac DMG | Sign, notarize, staple; Gatekeeper and first launch in a Tart VM | worked | R3 `1aee425`; final `34e818a`, `0be0ea3`; R7 10/10 online and offline (`2403117`); `syspolicy_check` flipped from "Notary Ticket Missing" to PASS after 0.2.140+ | A base VM with "App Store only" Gatekeeper invalidated the first R7 run; Adrian changed the setting (`RESULT-R7.md`). |
| MSIX interrupted update (W08) | `IAsyncInfo.Cancel()` on `AddPackageAsync` at staging + 200-360 ms | failed (platform) | a cancel landing in the registration phase fails the rollback (`0x80073CF8`, event 751) and leaves 0.1.0.0 `Modified, NeedsRemediation`: it does not launch, data intact. 8/8 probe runs reached it, 26 % of cancels (`80a9b45`, `RESULT-R5-W08-recovery.md`) | `KillClient` (`Stop-Process`) is not an interruption: the service finishes anyway. Only `Add-AppxPackage -AppInstallerFile` on the newer feed recovers; `RegisterByFamilyName`, `Reset-AppxPackage`, relaunch do not. |
| Mac install swap | Kill between the two renames | partial | SIGKILL leaves the install path absent until `install-app --recover` (`RESULT-R7.md`, "Interrupted install") | |

### 3.12 Clean machine

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Windows Sandbox harness (W00-W14) | worked after 8 harness defects | pinned harness 5/15, patched 13/15 (`75050e2`), final2 14/15 (`4496474`), tuple 08 offline 13/14 + network 3/3 (`d4d2ca4`) | Sandbox needs `<vGPU>Disable</vGPU>` on this Dell (Default drops the RDP session), so hardware-GPU rendering in the guest is not covered (`RESULT-R5.md`, "Environment and limits"). Offline and network profiles must be separate runs. |
| Tart VM for Mac (headless, macOS 26 vanilla) | worked | R7; `8da6f43` package record M00-M11 12/12; M11 via the window server's list because `screencapture` is TCC-denied in the guest | The VZ VNC server dies on a second client; typing into SwiftUI fields over Screen Sharing did not register. |
| Manual Repair perturbed the tuple 07 W08 run | invalid run | a person clicked Settings Repair mid-run (`RESULT-R5-07.md`, "W08 ... perturbed"; `cb76701`); tuple 08 added an optional hold-open (`a6d657b`) and no one touched it | Never let the verdict depend on a bystander. |

### 3.13 Qualification runner (SR0-A)

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Stdlib runner with accepted-baseline lane, event schema, canonical digest | worked | `b98d495`, `docs/qualification.md`; 16 baselines seeded (`799047d`) | The accepted baselines were approved by "the SwiftRight primary session under Adrian's standing autonomy grant", not reviewed by Adrian (`docs/qualification.md:59`, `:109`). |
| Review of runner v1 found false-green paths | repaired | skips counted as pass, no package stage, compare before replay, Windows pass without artifact ids (`docs/sr0-close-plan.md:20`, finding F3); fixed in `1b7cdc1`, `2c8b765`, `9e2a195` (strict runner, receipt schema v2, tuple pinning, negative control that fails the old rev06c receipts) | |
| Canonical form v2 (per-node event order kept) | worked, exposed F6 | 15 of 16 configs one result; F6 had two (`docs/qualification.md:125-131`) | The old order-insensitive digest hid per-node order faults. |
| F1 compare on tuple 06 | failed then fixed | 28 diffs: the engine insert released 1.2 ms after the last key because the release gate was patched in by a build script (`0d89b36`); fix `c0fc401` put the gate in FreshOnBridge source | Patched-in test hooks make the hash ambiguous. |
| Tuple 08 run | worked | `qualification/out/r8-tuple08/` | |

### 3.14 Oracle and comparator (SR0-O)

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Mac AX observation routes | worked | tree walk 188 nodes, identifiers, `AXPress`, focus, `AXSelectedTextRange`, `AXBoundsForRange` (`probes/sr0-o/ax-routes/RESULT.md`) | Run 1 posted "abc" with global `CGEvent.post` while another app was frontmost; the keystrokes went to that app (incident logged). Use `postToPid`. |
| Fixture app F1-F9 | failed then worked | "window never presented" was argument order: AppKit paired `--self-test` with the next token; `--self-test` must be last (4/4 failures before, 30/30 after) (`fixtures/RESULT.md`, "Primary diagnosis") | |
| F3 oracle | worked, contract corrected | `List` preserves `@State` across remove and reinsert; `VStack`/`LazyVStack` reset it and lose focus (3 runs each, 0/1/3 s gaps); the draft contract's "fresh state" was wrong | Record the platform's behaviour, then specify it. |
| F5 | worked | nondeterminism was AppKit restoring `NSWindow Frame main`; fixed by clearing the default | |
| F6 | partial | Double animation source (`withAnimation` plus implicit `.animation(value:)`) was a fixture defect, removed (`52aa3d9`); a residual A/B completion-order swap remains: 1 of 20 earlier, 4 of 100 in R6, decided unordered | |
| F9 | partial | AppKit keeps the closed `NSWindow` alive (`isReleasedWhenClosed=false`), so `tree-released` is OBSERVE on Mac and a Windows runtime requirement via `live_nodes` | |
| Comparator rejects injected faults | worked | wrong row identity, stale task commit, missing action, extra container, label change (`probes/sr0-o/comparator/RESULT.md`, 16 tests) | |
| Repeatability: 17 configs x 20 | worked | `4ff202f`, `probes/sr0-o/fixtures/REPEAT20.md` | |
| SR1 Mac fixtures G1-G8 | partial | sweep interrupted by the coordinator because it disrupted Adrian's Mac; G2 (extra `binding-write` 5/20) and G6 (lost window activation 1/19) were fixture defects, fixed but not re-run; G7 2/20, G8 0/20 (`fixtures/RESULT.md`, "SR1 fixtures"; `858faa7`) | Heavy windowed sweeps on the user's own Mac are not acceptable; they need a separate test user or VM. |

### 3.15 Cross-compare

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Mac and Windows recorders feeding one comparator (F1) | worked | 317 diffs, then 52 after List AX roles (`cc605bf`), then label fix (`cc4c93a`), then 0 (`eaf40dc`); on tuple 08 0 diffs (`qualification/out/r8-tuple08/compare-F1.json`); R6 signed re-record 0 diffs | Each reduction exposed a real runtime or bridge gap, which is why Stage O's repair count grew. |
| F2-F9 cross-compare | not done | no Windows schema-v0 trace exists (`probes/sr0-o/R6-RESULT.md`) | |
| Windows UIA recorder in Swift | worked, via a C shim | Swift's `WinSDK` has no UIAutomation module; importing `UIAutomationClient.h` through clang modules fails (`oleacc.h` missing `windef.h`); a flat header-free C shim does every COM call (`probes/sr0-o/uia-recorder/RESULT.md`) | |

### 3.16 Dependencies, hosts, bridge faults

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| GPUI 0.2.2 + AccessKit exact-pinned composition | worked | `probes/sr0-d/render-composition/DEPENDENCIES.md`; 719 locked crates, all crates.io; one MPL-2.0 crate (`option-ext`); 63 non-Windows crates not downloaded, licences UNVERIFIED | Published `gpui 0.2.2` has no AccessKit of its own (`docs/architecture.md:26`); the composition is SwiftRight's. |
| SwiftPM consumer of a prebuilt C ABI DLL | worked | `probes/sr0-d/swiftpm-consumer/RESULT.md`; needs both `-Xcc -I` and `-Xlinker -L` on the command line; a missing DLL kills the process with 0xC00004BC before Swift runs, so the loader uses `LoadLibraryW` and typed `SWR_STARTUP_ERROR` (exit 78) | |
| Bridge fault harness (C stand-in) | worked | startup mismatch, stale handles, queue overflow, off-thread action during close, stale snapshot, 3/3 (`probes/sr0-b/bridge-faults/RESULT.md`) | |
| Dispatch drain via libdispatch `_4CF` | worked | exports found in `dispatch.dll` of Swift 6.4.0; 3/3 (`probes/sr0-d/dispatch-drain/RESULT.md`) | A private symbol; a toolchain risk, not a supported API (`docs/architecture.md:178`). |
| Late-dispatch after close | worked | 3/3 reject stale generation and dead node (`gpui-drain/RESULT.md`; `0d3f1a9`) | |

---

## 4. Failed or abandoned approaches

1. **WinUI / SwiftCrossUI WinUI backend, then a C# WinUI shell, replaced by GPUI.** Architecture v0.1-v0.2 planned real SwiftUI on Mac and native WinUI via SwiftCrossUI on Windows (`git show 7a2d1f7:docs/architecture.md`, lines 10, 37). An adversarial review (`0dccfd5`, `docs/architecture-review.md:12-28`) found the Windows chain archived (`swift-winui` archived 16 Oct 2025, x64 only, outdated), an open UIA crash, no WinUI test target, and proposed a C# WinUI shell as the missing alternative (`:67`). v0.3 (`fed72cc`) dropped SwiftCrossUI/WinUI and committed to an owned SwiftUI-semantics runtime over GPUI; a C# shell was rejected because it breaks one-codebase (`docs/architecture.md:136`). Reason: remove WinRT projection ownership and the UIA crash chain (`architecture-review.md:100`).
2. **SwiftCrossUI-core fork as runtime seed.** Section 3.1; reopening it is a scope change by Adrian, not a retry (`probes/sr0-s/COMPARISON.md`, last line).
3. **Paint pacing** (fixed wait, edge-clock, 1.0 ms): worse than none (section 3.4). Code remains behind `SWR_PAINT_PHASE_MS`, default off.
4. **Global `SendInput` / `keybd_event` for fixture typing.** Matrix run F2 r18 (`out/matrix-20b/pre-targeted/`): focus moved between the foreground check and the key, and `x` reached another application's window (`Bloop-v4-3d-showcase.mp4`). The matrix therefore posts `WM_CHAR` to the probe HWND only (`fresh-on-bridge/RESULT.md`, "Targeted delivery"); posting `WM_KEYDOWN`+`WM_CHAR`+`WM_KEYUP` doubled the text. Real IME still needs virtual-key `SendInput`, gated by a foreground check that aborts the run (`native-ime-f7-tuple08.txt:1417`, `driver_abort=none`). Residual: external input still reaches the window: matrix 08 F3 list-0s r16 received "and the " from someone typing or dictating on the Dell (`matrix-08/RESULT.md`). Lesson: any shared desktop leaks input; targeted messages plus foreground aborts plus recorded foreground owners.
5. **The quiet-host gate** (`825f5d2`, `5ab4a31`): blocked runs on CPU and foreground; unusable on a shared Dell where `heardright_next_bin`, ChatGPT, SearchHost and Claude take the foreground in every run (`ITERATION.md:16-17`, `:160`). Replaced by recording context and voiding only occluded or CPU-saturated runs (`65cd886`).
6. **`SendToRecycleBin` over SSH.** The Dell stage root `D:\Claude\sr0-r5-07` was removed with `FileSystem.DeleteDirectory(..., SendToRecycleBin)` from the SSH session; no item reached the Recycle Bin on C: or D:, so it was deleted permanently. The MSIX, seals, QA receipts, run records and a patch were copied out first; RightKit's signing receipts, `hardening.json` and unpacked payloads were lost (`examples/SliceApp/RESULT-R5-07.md`, "Dell stage root removed"; commit `1d6b205`). Cause not established (deep `node_modules\.pnpm` paths or the non-interactive session are suspects). Lesson: recycle needs the interactive shell; copy evidence out before any delete.
7. **`DwmGetCompositionTimingInfo` for frame timing and pacing**: fails or reports 0 on this host (sections 3.4, 3.5).
8. **Offline matrix and runner replay as the sole path evidence**: a run where the window never presented was an argv-order bug (3.14), and the R9 first attempt aborted in `$LASTEXITCODE` handling (`native-interaction/out/RESULT.md`, attempt 1).
9. **Cancelling an install by killing the client** (`KillClient`): the service completes anyway; not a valid interruption (`RESULT-R5.md`, W08).
10. **`ms-appinstaller` recovery in Sandbox**: untestable; stock Sandbox has no App Installer (`RESULT-R5-W08-recovery.md`, method b2).
11. **ABI struct hand-layout** (`TaskDialogIndirect`, 3.8) and **Swift UIA via clang modules** (3.15): replaced by correct packing and a C shim.
12. **Wavy or dotted underline, image tint/opacity/fit, paths, non-translation transforms, RTL, `\r`, key-up, pointer-move, window-focus events, multi-window**: declared in the header but deferred (`render/README-abi-v0.md`, "Deferred").

---

## 5. Known limitations (with sources)

| # | Limitation | Source |
|---|---|---|
| L1 | W5 zero missed vblanks fails on the hybrid-GPU Dell: 5, 1, 1 per 60 s (tuple 08); 1-6 across committed runs; overlay-off run not done | `r10-20261010-tuple08-renderere280-windows.txt:40,79,118`; `docs/sr0-status.md:50` |
| L2 | MSIX update cancelled in the registration phase leaves `Modified, NeedsRemediation`; the app does not launch until the update is re-applied; data intact; recovery documented by RightKit (`@rightkit/release` README `e93ac2df`, not reproduced in this repository, UNVERIFIED) | `RESULT-R5-08.md:28-34`; `RESULT-R5-W08-recovery.md` |
| L3 | IME candidate list does not follow a mid-composition layout move (TSF text store likely needed) | `native-ime-f8-tuple08.txt:615`; `docs/sr0-freeze-slice-contract-v1.md:137` |
| L4 | Narrator speech content and Narrator-start attribution are not machine-verifiable | `native-narrator-tuple08.txt:53,82` |
| L5 | Cold first dialog open can exceed the 50 ms bound (60.9 ms once on tuple 07) | `result-modal07.txt:4`; `result-modal08.txt:262` |
| L6 | Underline and image painting are accepted, not asserted (no per-primitive draw counter) | `docs/sr0-status.md:16` |
| L7 | App Installer production host and TLS chain untested (guest-local self-signed feed); no hardware-GPU rendering in the Sandbox guest | `RESULT-R5.md`, `RESULT-R5-08.md` |
| L8 | The packaged exe's log file is held exclusively by the CRT while the app runs | `RESULT-R5.md`, "Product fix" |
| L9 | RightKit `install-app` SIGKILL between the two renames leaves the install path absent until `--recover` | `RESULT-R7.md`, "Interrupted install on 0.2.142" |
| L10 | Windows evidence is from one machine (Dell XPS 15 9530, NT 10.0.26300); the Sandbox guest is build 26100 | `docs/sr0-freeze-slice-contract-v1.md:146` |
| L11 | Windows x64 and macOS arm64 only (scope revision 1, 9 Oct) | `docs/architecture.md:238` |
| L12 | Windows signing certificate (thumbprint `121FD7B5…`) expires 2026-10-12 05:16:54 Dell local; any new Windows build needs a renewed certificate | `RESULT-R5-08.md:12`; `docs/sr0-status.md:18` |
| L13 | Renderer knobs outside the ABI (`SWR_PAINT_PHASE_MS`, `SWR_AX_MIN_MS`, `SWR_AX_OFF`, `SWR_FRAME_LOG`, `SWR_MEM_DEEP`, `SWR_MODAL_LEGACY_SPAWN`) | `render/README-abi-v0.md`; `render/swiftright-render/README.md` |
| L14 | The private libdispatch `_4CF` symbols are a version-pinned compatibility risk | `docs/architecture.md:178` |
| L15 | Renderer DLL provenance: the committed-tree rebuild of `9c261d4` hashed `E280F4A9`, so bytes match the source; the DLL is unsigned in the SDK payload (RightKit signs it inside the package) | `docs/sr0-snapshot.md:89`; `RESULT-R2.md` |
| L16 | F6 interrupted-animation completion order is unordered on SwiftUI itself (4 of 100 swapped) | `probes/sr0-o/R6-RESULT.md` |
| L17 | Cross-platform compare covers F1 only | `probes/sr0-o/R6-RESULT.md` |
| L18 | GPU/driver, fonts, locale, DPI, refresh are not pinned at tuple level (recorded per run only); Rust and MSVC versions not re-queried | `docs/sr0-snapshot.md:107-109` |

---

## 6. Open items

### 6.1 User-dependent (nothing here has a committed result)

| # | Item | Needs | Source |
|---|---|---|---|
| U1 | R9 Narrator speech content | A person listening at the Dell, about 2 min | `docs/sr0-status.md:40` |
| U2 | R10 one run with the NVIDIA overlay off; Mac windowed workload result | Adrian (no setting was touched); the Mac | `ITERATION.md:155-157`; `docs/sr0-status.md:41` |
| U3 | Decision: accept W08 and W5 as known limitations, or repair and rerun | Adrian | `docs/sr0-status.md:42`; `docs/sr0-retry-ledger.md:76` |
| U4 | Explicit record of the retry-cap overruns after the 9 Oct resume (R10, R9, R5, B repairs `02b3cc0`, `9c261d4`) | Adrian | `docs/sr0-retry-ledger.md:78,90` |
| U5 | Windows signing certificate renewal before any new Windows build (expires 2026-10-12) | Adrian / RightKit | `RESULT-R5-08.md:12` |
| U6 | Narrator registry and any other user-setting edits by drivers (resolved by restore logic; no open action) | | `native-narrator-tuple08.txt:85` |

R6 (Mac oracle with the signed recorder) is no longer pending; see section 1.

### 6.2 Technical

| # | Item | Notes |
|---|---|---|
| T1 | Windows schema-v0 traces for F2-F9 and a cross-compare beyond F1 | `probes/sr0-o/R6-RESULT.md` |
| T2 | Apply C1-C8 (and C3, see gap G4) to `CONTRACT.md`, bump to v1.0, freeze ABI 0.6; record F6 as unordered | R11; both freeze docs stay NOT FROZEN |
| T3 | TSF text store for the candidate window | SR1 |
| T4 | A per-primitive draw counter so underline and image painting can be asserted | `docs/sr0-freeze-bridge-interface.md:140` |
| T5 | GPU placement experiments for W5 (section 8) | not started |
| T6 | G2, G6, G7, G8 Mac fixture repeats (SR1 lane) | `fixtures/RESULT.md`; needs a free Mac |
| T7 | A shared-read variant of the packaged exe log | `RESULT-R5.md` candidate patch (outside the repository) |
| T8 | RightKit services C ABI and a Tauri-free `rightkit-shell` (blocks SR2, not SR0); status not rechecked since `probes/sr0-d/owner-map/RESULT.md` | |
| T9 | SR1 factory spikes (capture methods, comparator calibration) before any estimate | `docs/sr1-plan.md:160-176` |
| T10 | A decision on `modal_open_one_off` as a re-scoped criterion | `docs/sr0-retry-ledger.md:27` |

---

## 7. Gaps in the documentation itself

Each gap cites both sides. Severity is my judgement.

| # | Gap | Where | Severity |
|---|---|---|---|
| G1 | **Stale lane-status table.** `docs/sr0-close-plan.md` carries two lane tables: the first (lines 31-44) is tuple 08; the "Lane status" table (lines 63-76) still describes tuple 06 era: R3 "repo record PENDING", R7 "partial", R8 "full run PENDING", R4 pins 0.2.144, R10 "1-3 missed". Line 5 says the plan text "is unchanged", but the later table contradicts the earlier one in the same file. | `docs/sr0-close-plan.md:31-44` vs `:63-76` | High |
| G2 | **Snapshot section 5 stale.** `docs/sr0-snapshot.md:134-149` marks text geometry (6), real modal paths (7) and headless tests (9) PENDING and R3 repo record PENDING; all are done on tuple 08 (`docs/sr0-status.md:16`, `:35`). Header says HEAD `6263841`. | `docs/sr0-snapshot.md:3`, `:144-149` | Medium |
| G3 | **it6-it8 files: contradiction.** `docs/sr0-status.md:27` says "the it8 result file is not committed", `docs/sr0-snapshot.md:146` says they are not committed, while `docs/sr0-status.md:35` and commit `00e7b3e` say they are; the files exist in `probes/sr0-b/workload/results/`. | as cited | Low |
| G4 | **Contract change C3 rests on a refuted finding.** `docs/sr0-freeze-slice-contract-v1.md:101` proposes changing `ForEach($items) { $item in }` because it "fails on Windows". `probes/sr0-c/same-source/RESULT.md` "Primary correction" says that was a stub defect and the original form compiles on both (`Binding.init(projectedValue:)`). The fresh runtime also supports it (`probes/sr0-s/fresh-runtime/RESULT.md`, "Deviations"). C3 as written would weaken the contract unnecessarily. | | High |
| G5 | **Hybrid-GPU claims have no committed raw evidence.** The 13 MB back buffer, PCIe copy, 27 % copy-engine, `msUntilRenderComplete` percentiles and the `nvspcap64.dll` injection appear only as prose in `ITERATION.md`. The PresentMon CSVs and GPU counters are on the Dell (`D:\Claude\sr0b-workload\runs\`, `frame-clock/RESULT.md` "CSV stays on the host"). The committed result files record only `gpu_adapter=NVIDIA…`. | `ITERATION.md:3,10-11,155` | High |
| G6 | **Adapter order inconsistency.** `ITERATION.md:157` says GPUI's `EnumAdapters(0)` is the NVIDIA GPU. The analyzer's synthetic fixture lists DXGI enumeration order as 0 Intel, 1 NVIDIA (`probes/sr0-b/workload/analysis/analyze_workload.py:1090-1094`, a self-test model, not a captured host). The sampler writes `resources-meta.json` with the real order, but none is committed. gpui picks the first D3D11-capable adapter from `EnumAdapters` (`directx_devices.rs:123-139`), so on this host something other than raw order (for example a per-app Windows graphics preference) must explain the NVIDIA result. UNVERIFIED; this matters for any fix in section 8. | | Medium |
| G7 | **W5 counts differ across documents.** "1-6" (`docs/sr0-status.md:29,50`), "1-8 in undisturbed runs, median 2" (`docs/sr0-freeze-slice-contract-v1.md:87`), "1-3" (`docs/sr0-close-plan.md:75`, `docs/sr0-snapshot.md:146`), tuple 07 "0/2/6" (commit `61b8698`) versus the cited ranges. The ranges mix different tuples and disturbed runs. | | Medium |
| G8 | **`architecture.md` header is stale.** v0.5 (8 Oct) says "proposed architecture; no implementation or measured performance claimed" (`docs/architecture.md:5`) while the same file records §11 revision 1 from PresentMon data and scope revision 1, and the implementation exists. IMM32 is stated as the IME path, but the measured Windows 11 limitation needs TSF (L3). | | Medium |
| G9 | **`docs/sr1-plan.md` entry criteria pin the wrong tuple.** It names renderer `4FB068F0…` and fixture `AFE131A1…` (`docs/sr1-plan.md:7-9`), both superseded (tuple 08: `E280F4A9…`, `7673A2D5…`). It also says "Nothing here is implemented" while SR1 head-start work exists (ABI 0.6 `4df7e67`, runtime 62/62 `14106d6`, gallery build `47e9066`, Mac fixtures `c9347a0`). | | Medium |
| G10 | **`render/README-abi-v0.md` contradicts the freeze status.** It says 0.6 is "append-only after the SR0 bridge-interface freeze, see ... 'After-freeze additions'" (revision 0.6 note); `docs/sr0-freeze-bridge-interface.md` says NOT FROZEN and has no such section. It also says "Nothing committed" and "Nothing was run on a desktop" for 0.6, superseded by commits `862997c` to `840f9ec`. | `render/README-abi-v0.md:3`, `:11` | Medium |
| G11 | **`docs/qualification.md` header predates tuple 08.** "SR0-A is not closed ... the Windows matrix has not been run" (`:3`); test counts 115 (`:11`) vs 119 elsewhere (`:156`, `docs/sr0-status.md:19`); the D5 paragraph says `tuple-final.json` holds section 2c hashes (`:160`) while the file now names tuple 08 (`qualification/tuple-final.json:3-5`). It also says `qualification/out/` is ignored (`:14`), but `qualification/out/r8-tuple08/` and `r8-desktop-20261010/` are tracked. | | Low |
| G12 | **`probes/sr0-s/fresh-runtime/RESULT.md` top verdict is 9/9** with "Known semantic gaps: no layout", while later sections of the same file reach 62/62 and 77/77 with a layout engine; the final 84/84 is in `RESULT-tests-final.md`. | | Low |
| G13 | **`docs/sr0-freeze-slice-contract-v1.md` row WIN-M5 / §3** compare Windows F6 as "3/3 PASS" while the Mac F6 had 2 canonical results; now settled by R6 but the freeze text and `docs/qualification.md:130` ("decided by the R6 sample") are not updated. | | Low |
| G14 | **Modal open maxima differ.** `docs/sr0-status.md:16` and `docs/sr0-freeze-slice-contract-v1.md:144` say tuple 08 max 29.30-39.59 ms; the commit message of `840f9ec` says "open max 35.96 ms". Possibly different statistics (per-run vs overall); not reconciled. | | Low |
| G15 | **Evidence lives outside the repository.** R3 DMG original evidence `/Volumes/D/sr0-artifacts/...`, MSIX packages, RightKit receipts (partly lost, section 4 item 6), Dell trees `D:\Claude\sr0-r08\...`, raw PresentMon CSVs, 20-run Mac JSONL (gitignored `out/`, `docs/qualification.md:59`), R5 harness changes described as UNCOMMITTED (`RESULT-R5.md`, "Harness changes"; later `a6d657b` changed the harness, whether all harness files are tracked is UNVERIFIED). Only copies listed in the RESULT files are committed. | | Medium |
| G16 | **Approver attribution.** Accepted baselines for F1-F9 were approved by the primary session under a standing autonomy grant, and "Adrian did not review these traces individually" (`docs/qualification.md:59`, `:109`). AD7 says maintainers own acceptance. | | Medium |
| G17 | **Retry-cap accounting is partly UNVERIFIED.** Modal-loop run count "not recoverable from the RESULT file" (`docs/sr0-retry-ledger.md:27`); R10 ledger row counts "at least 14" timed runs; six were taken after a run-cap message (`ITERATION.md:164`). The only repository "resume" is a quoted chat message (`docs/sr0-retry-ledger.md:90`). | | Medium |
| G18 | **Mac-side §11 is unmeasured.** The workload thresholds were measured on Windows only; "Mac windowed workload: no committed result" (`docs/sr0-status.md:21`). `docs/architecture.md:280` requires each OS. | | Medium |
| G19 | **Native F7 "20/20" excludes one NOT-RUN check** (`candidate-window-follows-layout-move`, `native-ime-f7-tuple08.txt:610`) and F8's count omits the failing one differently; counts are consistent only if the reader knows the not-run convention. | | Low |
| G20 | **Ranking claims without a run.** "Running the fork through the real renderer would not change this outcome" is explicitly a judgement (`probes/sr0-s/COMPARISON.md`); the SwiftCrossUI assessment is source-reading only (`swiftcrossui-assessment/RESULT.md:3`). | | Low |
| G21 | **`CONTRACT.md` is still DRAFT v0.1** (`conformance/sr0-slice/CONTRACT.md:3`) while the status table is bound to a frozen-looking tuple; C1-C8 are not applied. Anyone reading `CONTRACT.md` alone sees stale F3 and F6 text. | | Medium |

---

## 8. Hardware acceleration and DirectML

Question (Adrian): could DirectML be used for rendering, since he uses it for the Parakeet ASR model? Short answer: no. DirectML is a machine-learning operator library, not a rendering API. The renderer already uses the GPU. Items that would address the measured W5 problem are about presentation and GPU placement, not ML.

### 8.1 What DirectML is

- A low-level ML API with "a familiar (native C++, nano-COM) programming interface and workflow in the style of DirectX 12"; its building blocks are hardware-accelerated ML operators (convolution, activation, GEMM, pooling, and so on) that record into Direct3D 12 command lists. Supported by DirectX 12-compatible hardware. Verified from Microsoft Learn, "Introduction to DirectML", fetched 10 Oct 2026 (`https://learn.microsoft.com/en-us/windows/ai/directml/dml`).
- Status: "DirectML is in sustained engineering ... continues to be supported, but new feature development has moved to Windows ML for Windows-based ONNX Runtime deployments" (same page). "Maintenance mode" is my paraphrase; the page's wording is "sustained engineering".
- It is usually consumed through ONNX Runtime as an execution provider (same page). That is how an ASR model such as Parakeet would use it. Parakeet itself and Adrian's use of DirectML are not documented in this repository (UNVERIFIED).

### 8.2 Why it is not a rendering API

- It executes tensor operators, not triangles, glyphs or compositor surfaces. It has no swap chain, no presentation, no text shaping, no hit-testing.
- It can interleave ML dispatches with D3D12 rendering on a D3D12 device (page, "Layer-by-layer ..."), which only matters if the app itself renders with D3D12 and wants ML work on the same frame. SwiftRight's renderer uses D3D11 (section 2.3), and nothing in the UI needs ML.
- Using DirectML to produce pixels (for example a neural upscaler) would add an ML model and its latency to every frame to solve a problem that is not shading throughput: W5 misses come from presentation timing and a cross-GPU copy (section 2.4).

### 8.3 GPU acceleration the renderer already has

- All drawing is on the GPU through Direct3D 11 and HLSL shaders, with DirectWrite for text, composed by DWM through a DirectComposition flip-model swap chain (section 2.3, `directx_renderer.rs`, `directx_devices.rs`).
- The workload run shows the NVIDIA GPU active and the CPU paint/commit costs in single-digit milliseconds (`ITERATION.md`); render-complete p50 is 6.1 ms including the cross-GPU copy.
- The swap-chain path is already flip model: Microsoft's guidance says flip model gives "better performance, lower power usage" and notes the cost of moving content between GPUs on multi-GPU laptops ("the cost of presenting a full resolution swapchain increases ... bandwidth ... across different GPUs") (`https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model`, fetched 10 Oct 2026).

### 8.4 What would be relevant to the measured bottlenecks

Everything below is a hypothesis for experiments, not a finding. None was tried in SR0 (T5).

| Idea | Why it is relevant | Evidence in the repository | Status |
|---|---|---|---|
| **Render on the iGPU that owns the display** | Removes the dGPU-to-iGPU copy of the ~13 MB back buffer each frame; `ITERATION.md:157` proposes it | The copy and its ~6 ms floor are claimed in `ITERATION.md:155` (G5: no raw data committed). gpui picks the first D3D11-capable adapter from `EnumAdapters` (`directx_devices.rs:123-139`) | Not tried; UNVERIFIED benefit |
| **GPU preference: `EnumAdapterByGpuPreference`** | Microsoft documents that it reorders adapter enumeration; `DXGI_GPU_PREFERENCE_MINIMUM_POWER` returns iGPUs first, `HIGH_PERFORMANCE` returns xGPUs, dGPUs, then iGPUs; `UNSPECIFIED` equals `EnumAdapters1` (`https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_6/nf-dxgi1_6-idxgifactory6-enumadapterbygpupreference`, Windows 10 1803+, fetched 10 Oct 2026). gpui 0.2.2 already creates an `IDXGIFactory6` but does not call it | `directx_devices.rs:109-146` | A change inside gpui (published crate, exact-pinned) or a vendored fork; the pin rules forbid a Git/vendoring exception without a decision (`docs/architecture.md:28`) |
| **Per-app Windows graphics preference (Settings, or the registry value behind it)** | Lets a user or installer pin the executable to the power-saving (iGPU) or high-performance GPU without code changes; likely explains which adapter `EnumAdapters(0)` returns per process (G6) | Not used or recorded anywhere in the repository | UNVERIFIED (no Microsoft page was fetched for this mechanism); no setting was touched in SR0 |
| **DirectComposition / flip model tuning** | Already flip-sequential and DirectComposition by default; alternatives: `DXGI_SWAP_EFFECT_FLIP_DISCARD` ("reverse composition", less DWM work), a frame-latency waitable object, `ALLOW_TEARING`, independent flip (needs the buffers and window to cover the screen, so not for a normal window except via multi-plane overlay) | Microsoft flip-model page (fetched 10 Oct 2026); current settings `directx_renderer.rs:1030-1044`; PresentMon reports `Composed: Flip` (`frame-clock/RESULT.md:140`) | Not tried; gpui does not expose these swap-chain options (UNVERIFIED that no hook exists) |
| **Sync interval 0 plus a DwmFlush-driven paint** | gpui presents with sync interval 0 and relies on its vsync thread. Present is not what blocks; the paint can still be late if the UI thread is busy | `directx_renderer.rs:205`; `vsync.rs:36`; every remaining miss is a UI-thread delay of 3-7 ms plus a GPU burst (`ITERATION.md:100-101`) | The UI-thread side (key handler 3 ms, host drain 4-6 ms) is not GPU work; reducing it is a runtime/bridge task |
| **Smaller or cheaper back buffer** | The cross-GPU copy scales with pixels; Microsoft's own advice is to lower swap-chain resolution when the copy cost matters | Microsoft flip-model page | Not applicable to a full-size app window without a visible quality cost |
| **NVIDIA overlay off** | `nvspcap64.dll` is loaded in the process; it may add to the render-complete floor | `ITERATION.md:155-157` | PENDING (U2) |
| **Run the W5 workload on a single-GPU machine** | Separates the hybrid-GPU effect from renderer cost; the standalone probe already met the budget 30/30 on the same Dell | `frame-clock/RESULT.md` batch 5 | No second machine is recorded in the repository |

Not relevant to W5: ML upscaling or denoising, DirectML operator graphs, or moving shading to compute.

### 8.5 Where ML acceleration could matter in the product

SwiftRight's UI renderer should stay free of ML. ML belongs in application features behind the service boundary:

- `docs/architecture.md:222`: high-rate data such as audio, frames and inference stays inside the engine; the UI exchanges commands, transcripts, status and progress. A speech engine (for example Parakeet-class ASR in HeardRight-like apps, `docs/architecture.md:244`) can pick DirectML, Windows ML or another ONNX Runtime provider for its own inference, independently of the renderer.
- `docs/architecture.md:212`: Core ML, Metal and other Apple components are not made portable by the UI layer; apps choose a Windows implementation behind the service contract. On Windows the equivalent choice (DirectML via ONNX Runtime today; Windows ML as Microsoft's successor path per the page above) is a per-app engine decision.
- Shell-level on-device models (for example dictation or command suggestions) would be engine services reached through `EngineService`, not renderer features (`docs/architecture.md:192`, `:204`).

GPU sharing consideration (UNVERIFIED, no measurement in the repository): an ML engine and the renderer on the same dGPU would compete for it; on the Dell the NVIDIA GPU already does the UI rendering plus the copy engine work in section 2.4, so any ML engine feature should be measured with the workload running before shipping.

### 8.6 Labels

Verified from fetched Microsoft pages (10 Oct 2026): DirectML definition and "sustained engineering" status; flip-model guidance and cross-GPU cost; `EnumAdapterByGpuPreference` semantics. Verified from source: everything in section 2.3. Verified from repository files: section 2.4 figures as stated by `ITERATION.md`. UNVERIFIED: whether Adrian's Parakeet setup uses DirectML or Windows ML; per-app graphics preference behaviour; whether any W5 improvement results from changing adapter, swap effect or overlay; Windows ML details beyond the sentence on the DirectML page.
