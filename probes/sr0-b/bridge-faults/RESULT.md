# SR0-B probe: bridge-faults (Windows x64, C stand-in renderer)

**Overall: PASS.** Startup validation (4 cases), stale handles, queue overflow, off-thread action during window close, and snapshot staleness all pass in 3 of 3 runs. No Rust, GPUI or GUI. Only the C stand-in and a synchronous Swift host were used.

Host: Windows x64, Swift 6.4.0 (`x86_64-unknown-windows-msvc`), Visual Studio 2026 Community (MSVC `cl`, `/W4 /WX`).
Remote work dir: `D:\Claude\sr0b-bridge-faults\`. Local source: `probes/sr0-b/bridge-faults/` (only write location).

## Design

**Files**
- `Sources/CSwrFakeRender/swr_fake_render.h`: ABI v0 header (bootstrap info, cb table, event record, stats, error codes, function prototypes).
- `Sources/CSwrFakeRender/module.modulemap`: systemLibrary module with **no `link` directive**. The DLL is never bound through the import table.
- `renderer/swr_fake_render.c`: C stand-in renderer, one SRWLOCK over tables, queue and counters.
- `Sources/BridgeFaults/Bridge.swift`: explicit loader (`LoadLibraryW` + `GetProcAddress`), typed function pointers, drain callback, Swift-owned ledger.
- `Sources/BridgeFaults/main.swift`: T1 to T5 test driver.
- `scripts/run-probe.ps1`: builds the four DLL variants and the Swift host, then runs the matrix.
- `Package.swift`: SwiftPM, tools 6.0, `swiftLanguageModes: [.v5]`. Same pattern as SR0-D `swiftpm-consumer`.

**ABI v0 mechanics (C side)**
- Bootstrap: `swr_bootstrap_query(out, caller_size)` returns `abi_major`, `abi_minor`, `arch`, `pointer_width`, `cb_table_size` into a caller-sized struct. It rejects a too-small caller (`SWR_E_BAD_ARG`) without writing.
- Handles: `node = (generation << 32) | slot`. Handle 0 is invalid. Windows are minted from one monotonic counter, and `swr_window_close` bumps it. Closing a window releases its nodes and bumps each slot's generation, so a reused slot gets a new generation and old handles fail.
- Queue: fixed ring of 256 records. A full queue returns `SWR_E_QUEUE_FULL`. The producer API (`swr_post_ax_action`) only validates, enqueues under the lock, and calls `SetEvent`. It never calls Swift.
- Drain: `swr_drain_events(cb, max)` copies records out under the lock, then calls the plain C callback (`fn ptr + ctx`) with the lock released, so the callback can re-enter `swr_node_check` without deadlock.
- Stats: attempts, ok, full, stale, bad, drained, max depth.

**Variant builds** (same source, different defines; the header is shared):
| variant | define | reported identity | Swift expectation |
|---|---|---|---|
| `match` | none | abi 0.1, x86_64, ptr 64, cb table 16 | matches |
| `major` | `/DSWR_REPORT_MAJOR=1` | abi 1.1 | 0.1 |
| `table` | `/DSWR_EXTRA_CB_SLOT` (header adds a callback slot) | cb table 24 | 16 |
| `missing` | no DLL file | n/a | n/a |

**Startup order (Swift):** `LoadLibraryW`, then `swr_bootstrap_query` only. It validates the ABI version, arch, pointer width and callback-table size, in that order. Only after that does it resolve the other symbols. Any mismatch prints `SWR_STARTUP_ERROR: ...` and calls `exit(78)`. The loader never kills the process, because nothing is bound at load time.

**Callback validation order (Swift, on the main thread):** window generation equals the live Swift window, then snapshot is not older than the committed snapshot, then `swr_node_check` passes. Only then is the action applied to the model. Each rejection increments its own counter.

## Commands

Sync (source split because the helper caps the archive at 24000 base64 chars):
```
scripts/sync-to-win.sh <scratch>/bf-pkg 'D:\Claude\sr0b-bridge-faults'      # Package.swift
scripts/sync-to-win.sh probes/sr0-b/bridge-faults/Sources 'D:\Claude\sr0b-bridge-faults\Sources'
scripts/sync-to-win.sh probes/sr0-b/bridge-faults/renderer 'D:\Claude\sr0b-bridge-faults\renderer'
scripts/sync-to-win.sh probes/sr0-b/bridge-faults/scripts 'D:\Claude\sr0b-bridge-faults\scripts'
```
Build (variants with `cl /nologo /LD /W4 /WX /DSWR_BUILD [defines] /I<Sources/CSwrFakeRender> swr_fake_render.c /link /IMPLIB:...`, then):
```
swift build -c release --scratch-path D:\Claude\sr0b-bridge-faults\scratch-b1
```
Run (3 times, inside the script):
```
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-bridge-faults\scripts\run-probe.ps1 -Stage run -Runs 3
```

Build output (trimmed): `variant match built: ...\variants\match\swr_fake_render.dll` (same for `major`, `table`), `Build complete! (12.33 secs)`, `swift build ok; bin path: ...\scratch-b1\out\Products\Release-windows-x86_64`. No warnings under `/W4 /WX`.

## Verbatim outputs (run 1, trimmed; runs 2 and 3 identical in structure and PASS/FAIL)

Startup matrix, one process each:
```
=== run 1 case missing-dll ===
SWR_STARTUP_ERROR: renderer not found D:\Claude\sr0b-bridge-faults\variants\missing\swr_fake_render.dll
exit=78
=== run 1 case major-mismatch ===
SWR_STARTUP_ERROR: abi mismatch expected 0.1 got 1.1
exit=78
=== run 1 case table-mismatch ===
SWR_STARTUP_ERROR: callback table size mismatch expected 16 got 24
exit=78
=== run 1 case matching ===
SWR_STARTUP_OK abi=0.1 arch=x86_64 pointer_width=64 cb_table_size=16
TEST T1 startup-matching: PASS
  bootstrap with 8-byte caller rejected: yes [rc -1]
  rejected call leaves struct_size untouched: yes
```

T2 stale handles:
```
TEST T2 stale-handles: PASS
  close window A = SWR_OK
  set_text(h1) after close = SWR_E_STALE_HANDLE
  set_text(h2) after close = SWR_E_STALE_HANDLE
  node_check(h1) after close = SWR_E_STALE_HANDLE
  node_release(h1) after close = SWR_E_STALE_HANDLE
  post(A,h1) after close = SWR_E_STALE_HANDLE
  close window A twice = SWR_E_STALE_HANDLE
  reopen window B: yes [gen 3]
  h3 reuses h1 slot index under new generation: yes [h1=100000000 h3=200000000]
  set_text(old h1) after slot reuse = SWR_E_STALE_HANDLE
  h3 text is beta (old handle did not write): yes [text 'beta']
  set_text 200 bytes (over capacity) = SWR_E_TOO_LARGE
  set_text null with len 3 = SWR_E_BAD_ARG
```

T3 queue overflow (4 producers x 10,000 attempts, drain 8 per iteration with 1 ms pause):
```
TEST T3 queue-overflow: PASS
  4 x 10000 attempts accounted: yes [ok 264 full 39736 stale 0 other 0]
  delivered + QUEUE_FULL == posted: yes [delivered 264 + full 39736]
  delivered == enqueued (C and Swift agree): yes
  all delivered accepted, no duplicate seq: yes
  queue reached capacity 256: yes [max_depth 256]
```

T4 off-thread actions during window close (producers keep posting; close at 4004 attempts of 40000; main then opens window D and posts 1000 valid actions):
```
TEST T4 close-race: PASS
  close window B while producers run = SWR_OK
  producers: 40000 attempts accounted: yes [ok 4004 full 0 stale 35996 other 0]
  close happened mid-flight: yes [attempts at close 4004]
  stale rejections at post after close: yes [stale 35996]
  some B events applied before close: yes [applied 3900]
  queued B events after close rejected by Swift: yes [rejWindow 104 expected 104]
  no B application after close: yes [after-close applied 3900]
  D model applied exactly the main posts: yes [applied 1000 main 1000 main-full-retries 106]
  D model text unchanged: yes [text 'model-D']
  no duplicate seq: yes
```

T5 snapshot staleness:
```
TEST T5 snapshot-staleness: PASS
  all 500 posts enqueued: yes [post failures 0]
  older-snapshot actions rejected (400 + 100): yes [rejSnapshot 500]
  current-snapshot actions accepted (100): yes [accepted 100]
  model mutated only by accepted actions: yes
  no window or node rejections: yes
SUMMARY: 5/5 PASS
exit=0
```

Run 2 T4 numbers differ (`ok 4001`, `attempts at close 4000`, `rejWindow 4`) because thread timing varies. Every assertion is an invariant, not a fixed count, and passes in all three runs.

## PASS/FAIL table

| # | Check | Run 1 | Run 2 | Run 3 |
|---|---|---|---|---|
| 1a | Missing DLL: `SWR_STARTUP_ERROR: renderer not found <path>`, exit 78, no crash | PASS | PASS | PASS |
| 1b | Major mismatch (1.1 vs 0.1): `abi mismatch expected 0.1 got 1.1`, exit 78 | PASS | PASS | PASS |
| 1c | Callback table size mismatch (24 vs 16): deterministic message, exit 78, no callbacks installed | PASS | PASS | PASS |
| 1d | Matching: bootstrap validates, 8-byte caller rejected and struct untouched | PASS | PASS | PASS |
| 2 | Stale handles: set_text, check, release, post, double close all `SWR_E_STALE_HANDLE`; slot reuse under new generation keeps old handle rejected; no write | PASS | PASS | PASS |
| 3 | Queue overflow: 40000 posts = delivered 264 + `QUEUE_FULL` 39736, no lost events, no duplicate seq, high-water 256 | PASS | PASS | PASS |
| 4 | Off-thread actions during close: old-window events rejected by Swift (rejWindow equals queued-after-close), zero applied after close, new window model exact | PASS | PASS | PASS |
| 5 | Snapshot staleness: 500 older-snapshot actions rejected, 100 current accepted, model changed only by accepted | PASS | PASS | PASS |
| - | **Summary** | 5/5 | 5/5 | 5/5 |

Full-run exit codes: matching = 0 in all runs. Non-matching startup cases = 78 in all runs.

## Findings and limitations

1. **Missing DLL is now deterministic.** SR0-D showed a missing DLL kills the process before Swift runs, with code `0xC00004BC` and no output. Explicit loading returns a typed diagnostic and exit 78 instead, and Swift code runs. The header module has no `link` directive, so nothing is bound at load time.
2. **Validation is ordered.** ABI version is checked before arch, pointer width or table size. Symbols other than `swr_bootstrap_query` are resolved only after the version check. A mismatch therefore never installs a callback or reaches the drain code. This is the exact rule in architecture.md §6 "Binary compatibility".
3. **Snapshot staleness is Swift-owned, not C-owned.** The C post API does not validate snapshot versions. It carries the tag, and the Swift callback rejects stale ones. T5 proves that rejection path only; it does not prove a C-side check.
4. **Producers are Swift threads calling the C post function.** This models the AccessKit off-thread path. Real AccessKit callbacks, a real UI loop, a real `GetMessage` pump and GPUI's dispatcher are not exercised.
5. **No mutation control was run.** The T4 accounting would fail if the window check were removed, because it asserts exact counts. That was not run as a negative control, so it remains an inference.
6. **Exit code 78 is a probe convention** taken from the SR0-B spec. It is not a Windows or Swift standard. The product contract for startup-failure codes is still open.
7. **Windows x64 only.** arm64 is not built or run.
8. **Driver fixes, not bridge fixes.** Fix iterations used: 3 driver or tooling fixes (Swift `for v: UInt64 in` syntax before the first build; `Launch-VsDevShell` PATH overwritten by a later PATH assignment; run stage missing `Set-Location` for SwiftPM). The bridge rules did not need changes. A generated macOS `.build` index folder under this probe directory was moved out to the session scratchpad, because the sync helper's archive exceeded its size cap. Nothing was committed, pushed or branched.

## Compliance

- Writes only under `probes/sr0-b/bridge-faults/`. The Windows work area is `D:\Claude\sr0b-bridge-faults\`.
- No commit, push or branch.
- No `Remove-Item -Recurse` on Windows, and no `rm -rf` on the Mac (the hook blocked it; `mv` was used instead).
- No Rust or Cargo was invoked.
