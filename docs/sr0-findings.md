# SR0 findings: everything tried, what worked, what did not, and what is missing

Compiled 10 October 2026 (revised at HEAD `acef4f1` to fold in the adversarial review `docs/sr0-findings-review-astra.md`; dispositions in the last section) from the repository at HEAD `593e3ab` (the task named `2da92ab`; the only later commit is the R6 result, `probes/sr0-o/R6-RESULT.md`). Sources: `docs/*`, every `RESULT*.md` and `ITERATION.md` under `probes/`, `examples/` and `qualification/`, `render/README-abi-v0.md`, `render/swiftright-render/README.md`, `git log` (219 commits), `probes/sr0-s/COMPARISON.md`, the `gpui 0.2.2` crate source, and Microsoft Learn pages fetched on 10 Oct 2026. Nothing was rerun to write this. Every claim cites a path (with line where useful) or a commit. A claim with no citation is marked UNVERIFIED.

Update 11 October 2026 (HEAD `61be5f94`): sections 1, 5, 6 and 9 and the decision in section 11 are brought to tuple 11 (`docs/sr0-snapshot.md` section 2e); the other sections keep their 10 October (tuple 08) text and are history where they name tuple 08 numbers. Conventions: "tuple 11" is the final SR0 snapshot (`docs/sr0-snapshot.md` section 2e); "tuple 08" is the previous final snapshot, kept as history (section 2d). Short hashes are sha256 prefixes of binaries or git commits (the context says which). "Dell" is the Windows host (Dell XPS 15 9530, `docs/sr0-snapshot.md:105`). "Mac" is the Mac mini, macOS 27.0.1, arm64.

---

## 1. Outcome

SR0 is **OPEN**, not closed (`docs/sr0-status.md:7`). The final tuple is tuple 11: renderer DLL `E280F4A9…` (ABI 0.6, built from `9c261d4` on `02b3cc0`, unchanged since tuple 08), runtime `8e47b89`, FreshOnBridge `07351314…` (`0a745ab` plus the AX selection-publish fix `2cfb36ef`), BridgeSmoke `85D5F8BA…`, WorkloadWin `5270D3E5…`, SliceApp MSIX 0.1.0.0 `39007039…` / 0.1.1.0 `efc52869…`, DMGs `b976ac70…` / `75f3cd75…`, `@rightkit/release` 0.2.146 (`docs/sr0-snapshot.md` section 2e, `qualification/tuple-final.json`). Receipts were taken on three tuples and carry only because the binaries are byte-identical: matrix on tuple 11; smoke, pixels, text geometry, modal and cold-open on tuple 09; workload, MSIX and (superseded) R9 and cross-compare on tuple 10. On them: the Windows 20-run matrix (320/320 first attempt on tuple 11), smoke, rendered-output pixel assertions, text geometry, modal paths, the workload against the 2026-10-10 bar, the Mac oracle and the Mac package record pass. Not closed: the tuple 11 cross-compare and R9 runs (running), Narrator speech (a person), the W08 acceptance decision, the retry-overrun record, the contract text and a runner run on tuple 11.

Why there are 11 tuples: tuples 06 to 08 fixed bridge defects (modal lost-wake, AX trailing publish, F1 release gate); tuples 09 to 11 fixed Mac-vs-Windows parity differences found by the 16-config cross-compare (onChange after List reinsertion, initial focus, Invoke focus, OS animation setting, motion start on first tick, launch selection, AX selection publish): `docs/sr0-retry-ledger.md`, "Ledger, tuples 09 to 11". The renderer did not change after tuple 08.

| Stage | Status on tuple 11 | Key evidence |
|---|---|---|
| SR0-D dependencies and hosts | PASS (Windows x64, Mac arm64) | `probes/sr0-d/*`; `docs/sr0-status.md:13` |
| SR0-C slice contract | DRAFT v0.1; freeze proposal v1.0 NOT frozen; proposed C9 and C11 text is in the file, C10 and C1-C8 are not | `conformance/sr0-slice/CONTRACT.md:3,54,56`; `docs/sr0-freeze-slice-contract-v1.md` |
| SR0-O oracle and comparator | Mac oracle PASS (R6). Cross-compare of all 16 configs: tuple 10 11/16, the 5 failures are launch selection; **tuple 11 compare running, no committed result**; R5, R6, R8 unproven; P2 settled as a Mac quirk | `probes/sr0-o/R6-RESULT.md`; `probes/sr0-o/f1-cross/CROSS-ALL.md`; `7a755ad1` |
| SR0-B bridge and measurement | PASS (carried from tuple 09): smoke 40/40, timeout 41/41, pixels 10/10, TextGeom06 20/20, Modal06 20/20 | `examples/BridgeSmoke/result-smoke-rev09.txt:83`, `result-smoke-timeout09.txt:84`, `result-smoke-pixels09.txt:4`; `examples/BridgeGeoModal/result-textgeom09.txt:93`, `result-modal09.txt:269` |
| SR0-S seed comparison | Fresh runtime selected; SwiftCrossUI fork early-disqualified (never ran on the real renderer); matrix 320/320 on tuple 11 | `probes/sr0-s/COMPARISON.md`; `probes/sr0-s/fresh-on-bridge/out/matrix-11/RESULT.md:7` |
| SR0-P packaged qualification | NOT PASS: Windows offline 13/14, W08 FAIL; network W00/W01/W12 PASS; three user recoveries measured; Mac DMG 12/12 and R7 10/10 PASS | `examples/SliceApp/RESULT-R5-10.md`; `RESULT-R5-W08-recovery-08.md`; `RESULT-R7.md` |
| SR0-A automation | Runner closure gate extended (workload, native, all 16 configs); last full run on tuple 08; none on tuple 11 | `docs/qualification.md` (2026-10-11 section); `qualification/out/r8-tuple08/` |
| SR0-N native interaction (R9) | Tuple 10 (superseded host): F7 17/20 then 20/20, F7live 20/21, F8 18/19, Narrator 8/8 automatable; **tuple 11 run running**; Narrator speech not machine-verifiable | `probes/sr0-b/native-interaction/out/*-tuple10*.txt` |
| SR0-W workload (R10) | MET under the 2026-10-10 bar (section 11): W4 p95 46.37-48.83 ms and interval p95 16.73-16.74 ms against Mac SwiftUI 71.6-78.9 ms and 17.82-17.94 ms; missed vblanks 1, 1, 1 reported; leak slope 1.72 / 3.90 / 4.20 MB/min | `probes/sr0-b/workload/results/r10-20261011-tuple10-renderere280-windows.txt:37,40,44,76,79,83,115,118,122`; `MAC-WORKLOAD.md` |

### R6 (Mac oracle, `593e3ab`, `probes/sr0-o/R6-RESULT.md`) and what followed

- mac-oracle stage: all 16 configs, 3 runs each, 3/3 self-test PASS and every canonical trace equals the accepted baseline. F1 signed re-record (Developer ID, team 6KLGD3LLKF): 3 recordings, 0 diffs against the accepted Mac trace and against the tuple 08 Windows trace.
- F6 100-run sample: 100/100 self-test PASS; 96 A-first, 4 B-first (runs 13, 23, 24, 25, clustered); the runner verdict was FAIL on the 2 canonical results (`probes/sr0-o/r6/f6/f6-100-events.jsonl:104`). **Since decided and implemented:** the canonicalizer permutes only the A/B completion pair (proposed C9, `653b2534`, `probes/sr0-o/F6-UNORDERED.md`); the 4 B-first runs and both candidates equal the accepted digest; negative controls still fail; accepted digests unchanged; the runner mirrors it. The candidate `conformance/candidates/F6/20261010T082727.113Z` is untracked and not promoted.
- The Windows schema-v0 traces for F2 to F9 now exist: all 16 configs were recorded 3 x on each side and compared (`CROSS-ALL.md`). Tuple 08 (first pass 13/16, then review `a6bccd0b`: allowances scoped, 65 injected faults rejected), tuple 09 11/16 (D2 launch selection on 5 configs, D3 F6 row rebuild), tuple 10 11/16 (F6 passes under proposed C11 with 4 more fault controls, 69 rejected; the 5 launch-selection configs still fail: the runtime selected all but UIA read the caret at the end), tuple 11: the host now publishes the AX selection with anchor = start (`2cfb36ef`), compare running.
- Unproven and listed so nobody reads a PASS as proof: R5 (F5 initial window size), R6 (F7 IME stimulus chunking), R8 (F9 late results); P2 is settled as a Mac oracle quirk by the `F3-list-1s-typeafter` probe.

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

The Dell has an Intel Iris Xe iGPU and an NVIDIA GeForce RTX 4070 Laptop GPU (the iGPU is described as the display owner in `ITERATION.md`; no committed output/LUID record confirms it). The text separates what committed files record from hypotheses.

**Measured (committed result files):**

- The process rendered on the RTX 4070 in every committed run (`gpu_adapter=NVIDIA GeForce RTX 4070 Laptop GPU`, `r10-20261010-tuple08-renderere280-windows.txt:127`).
- Tuple 08 records per-run `msUntilRenderComplete` and dropped (replaced) presents: run 1 p50 6.06, p95 9.14, p99 10.94, max 13.92 ms, 5 of 3600 presents dropped (`...tuple08...windows.txt:131`; runs 2 and 3 at `:136`, `:141`). Overlay injection is also recorded per run (`nvspcap64.dll` in the process before and after, `:129`). An earlier version of this document (gap G5) wrongly said these exist only as prose.
- Every remaining missed vblank is a 3-7 ms late paint (a 3 ms key handler or a 4-6 ms host drain on the paint edge) coinciding with a GPU burst of 9-12 ms render-complete for about three frames every few seconds (`ITERATION.md:100-101`, `:154-155`; analysis prose, raw PresentMon CSVs not committed).
- A present is displayed two vblanks later when phase after vblank + `msUntilRenderComplete` < 16.67 ms, else three (`ITERATION.md:8-11`; a stated model, not a committed trace).

**Hypotheses (not established by committed evidence):**

- That a ~13 MB back buffer is copied across PCIe to the iGPU each frame, that the NVIDIA copy engine is 27 % busy, and that this copy causes the late renders (`ITERATION.md:10-11`, `:155`). The committed files contain no ETW/GPU-queue or copy-engine trace, no adapter or output LUIDs, no buffer dimensions, driver versions or HAGS state. Correlation between the 9-12 ms bursts and misses is observed; causation is not shown, and shading throughput has not been excluded by measurement. PresentMon 2.6 documents that hardware-accelerated GPU scheduling (HAGS) can make some timings inaccurate (https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README.md), so HAGS state must be recorded with any further trace.
- That `nvspcap64.dll` contributes; this requires an overlay-off run, PENDING (U2).
- "Rendering on the Intel iGPU would remove the copy" (`ITERATION.md:157`) is untried. The earlier draft's inference that Windows graphics preferences "must" explain the NVIDIA selection is deleted (see G6): it compared a synthetic self-test enumeration with a host claim, and the synthetic data establishes no host order. Which adapter the renderer selects and which adapter owns the display output must be logged before any placement policy is chosen.

---

## 3. Everything tried, by area

Result key: worked / failed / partial. "Lesson" is the transferable point.

### 3.1 Runtime seed choice

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Fork SwiftCrossUI core with a GPUI backend | failed (early-disqualified) | 17/22 headless, 5 blocked (observation granularity +8 body evals per unrelated change, relayout re-measure, transactions/animation, custom `Layout`, sub-point geometry); 5 overrides ~215 lines plus a reverted sixth; never connected to the renderer. `probes/sr0-s/scui-fork/RESULT.md`; `probes/sr0-s/COMPARISON.md`; commits `b771c20`, `a7b43ac` | A foreign scheduler/invalidation/layout model is a rewrite, not a repair. Source-only assessment (`probes/sr0-s/swiftcrossui-assessment/RESULT.md`) predicted the blockers B2 (async `onDisappear`), B3 (stale task commits), no `Layout`, no transactions, no accessibility. |
| Fresh runtime on the first real-renderer matrix, rev2 | regression, fixed | matrix rev2 on the fixed runtime failed every config (`2aa1983`, `probes/sr0-s/fresh-on-bridge/out/matrix-rev2/`); repaired before the 300/300 run | A "fixed" runtime still needs the full matrix, not a sample. |
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

**W7 provenance (disclosure).** The tuple 08 orchestrator analysis was **INCOMPLETE** (`rc=2`): threshold W7 reported MISSING because `D:\Claude\sr0-r08\workload\runs\tuple08\incremental.json` did not exist (`r10-20261010-tuple08-renderere280-windows.txt:126`, `:145`; re-analysis note at `:147`, passing W7 at `:267-269`). The analyzer was then re-run on the same run data with the it-8 incremental record (`D:\Claude\sr0b-workload\incremental.json`, written 2026-10-09 21:35: 3 edits, 0 Rust invocations, identical DLL hashes). The log itself states it is "a carried-over build-graph record, not re-measured on tuple 08". The W7 pass on tuple 08 therefore rests on carried-over evidence. The validator checks booleans and counts, not tuple provenance. Either remeasure on the final tuple or justify build-graph equivalence (same workload exe `0815DF49`, renderer copied not built) in the record; open item T13.

### 3.3 Memory leak

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Suspect the renderer heap | failed | Rust live bytes flat at 7-13 MB; growth is in the shared process heap, committed +5.7 MB/min vs allocated +2.2 (memtest, `ITERATION.md:58-73`) | Measure allocated vs committed before blaming an allocator. |
| Throttle AccessKit publication to 100 ms, share semantic strings/runs | partial | renderer allocations -78 %, ~1 MB/min less growth; slope barely moved (`65cd886`, `ITERATION.md:75-102`) | Real saving, wrong target. |
| Control: AX publication disabled (`SWR_AX_OFF=1`) | partial | private slope 4.87 vs 5.99 MB/min default, Rust live bytes flat 7.0 MB, allocations 16.7 M vs 52.8 M, present mean 0.005 ms vs 1.26 ms; the slope stays near 5 MB/min even with no AccessKit publication (`ITERATION.md:62-66`). A control actually run | AX is a real cost but not the leak source; the same table shows `SWR_AX_MIN_MS=100` at 4.88. |
| Headless soak on the workload schedule | worked | Cause: `WorkloadEngine.park` kept the continuation of every cancelled row task (never resumed): `parked` 0 to 4037 in 300 s. Fix `33987c2` (unpark on cancel, prune per-row tables, lazy `Bridge.events`). Slope 5.2-7.35 to 2.97-3.24 MB/min app-only (`ITERATION.md:123-148`) | A soak with heap accounting and per-table sizes (`counters.csv`) found in one pass what four timed runs did not. |

The R threshold now judges the app-only slope (trace tables subtracted) with the raw slope reported beside it; both pass (`ITERATION.md:132-135`). Residual growth is allocator fragmentation that levels off after about 40 s (`ITERATION.md:144-148`).

### 3.4 Paint pacing and missed vblanks

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Fixed wait (~5.5-7 ms) after the vblank before painting (`02d8335`) | failed | missed vblanks 383-442 vs 243-277 unpaced (`9f38123`) | Delaying paint spends the GPU's budget: the present lands 7 ms after the vblank and leaves 9.7 ms for the 6 ms+ PCIe copy. |
| First pacing version used `DwmGetCompositionTimingInfo` | failed | fails on this host (HRESULT 0x88980090); it ran entirely on its fallback wait (`fallback_waits=4109 of 4109`, `ITERATION.md:13-14`) | Do not trust a timing API without checking its return. |
| Edge-clock pacing (a `DwmFlush` loop posts the paint at edge + 2.5 ms) | failed | 21-30 missed vblanks per run (`it2`) | Still worse than none. |
| Interleaved A/B: pacing off vs 1.0 ms | worked (off wins) | medians 2 vs 6.5 missed, W4 p95 45.4 vs 47.2 ms (`it3`, `ITERATION.md:75-102`); default `SWR_PAINT_PHASE_MS=0` (`render/README-abi-v0.md`, "Performance and diagnostics knobs") | Interleave A/B on the same artifact and session; sequential comparisons confounded by host load. |
| Control: resource sampler off (`-NoResources`, run it4a) | worked (sampler excluded) | missed vblanks 2 / 13 / 1 against 1 5 1 2 8 with the sampler (r2 disturbed by user input); renderer private-bytes slope 6.5 / 5.2 / 5.6 MB/min without it (`ITERATION.md:104-108`). A control actually run | Neither the misses nor the leak come from the measurement tool. |
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
| F8 matrix regression on abi06f | regression, fixed | F8 went 0/20 because the AX button focus was logged as a `focus` event and masked the row-focus check; it is now logged as `ax-button-focus` (`c31f1b5`, `matrix-abi06f`). The other configs stayed 20/20 | A diagnostic event with a shared name can change a semantic check. |
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
| Underline and image painting | not asserted | no per-primitive draw counter (`docs/sr0-status.md:16`) | Accepted, not proven painted. A draw counter would still not prove pixels, clipping or placement; see T4. |

### 3.11 Packaging

| Area | Approach | Result | Evidence | Lesson |
|---|---|---|---|---|
| RightKit adapter gaps | Preflight of `@rightkit/release` 0.2.135 | gaps named | `probes/sr0-d/release-preflight/RESULT.md`: no MSIX, no MSIX update route, no Swift DLL staging, updater signer hard-wired to Tauri | Route missing mechanics to the shared tool, do not script around it (`docs/architecture.md:236`). |
| `@rightkit/release` 0.2.137 to 0.2.146 | Pinned in `examples/SliceApp/package.json` | worked after waiting | 0.2.138 published without the swiftpm/MSIX flow (`4140b6a`); 0.2.139 added MSIX target (`bed78bd`); 0.2.140 notarize and staple `.app` before DMG (`f02244c`); 0.2.142 RightKit builds the DMG after the staple, workaround removed (`ea879dc`); 0.2.143 Dell trust floor pins its catalog (`b5473b9`); 0.2.144 QA gate (`f4c313f`, `54d480c`); 0.2.145 stage subsystem gate `SWIFT_STAGE_SUBSYSTEM` (`f2def6b`, `63d5598`); 0.2.146 missing QA receipt warns instead of blocking (`a6bc045`) | Four versions were needed for one product: each defect was fixed at the owner. |
| Windows MSIX | Build and sign the pair on the Dell through a non-elevated one-shot task | worked | R2 `b476c85`; tuple 06 `4496474`; tuple 07 `0c00316`; tuple 08 `d4d2ca4` (`RESULT-R5-08.md`: `signtool verify /pa` OK, layout pin OK, subsystem 2, `swift-only-proof` `ok: true`) | Compare PE files by Authenticode digest: RightKit re-signs every PE with a new timestamp, so raw hashes never match the pin (`RESULT-R2.md` defect 1; fix `1ab091c`). |
| Console window on packaged launch | Product bug: console-subsystem exe | worked after repair `0751951` | `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup`, log to `%LOCALAPPDATA%\SliceApp\slice-app.log`; found by the Sandbox W04 check (`RESULT-R5.md`, "Product fix") | The clean-machine check caught what the dev machine hid. The log is opened exclusively by the CRT; a shared-read variant is not committed (`RESULT-R5.md`). |
| Mac DMG | Sign, notarize, staple; Gatekeeper and first launch in a Tart VM | worked | R3 `1aee425`; final `34e818a`, `0be0ea3`; R7 10/10 online and offline (`2403117`); `syspolicy_check` flipped from "Notary Ticket Missing" to PASS after 0.2.140+ | A base VM with "App Store only" Gatekeeper invalidated the first R7 run; Adrian changed the setting (`RESULT-R7.md`). |
| MSIX interrupted update (W08) | `IAsyncInfo.Cancel()` on `AddPackageAsync` at staging + 200-360 ms | failed (platform) | a cancel landing in the registration phase fails the rollback (`0x80073CF8`, event 751) and leaves 0.1.0.0 `Modified, NeedsRemediation`: it does not launch, data intact. 8/8 probe runs reached it, 26 % of cancels (`80a9b45`, `RESULT-R5-W08-recovery.md`) | `KillClient` (`Stop-Process`) is not an interruption: the service finishes anyway. The AppInstallerFile redeploy of a newer version (`Add-AppxPackage -AppInstallerFile` on the newer feed) is the only recovery measured to work; `RegisterByFamilyName`, `Reset-AppxPackage` and relaunch did not. **Not tested:** Settings Repair (tuple 07's run was perturbed by a person clicking it; tuple 08's hold-open saw no Repair, `RESULT-R5-08.md:30-34`), and the package state after the platform `RegisterByPackageFullName` that ran at the launch attempt (the snapshot was read before the launch). W08 stays FAIL. |
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
| F6 | partial | Double animation source (`withAnimation` plus implicit `.animation(value:)`) was a fixture defect, removed (`52aa3d9`); a residual A/B completion-order swap remains: 1 of 20 earlier, 4 of 100 in R6; the lead decided it is unordered but the contract and comparator are not yet changed, so the runner verdict stays FAIL (section 1) | |
| F9 | partial | AppKit keeps the closed `NSWindow` alive (`isReleasedWhenClosed=false`), so `tree-released` is OBSERVE on Mac and a Windows runtime requirement via `live_nodes` | |
| Comparator rejects injected faults | worked | wrong row identity, stale task commit, missing action, extra container, label change (`probes/sr0-o/comparator/RESULT.md`, 16 tests) | |
| Repeatability: 17 configs x 20 | worked | `4ff202f`, `probes/sr0-o/fixtures/REPEAT20.md` | |
| SR1 Mac fixtures G1-G8 | partial | sweep interrupted by the coordinator because it disrupted Adrian's Mac; G2 (extra `binding-write` 5/20) and G6 (lost window activation 1/19) were fixture defects, fixed but not re-run; G7 2/20, G8 0/20 (`fixtures/RESULT.md`, "SR1 fixtures"; `858faa7`) | Heavy windowed sweeps on the user's own Mac are not acceptable; they need a separate test user or VM. |

### 3.15 Cross-compare

| Approach | Result | Evidence | Lesson |
|---|---|---|---|
| Mac and Windows recorders feeding one comparator (F1) | worked | 317 diffs, then 52 after List AX roles (`cc605bf`), then label fix (`cc4c93a`), then 0 (`eaf40dc`); on tuple 08 0 diffs (`qualification/out/r8-tuple08/compare-F1.json`); R6 signed re-record 0 diffs | Each reduction exposed a real runtime or bridge gap, which is why Stage O's repair count grew. |
| F2-F9 cross-compare | not done (R6 PARTIAL) | no Windows schema-v0 trace exists (`probes/sr0-o/R6-RESULT.md`) | |
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
| L1 | Missed vblanks are reported, not gated (Adrian, 2026-10-10, section 11): 1, 1, 1 per 60 s on tuple 10 (tuple 09 1, 0, 1; tuple 08 5, 1, 1; 1-6 across committed runs) on the hybrid-GPU Dell with the NVIDIA overlay loaded. The old zero-miss criterion is dropped, so the overlay-off run is no longer a gate | `r10-20261011-tuple10-renderere280-windows.txt:40,79,118`; `r10-20261010-tuple09-renderere280-windows.txt:40,79,118`; `docs/sr0-status.md` (R10 workload) |
| L2 | MSIX update cancelled in the registration phase leaves `Modified, NeedsRemediation`; the app does not launch until recovered; data intact. **Three user recoveries were measured on the final packages (n = 1 each): Settings > Advanced options > Repair, same-version `Add-AppxPackage -Path`, same-version `Add-AppxPackage -AppInstallerFile`; `Reset-AppxPackage` and the platform's own `RegisterByPackageFullName` (triggered by a launch attempt) do not.** Repair needs its install source; the product neither repairs nor tells the user; W08 remains FAIL (tuple 10: 5 genuine interruptions, c6 bad); acceptance decision pending | `RESULT-R5-10.md`; `RESULT-R5-08.md:28-34`; `RESULT-R5-W08-recovery-08.md` |
| L3 | IME candidate list does not follow a mid-composition layout move (TSF text store likely needed); unchanged on tuples 08 to 10 | `native-ime-f8-tuple10.txt:606`, `native-ime-f7live-tuple10.txt:616`; `docs/sr0-freeze-slice-contract-v1.md` section 6 |
| L4 | Narrator speech content and Narrator-start attribution are not machine-verifiable; a recorded listening result is required (U1, about 2 min, Adrian) | `native-narrator-tuple10.txt:94` |
| L5 | Cold first dialog open. Defined and measured on tuple 09: M1 main-queue blocking (the `modal_open_one_off` quantity) cold median 32.67, max 45.99 ms, 0 of 20 above 50 ms; **M2 request-to-visible median 39.20, max 52.16 ms, 1 of 20 above 50 ms**; earlier 60.9 ms once on tuple 07. The criterion is stated on M1 | `result-coldopen09.txt:7-12`; `result-modal07.txt:4`; `result-modal09.txt:263` |
| L6 | Underline and image painting: now asserted by pixels (10/10 on two capture methods, negative controls fail). Remaining: no per-primitive draw counter | `result-smoke-pixels09.txt:4`, `result-bridgepixels09.txt:4` |
| L7 | App Installer production host and TLS chain untested (guest-local self-signed feed); no hardware-GPU rendering in the Sandbox guest | `RESULT-R5.md`, `RESULT-R5-08.md` |
| L8 | The packaged exe's log file is held exclusively by the CRT while the app runs | `RESULT-R5.md`, "Product fix" |
| L9 | RightKit `install-app` SIGKILL between the two renames leaves the install path absent until `--recover` | `RESULT-R7.md`, "Interrupted install on 0.2.142" |
| L10 | Windows evidence is from one machine (Dell XPS 15 9530, NT 10.0.26300); the Sandbox guest is build 26100 | `docs/sr0-freeze-slice-contract-v1.md:146` |
| L11 | Windows x64 and macOS arm64 only (scope revision 1, 9 Oct) | `docs/architecture.md:238` |
| L12 | Windows signing certificate (thumbprint `121FD7B5…`) expires 2026-10-12 05:16:54 Dell local; any new Windows build needs a renewed certificate | `RESULT-R5-08.md:12`; `docs/sr0-status.md:18` |
| L13 | Renderer knobs outside the ABI (`SWR_PAINT_PHASE_MS`, `SWR_AX_MIN_MS`, `SWR_AX_OFF`, `SWR_FRAME_LOG`, `SWR_MEM_DEEP`, `SWR_MODAL_LEGACY_SPAWN`) | `render/README-abi-v0.md`; `render/swiftright-render/README.md` |
| L14 | The private libdispatch `_4CF` symbols are a version-pinned compatibility risk | `docs/architecture.md:178` |
| L15 | Renderer DLL provenance: the committed-tree rebuild of `9c261d4` hashed `E280F4A9`, so bytes match the source; the DLL is unsigned in the SDK payload (RightKit signs it inside the package) | `docs/sr0-snapshot.md:89`; `RESULT-R2.md` |
| L16 | F6 interrupted-animation completion order is unordered on SwiftUI itself (4 of 100 swapped); decided and implemented in the canonicalizer and runner as proposed C9; contract text in `CONTRACT.md:54`. List-row appear/disappear counts on animated insert are unspecified (proposed C11, `CONTRACT.md:56`) | `probes/sr0-o/R6-RESULT.md`; `probes/sr0-o/F6-UNORDERED.md`; `CROSS-ALL.md` |
| L17 | Cross-platform compare covers all 16 configs (tuple 10: 11/16); the tuple 11 compare is running; R5, R6, R8 unproven | `probes/sr0-o/f1-cross/CROSS-ALL.md` |
| L18 | GPU/driver, fonts, locale, DPI, refresh are not pinned at tuple level (recorded per run only); Rust and MSVC versions not re-queried | `docs/sr0-snapshot.md:107-109` |
| L19 | **Selection highlight is not painted** (caret only). The runtime selects all at launch and the host publishes the AX selection (UIA reads 0+5 on F5 in the host's own test), but the selection is not drawn. SliceApp's own host keeps a collapsed selection for SR0. SR1 | `0e4927aa` and `2cfb36ef` commit messages |
| L20 | **Cold dialog open M2 request-to-visible occasionally above 50 ms** (52.16 ms, 1 of 20 on tuple 09), while M1 blocking stays under 50 ms | `result-coldopen09.txt:12` |
| L21 | **IME F7 had one flaky run on tuple 10:** 17/20 on the first run (Escape and model-state checks after extra IME commit and Escape presses, `abort=none`), 20/20 on the rerun; tuple 09 20/20 | `native-ime-f7-tuple10.txt:1400`, `native-ime-f7-tuple10b.txt:1403` |
| L22 | **Leak slope close to the limit in 2 of 3 tuple 10 runs:** 1.72, 3.90, 4.20 MB/min against 5.0 (app only, trace buffers excluded; raw 2.32 / 4.50 / 4.81) | `r10-20261011-tuple10-renderere280-windows.txt:37,76,115` |
| L23 | **Mac SwiftUI baseline has caveats:** busy host, 1600x900 at scale 1.0, ScreenCaptureKit display-time proxy (it sees 60 fps while the app's display link ran at about 30), no Mac leak implementation in the analyzer, W6 not applicable. The performance bar compares against it | `MAC-WORKLOAD.md`, "Section 11 Mac items still unmet" |

---

## 6. Open items

State at 11 October 2026 (tuple 11). Items marked DONE keep their original number so the earlier references still resolve.

### 6.1 User-dependent (nothing here has a committed result)

| # | Item | Needs | Source |
|---|---|---|---|
| U1 | R9 Narrator speech content | A person listening at the Dell, about 2 min (Adrian) | `docs/sr0-status.md` (PENDING item 2) |
| U2 | DONE / dropped. Mac windowed workload result: committed (`MAC-WORKLOAD.md`, `3ef265bd`; instrumentation overhead A/B within noise: p95 +1.4 ms visible, -0.67 ms interval, 14-15 ns per timestamp pair). The NVIDIA overlay-off run is no longer needed because W5 is not gated | `MAC-WORKLOAD.md`; section 11 |
| U3 | DONE. W5 decided by Adrian (2026-10-10): zero-missed-vblank dropped, bar is no worse than Mac SwiftUI at p95, missed vblanks reported (section 11; `docs/architecture.md` §11 revision 2). Open remainder: write C10 into `CONTRACT.md` and change the analyzer's W5 verdict; the Mac figure carries the caveats of L23. W08 stays FAIL (T12) | Adrian (decided); R11 text |
| U4 | Explicit record of the retry-cap overruns after the 9 Oct resume (R10, R9, R5, B repairs `02b3cc0`, `9c261d4`, and the S/O parity repairs of tuples 09 to 11) | Adrian | `docs/sr0-retry-ledger.md` |
| U5 | Windows signing certificate renewal before any new Windows build (expires 2026-10-12 05:16:54 Dell local) | Adrian / RightKit | `RESULT-R5-10.md:3` |
| U6 | Narrator registry and any other user-setting edits by drivers (resolved by restore logic; no open action) | | `native-narrator-tuple10.txt` (`registry_restore_pass=1`) |
| U7 | Accept R5 W08 as a known limitation, with the three measured recoveries (L2), or repair and rerun | Adrian | `docs/sr0-status.md` (PENDING item 3) |

R6 (Mac oracle with the signed recorder) is done; the cross-compare it fed is T1.

### 6.2 Technical

| # | Item | State |
|---|---|---|
| T1 | Windows schema-v0 traces for F2-F9 and a cross-compare beyond F1, including injected semantic faults | Windows traces and cross-compare exist for all 16 configs with 69 rejected fault controls (tuple 10 11/16). **Tuple 11 compare running.** R5, R6, R8 unproven |
| T2 | Apply C1-C8 (and C3, see gap G4) to `CONTRACT.md`, bump to v1.0, freeze ABI 0.6; add C9 (text present), C10 (absent), C11 (text present) | R11; both freeze docs stay NOT FROZEN, bound to tuple 11 |
| T3 | TSF text store for the candidate window | SR1 |
| T4 | DONE. Rendered-output assertions for underline and images: pixel assertions 10/10 on two capture methods, negative controls fail (`result-smoke-pixels09.txt:4`, `result-bridgepixels09.txt:4`). Still open: a recorded Narrator listening result (U1) and explicit criterion dispositions | |
| T5 | GPU placement experiments for W5 (section 8): steps 1 to 4 run on tuple 08 (`W5-EXPERIMENTS.md`: Intel vs RTX interleaved 4 / 5 / 3 vs 2 / 1 / 3 missed; no MUX; overlay-off not run); the waitable swap chain proposal is not run. No longer gating | |
| T6 | G2, G6, G7, G8 Mac fixture repeats (SR1 lane) | `fixtures/RESULT.md`; needs a free Mac |
| T7 | A shared-read variant of the packaged exe log | `RESULT-R5.md` candidate patch (outside the repository) |
| T8 | RightKit services C ABI and a Tauri-free `rightkit-shell` (blocks SR2, not SR0); status not rechecked since `probes/sr0-d/owner-map/RESULT.md` | |
| T9 | SR1 factory spikes (capture methods, comparator calibration) before any estimate | `docs/sr1-plan.md` |
| T10 | DONE. Cold-dialog-open endpoint defined (M1 main-queue blocking, M2 request-to-visible) and 20 cold opens measured on tuple 09 (`result-coldopen09.txt:7-12`); the criterion is stated on M1. M2 once above 50 ms is L20 | `3587dcc1` |
| T11 | DONE. F6: canonicalizer permutes only the A/B pair with negative controls; the runner mirrors it; requalify F6 on the Mac oracle after the next R6 run | `653b2534`, `F6-UNORDERED.md` |
| T12 | DONE. W08 recovery measured on the final packages (Settings Repair, `Add-AppxPackage -Path`, `-AppInstallerFile` recover; `Reset-AppxPackage` and platform registration do not); harness committed in `qualification/clean-machine/windows`. Open: n = 1 per method, a real Windows install and a non-admin user are untested | `RESULT-R5-W08-recovery-08.md` |
| T13 | DONE. W7 measured on the tuple's own build: 0 Rust invocations over 3 edits (`r10-...tuple10...windows.txt:126-128`) | |
| T14 | DONE in code (`32536d98`): closure gate adds workload and native stages and requires all 16 compare configs. Open: a full runner run on tuple 11 | `docs/qualification.md` (2026-10-11) |
| T15 | Tuple 11 R9 (IME F7, F7live, F8, Narrator) on the new fixture host | running |
| T16 | Prove or accept cross-compare items R5, R6, R8 | open |
| T17 | Selection highlight painting (L19) | SR1 |

---

## 7. Gaps in the documentation itself

Each gap cites both sides. Severity is my judgement.

| # | Gap | Where | Severity |
|---|---|---|---|
| G1 | **Stale lane-status table.** `docs/sr0-close-plan.md` carries two lane tables: the first (lines 31-44) is tuple 08; the "Lane status" table (lines 63-76) still describes tuple 06 era: R3 "repo record PENDING", R7 "partial", R8 "full run PENDING", R4 pins 0.2.144, R10 "1-3 missed". Line 5 says the plan text "is unchanged", but the later table contradicts the earlier one in the same file. | `docs/sr0-close-plan.md:31-44` vs `:63-76` | High |
| G2 | **Snapshot section 5 stale.** `docs/sr0-snapshot.md:134-149` marks text geometry (6), real modal paths (7) and headless tests (9) PENDING and R3 repo record PENDING; all are done on tuple 08 (`docs/sr0-status.md:16`, `:35`). Header says HEAD `6263841`. | `docs/sr0-snapshot.md:3`, `:144-149` | Medium |
| G3 | **it6-it8 files: contradiction.** `docs/sr0-status.md:27` says "the it8 result file is not committed", `docs/sr0-snapshot.md:146` says they are not committed, while `docs/sr0-status.md:35` and commit `00e7b3e` say they are; the files exist in `probes/sr0-b/workload/results/`. | as cited | Low |
| G4 | **Contract change C3 rests on a refuted finding.** `docs/sr0-freeze-slice-contract-v1.md:101` proposes changing `ForEach($items) { $item in }` because it "fails on Windows". `probes/sr0-c/same-source/RESULT.md` "Primary correction" says that was a stub defect and the original form compiles on both (`Binding.init(projectedValue:)`). The fresh runtime also supports it (`probes/sr0-s/fresh-runtime/RESULT.md`, "Deviations"). C3 as written would weaken the contract unnecessarily. | | High |
| G5 | **Hybrid-GPU copy claims have no committed raw evidence.** The 13 MB back buffer, PCIe copy and 27 % copy-engine figure appear only as prose in `ITERATION.md`; the PresentMon CSVs and GPU counters are on the Dell (`D:\Claude\sr0b-workload\runs\`, `frame-clock/RESULT.md` "CSV stays on the host"). Correction after review: `msUntilRenderComplete` percentiles, dropped presents and the `nvspcap64.dll` injection **are** recorded per run in the committed tuple 08 result (`r10-20261010-tuple08-renderere280-windows.txt:129,131`). Missing: ETW/GPU-queue and copy-engine traces, adapter/output LUIDs, buffer dimensions, driver versions, HAGS state. | `ITERATION.md:3,10-11,155` | High |
| G6 | **Adapter order: no host evidence.** `ITERATION.md:157` says GPUI's `EnumAdapters(0)` is the NVIDIA GPU. The analyzer's synthetic fixture lists a different order (`probes/sr0-b/workload/analysis/analyze_workload.py:1090-1094`), but that is a self-test model, not a captured host, so it establishes no host order and no contradiction. The sampler writes `resources-meta.json` with the real order, but none is committed. An earlier draft inferred that a Windows graphics preference "must" explain the NVIDIA selection; that inference is deleted. Needed: log the renderer's actual adapter selection and display ownership before choosing a placement policy. | | Medium |
| G7 | **W5 counts differ across documents.** "1-6" (`docs/sr0-status.md:29,50`), "1-8 in undisturbed runs, median 2" (`docs/sr0-freeze-slice-contract-v1.md:87`), "1-3" (`docs/sr0-close-plan.md:75`, `docs/sr0-snapshot.md:146`), tuple 07 "0/2/6" (commit `61b8698`) versus the cited ranges. The ranges mix different tuples and disturbed runs. | | Medium |
| G8 | **`architecture.md` header is stale.** v0.5 (8 Oct) says "proposed architecture; no implementation or measured performance claimed" (`docs/architecture.md:5`) while the same file records §11 revision 1 from PresentMon data and scope revision 1, and the implementation exists. IMM32 is stated as the IME path, but the measured Windows 11 limitation needs TSF (L3). | | Medium |
| G9 | **`docs/sr1-plan.md` entry criteria pin the wrong tuple.** It names renderer `4FB068F0…` and fixture `AFE131A1…` (`docs/sr1-plan.md:7-9`), both superseded (tuple 08: `E280F4A9…`, `7673A2D5…`). It also says "Nothing here is implemented" while SR1 head-start work exists (ABI 0.6 `4df7e67`, runtime 62/62 `14106d6`, gallery build `47e9066`, Mac fixtures `c9347a0`). | | Medium |
| G10 | **`render/README-abi-v0.md` contradicts the freeze status.** It says 0.6 is "append-only after the SR0 bridge-interface freeze, see ... 'After-freeze additions'" (revision 0.6 note); `docs/sr0-freeze-bridge-interface.md` says NOT FROZEN and has no such section. It also says "Nothing committed" and "Nothing was run on a desktop" for 0.6, superseded by commits `862997c` to `840f9ec`. | `render/README-abi-v0.md:3`, `:11` | Medium |
| G11 | **`docs/qualification.md` header predates tuple 08.** "SR0-A is not closed ... the Windows matrix has not been run" (`:3`); test counts 115 (`:11`) vs 119 elsewhere (`:156`, `docs/sr0-status.md:19`); the D5 paragraph says `tuple-final.json` holds section 2c hashes (`:160`) while the file now names tuple 08 (`qualification/tuple-final.json:3-5`). It also says `qualification/out/` is ignored (`:14`), but `qualification/out/r8-tuple08/` and `r8-desktop-20261010/` are tracked. | | Low |
| G12 | **`probes/sr0-s/fresh-runtime/RESULT.md` top verdict is 9/9** with "Known semantic gaps: no layout", while later sections of the same file reach 62/62 and 77/77 with a layout engine; the final 84/84 is in `RESULT-tests-final.md`. | | Low |
| G13 | **`docs/sr0-freeze-slice-contract-v1.md` row WIN-M5 / §3** compare Windows F6 as "3/3 PASS" while the Mac F6 had 2 canonical results; now settled by R6 but the freeze text and `docs/qualification.md:130` ("decided by the R6 sample") are not updated. | | Low |
| G14 | **Modal open maxima: resolved.** `docs/sr0-status.md:16` and `docs/sr0-freeze-slice-contract-v1.md:144` say tuple 08 29.30-39.59 ms (per-run maxima: min 29.30, median 34.02, max 39.59, `result-modal08.txt:262`); the commit message of `840f9ec` says 35.96 ms, which is one run's detailed result (`result-modal08.txt:242`). The tuple 08 maximum is 39.59 ms. | | Low |
| G15 | **Evidence lives outside the repository.** R3 DMG original evidence `/Volumes/D/sr0-artifacts/...`, MSIX packages, RightKit receipts (partly lost, section 4 item 6), Dell trees `D:\Claude\sr0-r08\...`, raw PresentMon CSVs, 20-run Mac JSONL (gitignored `out/`, `docs/qualification.md:59`), R5 harness changes described as UNCOMMITTED (`RESULT-R5.md`, "Harness changes"; later `a6d657b` changed the harness, whether all harness files are tracked is UNVERIFIED). Only copies listed in the RESULT files are committed. | | Medium |
| G16 | **Approver attribution.** Accepted baselines for F1-F9 were approved by the primary session under a standing autonomy grant, and "Adrian did not review these traces individually" (`docs/qualification.md:59`, `:109`). AD7 says maintainers own acceptance. | | Medium |
| G17 | **Retry-cap accounting is partly UNVERIFIED.** Modal-loop run count "not recoverable from the RESULT file" (`docs/sr0-retry-ledger.md:27`); R10 ledger row counts "at least 14" timed runs; six were taken after a run-cap message (`ITERATION.md:164`). The only repository "resume" is a quoted chat message (`docs/sr0-retry-ledger.md:90`). | | Medium |
| G18 | **Mac-side §11 is unmeasured.** The workload thresholds were measured on Windows only; "Mac windowed workload: no committed result" (`docs/sr0-status.md:21`). `docs/architecture.md:280` requires each OS. | | Medium |
| G19 | **Native F7 "20/20" excludes one NOT-RUN check** (`candidate-window-follows-layout-move`, `native-ime-f7-tuple08.txt:610`) and F8's count omits the failing one differently; counts are consistent only if the reader knows the not-run convention. | | Low |
| G20 | **Ranking claims without a run.** "Running the fork through the real renderer would not change this outcome" is explicitly a judgement (`probes/sr0-s/COMPARISON.md`); the SwiftCrossUI assessment is source-reading only (`swiftcrossui-assessment/RESULT.md:3`). | | Low |
| G21 | **`CONTRACT.md` is still DRAFT v0.1** (`conformance/sr0-slice/CONTRACT.md:3`) while the status table is bound to a frozen-looking tuple; C1-C8 are not applied. Anyone reading `CONTRACT.md` alone sees stale F3 and F6 text. | | Medium |

---

## 8. Hardware acceleration and DirectML

Question (Adrian): could DirectML be used for rendering, since he uses it for the Parakeet ASR model? Answer: DirectML is useful for Parakeet inference; it can take part in ML upscaling and denoising within a rendering pipeline; it cannot replace D3D drawing or presentation; and it has no demonstrated benefit for W5. The renderer already uses the GPU. Items that could address the measured W5 problem are about presentation and GPU placement (section 8.4), not ML.

### 8.1 What DirectML is

- A low-level ML API with "a familiar (native C++, nano-COM) programming interface and workflow in the style of DirectX 12"; its building blocks are hardware-accelerated ML operators (convolution, activation, GEMM, pooling, and so on) that record into Direct3D 12 command lists. Supported by DirectX 12-compatible hardware. Verified from Microsoft Learn, "Introduction to DirectML", fetched 10 Oct 2026 (`https://learn.microsoft.com/en-us/windows/ai/directml/dml`).
- Status: "DirectML is in sustained engineering ... continues to be supported, but new feature development has moved to Windows ML for Windows-based ONNX Runtime deployments" (same page). "Maintenance mode" is my paraphrase; the page's wording is "sustained engineering".
- It is usually consumed through ONNX Runtime as an execution provider (same page). That is how an ASR model such as Parakeet would use it. Parakeet itself and Adrian's use of DirectML are not documented in this repository (UNVERIFIED).

### 8.2 Why it is not a rendering API

- It executes tensor operators, not triangles, glyphs or compositor surfaces. It has no swap chain, no presentation, no text shaping, no hit-testing.
- It can interleave ML dispatches with D3D12 rendering on a D3D12 device (page, "Layer-by-layer ..."), which only matters if the app itself renders with D3D12 and wants ML work on the same frame. SwiftRight's renderer uses D3D11 (section 2.3), and nothing in the UI needs ML.
- DirectML can participate in a rendering pipeline, for example ML upscaling or denoising (Microsoft DirectML documentation, https://learn.microsoft.com/en-us/windows/ai/directml/dml), but it does not draw or present. Using it for pixels would add a model and its latency to every frame, and nothing measured shows shading throughput limits W5: the misses coincide with late paints and GPU bursts whose cause (including a cross-GPU copy) is a hypothesis (section 2.4). No W5 benefit is demonstrated. Engine (Parakeet) and render responsibilities stay separate.

### 8.3 GPU acceleration the renderer already has

- All drawing is on the GPU through Direct3D 11 and HLSL shaders, with DirectWrite for text, composed by DWM through a DirectComposition flip-model swap chain (section 2.3, `directx_renderer.rs`, `directx_devices.rs`).
- The workload run shows the NVIDIA GPU active and the CPU paint/commit costs in single-digit milliseconds (`ITERATION.md`); render-complete p50 is 6.1 ms (whether that includes a cross-GPU copy is a hypothesis, section 2.4).
- The swap-chain path is already flip model: Microsoft's guidance says flip model gives "better performance, lower power usage" and notes the cost of moving content between GPUs on multi-GPU laptops ("the cost of presenting a full resolution swapchain increases ... bandwidth ... across different GPUs") (`https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model`, fetched 10 Oct 2026).

### 8.4 Ordered W5 experiment plan

All steps are untried (T5). Keep window and buffer dimensions, the workload, and the W4/W5 criteria fixed across steps; keep raw traces for each. The ordering follows the Astra review.

1. **Instrument actual GPU and output routing.** Log the renderer's chosen adapter, the adapter and output that own the display (LUIDs), buffer dimensions, driver versions and HAGS state; capture ETW/GPU-queue and copy-engine activity with a tool whose HAGS limits are known (PresentMon 2.6 documents HAGS timing inaccuracies). This replaces the unsupported adapter-order inference (G6) and turns the copy hypothesis into a measurement or refutes it.
2. **Interleave Intel-versus-RTX runs.** Compare the renderer on the iGPU and on the RTX with A/B interleaving on the same artifact and session. gpui 0.2.2 takes the first D3D11-capable adapter from `EnumAdapters` and does not call `EnumAdapterByGpuPreference` (`directx_devices.rs:123-139`); placement therefore needs a supported mechanism (per-app Windows graphics preference, UNVERIFIED against a Microsoft page) or a gpui change, which the exact-pin rule (`docs/architecture.md:28`) makes a decision for Adrian.
3. **Overlay on/off.** One interleaved run pair with the NVIDIA overlay off (U2).
4. **Supported direct-dGPU display routing.** Test only routings the platform supports for the display configuration; no unsupported tricks.
5. **Waitable swap chain, latency 1 versus 2.** Use `DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT` and `SetMaximumFrameLatency` (https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains). Measure `Present` duration and queue depth, because `Present(0, 0)` does not establish non-blocking behaviour (https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-present).
6. **Swap-effect and tearing experiments, clearly separated from the above.** The current composition path uses `CreateSwapChainForComposition`, which requires `FLIP_SEQUENTIAL` under its documented contract (https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition). `FLIP_DISCARD`, `ALLOW_TEARING` or independent flip are therefore backend changes (for example the `CreateSwapChainForHwnd` fallback, which gpui can already select with `GPUI_DISABLE_DIRECT_COMPOSITION`), not compatible tuning. Feature-check tearing and multi-plane overlay support, and preserve the tear-free acceptance criterion.
7. **Shorten the UI-thread work near paint deadlines.** Every remaining miss involves a 3-7 ms late paint (key handler, host drain). Reduce measured key-handler and drain work on the paint edge; this is a runtime/bridge task, not GPU work.
8. **Parakeet placement.** Test Parakeet on the RTX with the UI on Intel versus both on the RTX, keeping raw traces and end-to-end latency results.

### 8.5 Where ML acceleration could matter in the product

SwiftRight's UI renderer should stay free of ML. ML belongs in application features behind the service boundary:

- `docs/architecture.md:222`: high-rate data such as audio, frames and inference stays inside the engine; the UI exchanges commands, transcripts, status and progress. A speech engine (for example Parakeet-class ASR in HeardRight-like apps, `docs/architecture.md:244`) can pick DirectML, Windows ML or another ONNX Runtime provider for its own inference, independently of the renderer.
- `docs/architecture.md:212`: Core ML, Metal and other Apple components are not made portable by the UI layer; apps choose a Windows implementation behind the service contract. On Windows the equivalent choice (DirectML via ONNX Runtime today; Windows ML as Microsoft's successor path per the page above) is a per-app engine decision.
- Shell-level on-device models (for example dictation or command suggestions) would be engine services reached through `EngineService`, not renderer features (`docs/architecture.md:192`, `:204`).

GPU sharing consideration (UNVERIFIED, no measurement in the repository): an ML engine and the renderer on the same dGPU may compete for it; on the Dell the NVIDIA GPU already does the UI rendering, so step 8 of section 8.4 measures this before shipping.

### 8.6 Labels

Verified from fetched Microsoft pages (10 Oct 2026): DirectML definition and "sustained engineering" status; flip-model guidance and cross-GPU cost; `EnumAdapterByGpuPreference` semantics. Verified from source: everything in section 2.3. Verified from repository files: the per-run figures in section 2.4 (tuple 08 result); the copy, copy-engine and burst-cause statements are hypotheses. UNVERIFIED: whether Adrian's Parakeet setup uses DirectML or Windows ML; per-app graphics preference behaviour; whether any W5 improvement results from changing adapter, swap effect or overlay; Windows ML details beyond the sentence on the DirectML page.

---

## 9. Remaining work to close SR0

Ordered by dependency. State at 11 October 2026 (tuple 11); each item says what is now done.

1. DONE: apply the F6 decision (T11) in the canonicalizer and runner with negative controls (`653b2534`). Open: requalify F6 on the Mac oracle at the next R6 run; contract text C9 is in `CONTRACT.md:54`.
2. Partly done: Windows schema-v0 traces for F2-F9 recorded and cross-compared with injected faults (T1; tuple 10 11/16). Open: the tuple 11 compare (running); R5, R6, R8 (T16); then apply C1-C8, C3 (G4), C9, C10, C11 to `CONTRACT.md`, bump to v1.0 and freeze ABI 0.6 (T2).
3. DONE: W5 decided (U3, section 11); Mac windowed workload run with overhead A/B (U2); W7 remeasured (T13). Open: write C10 into `CONTRACT.md` and update the analyzer's W5 verdict; a quiet-host Mac rerun with an in-process frame record is optional hardening.
4. DONE: cold-dialog criterion defined and measured (T10). Open: L20 (M2 above 50 ms once) is recorded, not repaired.
5. Partly done: W08 recovery measured on the final packages (T12). Open: Adrian's acceptance decision (U7); a certificate renewal first if any new Windows build is needed (U5, expires 2026-10-12 05:16:54).
6. Partly done: rendered-output assertions for underline and images (T4). Open: the recorded Narrator listening result (U1).
7. Partly done: runner closure gate includes workload and native (T14). Open: run it on tuple 11.
8. Open: tuple 11 R9 (T15); the stale documents of section 7 that this update did not touch (G7, G9, G10, G12, G15 to G17, G20); the retry-cap overrun record (U4).

---

## 10. Review dispositions (Astra, acef4f1)

Source: `docs/sr0-findings-review-astra.md`. Each finding was checked against the cited files before being applied. No finding was rejected; where a finding was partly wrong or needed qualification the table says so.

| Finding | Disposition | Change made |
|---|---|---|
| 1 BLOCKER: F2-F9 parity unproved | Accepted. Verified: `run.py:1374` compares F1 only | R6 marked PARTIAL (section 1, stage table, L17, T1); kept open |
| 2 BLOCKER: F6 runner FAIL omitted | Accepted. Verified: `f6-100-events.jsonl:104` is `fail`; committed traces hold one A/B pair, so the "first animation pair" claim is unsupported | FAIL recorded; claim removed; T11 added with Astra's constraints (permute only the completion pair, keep start-before-complete, exactly-once, lifecycle and final state, negative controls) |
| 3 BLOCKER: W08 | Accepted with change: W08 stays FAIL. "Only" recovery is stated as the only one measured to work; the finding's demand for a harness is kept as an open item | Section 3.11 W08 row, L2, T12: AppInstallerFile redeploy is the only measured recovery; Settings Repair and post-registration state listed as untested |
| 4 BLOCKER: W5 closure evidence | Accepted. Verified against `docs/architecture.md:273` | U2, U3 and work list: Mac workload, archived samples, overhead measurement; repair W5 or revise the criterion explicitly, then rerun |
| 5 MAJOR: GPU correlation as cause; G5 wrong | Accepted. Verified: tuple 08 log lines 129-131 record overlay and `msUntilRenderComplete` | Section 2.4 split into measured and hypotheses; G5 corrected; HAGS caveat with PresentMon link; ETW/LUID/driver/HAGS evidence listed |
| 6 MAJOR: adapter-order "contradiction" | Accepted. The fixture at `analyze_workload.py:1090-1094` is a synthetic self-test | G6 rewritten, inference deleted; adapter selection logging is step 1 of section 8.4 |
| 7 MAJOR: swap-chain constraints | Accepted | Section 8.4 steps 5-6: API constraints, Microsoft links, `Present(0,0)` caveat, tearing/MPO feature check, tear-free criterion kept |
| 8 MAJOR: cold-dialog | Accepted. Verified: 39.59 ms max at `result-modal08.txt:262`; 35.96 ms is one run at `:242` | L5, G14 corrected; T10 for measurement definition and 50 ms resolution |
| 9 MAJOR: W7 carry-over | Accepted. Verified at log lines 126, 145, 147 | Disclosure paragraph in section 3.2; T13 |
| 10 MAJOR: visual/accessibility gates | Accepted. Verified: `run.py:61` stages omit workload and native-interaction | T4, T14, U1, L4, L6, section 3.10; work list items 6-7 |
| 11 MINOR: omitted controls and regressions | Accepted. Verified `ITERATION.md:62-66`, `:104-108`, commits `2aa1983`, `c31f1b5` | Four rows added (AX-off control, sampler-off control, rev2 regression, F8 0/20 regression), each marked as actually run or regression |
| 12 MINOR: DirectML categorical | Accepted | Section 8 intro, 8.2 and 8.5 reworded: useful for Parakeet inference; can take part in ML upscaling and denoising; cannot replace D3D drawing; no demonstrated W5 benefit; sustained-engineering statement kept |

## 11. Decision: performance bar (Adrian, 2026-10-10)

The zero-missed-vblank criterion (W5) is dropped: "We don't need that zero-missed screen refresh … Change the bar." The §11 performance bar for SR0 is: no worse than Mac SwiftUI on the same workload for input-to-visible latency and frame-interval p95, with missed vblanks reported, not gated. Evidence: Windows tuple 08 W4 p95 43–49 ms, W5 interval p95 about 16.76 ms, 1–6 missed vblanks per 60 s (`probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt`, `W5-EXPERIMENTS.md`); Mac SwiftUI W4 p95 72–79 ms, interval p95 17.9 ms, 0 missed (`MAC-WORKLOAD.md`, with its caveats). To apply: `docs/architecture.md` §11, `conformance/sr0-slice/CONTRACT.md` (proposed change C10), the workload analyzer's W5 verdict.

**Applied 11 October 2026:** `docs/architecture.md` §11 revision 2 (dated 2026-10-10) carries this decision in the limits table and the revision note; `docs/sr0-status.md`, `docs/sr0-close-plan.md`, both freeze documents and `docs/qualification.md` cite it. `CONTRACT.md` (proposed C10) and the analyzer's W5 verdict are not yet changed.

## 12. Unresolved observation from the factory's first Windows capture (2026-10-11)

Reported by the SR1 factory session (evidence `factory/native/windows/first-capture-corrections-v1/diagnosis.json`, `first-capture-readiness-v1/actual-first-r1`): on the Dell (DPI 240, scale 2.5) the renderer's ABI "ready" metrics reported 800x1396 physical while the host's actual client area was 800x600. The factory host now derives its layout proposal from the actual client size and scale and keeps the ready metrics separately. Cause not assigned: it may be the factory host's window creation, a clamp to the work area, or a unit mix in the renderer's ready metrics. Not reproduced in SR0 fixtures (the SR0 hosts size their own windows). To settle: log requested size, ready metrics and GetClientRect in one SR0 host run at scale 2.5. A second observation (a button label wrapping "Continu" / "e") was a factory-host reshaping error, not a runtime or renderer defect.
