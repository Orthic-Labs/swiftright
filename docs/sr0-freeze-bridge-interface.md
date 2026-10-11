# SR0-B bridge interface (ABI rev 0.6): freeze proposal

**PROPOSAL, not frozen. Updated 11 October 2026 against HEAD `61be5f94`; the freeze is proposed on ABI 0.6 bound to tuple 11, the final snapshot tuple (`docs/sr0-snapshot.md` section 2e; sections 2d (tuple 08) and 2c (tuple 06) are superseded). The ABI itself is unchanged since tuple 08: header last changed `862997c`, renderer `E280F4A9…` since `9c261d4`; tuples 09 to 11 changed the runtime and the fixture host only. Sections 1 to 6 below keep their tuple 08 evidence as history; section 7 binds the proposal to tuple 11.** The SR0 snapshot is bridge ABI **0.6**, an append-only superset of 0.5 (header `SWR_ABI_MINOR 6`, last header change `862997c`, unchanged since). Sections 1 to 4 were written for 0.5 and keep their 0.5 evidence as history; section 5 lists the 0.6 delta that makes the 0.6 surface = sections 1.1-1.10 plus section 5; section 6 records the 0.6 evidence on the final tuple. Sources: `render/swiftright-abi/include/swiftright.h` (single source of truth), `render/README-abi-v0.md`, `packages/SwiftRightBridge/` (last change `33987c2`), `examples/BridgeSmoke/`. History: b907913 (v0, smoke 19/19), b9651bd (rev 0.4), 10c4877 (rev 0.5), 4df7e67 (rev 0.6), 862997c (0.6 smoke 40/40 on renderer `777F14C4`, header comments). The README says freeze waits on the SR0-C contract freeze; companion proposal: `docs/sr0-freeze-slice-contract-v1.md`.

**Final tuple for the freeze (tuple 11, `docs/sr0-snapshot.md` section 2e):** renderer DLL `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` (ABI 0.6; built from `9c261d4` on top of `02b3cc0`, no ABI change; provenance `examples/SliceApp/Windows/renderer-pin.json`), runtime `8e47b89`, fixture host FreshOnBridge `073513142F25C454B58DD05E545875E90B157539C72977E855AD68785293D55E` (`0a745ab` plus `2cfb36ef`), BridgeSmoke `85D5F8BA798EF17367844F28D75F3E53A37323F13A8409397C7C3FD1AD563EEA`, WorkloadWin `5270D3E54C1BD8FB625A2BE20EDFE12C31DD92686426457FDBED8FBA705124E7`, SliceApp MSIX 0.1.0.0 `39007039…` / 0.1.1.0 `efc52869…` (`examples/SliceApp/RESULT-R5-10.md:12`), `@rightkit/release` 0.2.146. Everything named `E280F4A9`-era in the sections below as tuple 08 (fixture `7673A2D5…`, BridgeSmoke `21992F16…`, WorkloadWin `0815DF49…`, MSIX `c80c6947…` / `0ff65165…`) is history. The renderers `7533963D…` (tuple 06) and `97CA28E8…` (tuple 07) and fixture `AA4353CE…` are superseded and are history. The renderers `C80B9517…`, `777F14C4…` and `4FB068F0…` and the 0.5 DLL `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1` (renderer `d45c98c`) are superseded and are history.

**The renderer changed after the 0.6 header without an ABI change.** After `862997c` the renderer sources changed for IME (`15855e1` runtime treats the IME selection as relative to the marked text and the renderer subclasses the window to re-place composition and candidate windows; `a9db7dc` candidate geometry logging; `5e36535` re-place on layout move) and for R10 performance (`02d8335` per-row observation, off-screen culling, shared AX snapshot, first paint pacing; `65cd886` pacing off by default, AccessKit publication throttled to once per 100 ms with a trailing publish, allocation counters, frame trace). `173ac08` documents the R10 environment knobs in `render/README-abi-v0.md`. The header (`swiftright.h`) is unchanged since `862997c` and the final BridgeSmoke prints `startup validation [abi 0.6 fn_count=16 stats_size=200]` (`examples/BridgeSmoke/result-smoke-rev06final.txt` line 67). The knobs are environment variables read once at renderer start (`SWR_PAINT_PHASE_MS`, `SWR_AX_MIN_MS`, `SWR_AX_OFF`, `SWR_FRAME_LOG`, `SWR_MEM_DEEP`); they are proposed as outside the frozen ABI surface.

**Status: NOT FROZEN.** The 0.6 smoke, pixel, matrix, text-geometry, modal and native-interaction receipts exist on tuple 11 or on byte-identical tuples carried to it (section 7). The freeze is withheld with the contract freeze until every blocker listed in section 7 closes or is accepted by Adrian (`docs/sr0-freeze-slice-contract-v1.md` sections 4 and 6).

## 1. Proposed frozen surface, 0.5 baseline (0.6 adds section 5)

### 1.1 Bootstrap and loading
- `SWR_ABI_MAJOR 0`, `SWR_ABI_MINOR 5`; `swr_bootstrap_query(out, caller_size)` and `swr_get_api(out, caller_size)`: any thread, no allocation, no callbacks (header LOADING block).
- Host loads explicitly (`LoadLibraryW`/`GetProcAddress`), validates abi, arch, pointer width and every `*_size` field before resolving anything else (header; `packages/SwiftRightBridge/Sources/SwiftRightBridge/Loader.swift`; typed `SWR_STARTUP_ERROR:` lines, exit 78, per README).
- Rev 0.5: `swr_bootstrap_info.reserved` became `stats_size` (README rev 0.5 (a)).

### 1.2 Functions (14, `SWR_API_FN_COUNT`; `swr_api` = 120 bytes)
`run`, `request_quit`, `window_request_close`, `window_get_metrics`, `commit`, `measure_text`, `text_run_cells`, `text_run_release`, `event_pop`, `request_ticks`, `request_modal`, `selftest_reentry`, `get_stats`, `shutdown_complete` (appended in 0.5). Plus the two exported bootstrap symbols (`swr_bootstrap_query`, `swr_get_api`).
Thread-safe from any thread: bootstrap_query, get_api, request_quit, window_request_close, get_stats. Everything else UI-thread-only, else `SWR_E_WRONG_THREAD` (header THREADING).
Swift surface: `Bridge`, `BridgeWindow`, `Bridge.shutdownComplete()`, `Primitive.underline(_:color:)`, `SemanticNode(identifier:)` (README).

### 1.3 Struct sizes (clang-measured, x86_64; Rust mirror asserts the same; README rev 0.5)
bootstrap 88, host_callbacks 112, api 120, transaction 72, node 144, primitive 80, semantic 88, ax_text_run 80, event 136, measure_request 88, measure_result 56, line_info 24, char_cell 24, **stats 200** (176 -> 200 in 0.5). The remaining six structs (`swr_rect`, `swr_utf16_range`, `swr_utf16_selection`, `swr_run_options`, `swr_window_metrics`, `swr_modal_request`) are now recorded in the README (commit 02e660f: 3 asserted in `abi.rs`, 3 static-asserted); B6 closed.
`swr_stats` fields: 23 counters from the original layout plus `live_nodes` (gauge), `post_close_drains`, `post_close_timeouts` appended (header lines 548-575).

### 1.4 Status codes (header lines 125-143)
`SWR_EMPTY 1`, `SWR_OK 0`, `SWR_E_BAD_ARG -1`, `PANIC -2`, `NOT_READY -3`, `STATE -4`, `PLATFORM -5`, `STALE_HANDLE -6`, `QUEUE_FULL -7`, `TOO_LARGE -8`, `BUSY -9`, `WRONG_THREAD -10`, `STALE_VERSION -11`, `NOT_FOUND -12`, **`SHUTDOWN -13`**, `ABI -14`, `UNSUPPORTED -15`. Numeric values are part of the freeze; new codes append only.

### 1.5 Lifecycle and loop
- `swr_run` blocks on the initial thread; one window per `swr_run` (multi-window deferred, README).
- Callbacks (all UI thread, non-reentrant, outside borrows): `loop_ready`, `drain`, `events_available`, `tick`, `window_closed`, plus seven `ime_*` (`get_selection`, `get_marked`, `copy_text`, `replace`, `replace_and_mark`, `unmark`, `caret_bounds`) that run inside native input handling with restricted permitted calls (header THREADING).
- **Post-close pump (rev 0.5)**: after `window_closed`, renderer frees tree, text runs and AccessKit snapshot (`live_nodes` -> 0) and keeps draining until the host calls `swr_shutdown_complete()` (UI thread, idempotent, `SWR_E_STATE` before close, allowed inside `window_closed`) or `SWR_POST_CLOSE_TIMEOUT_MS` (5000 ms; counted in `post_close_timeouts`). `swr_run` returns when the phase ends. In the pump: `swr_commit` and `swr_measure_text` -> `SWR_E_SHUTDOWN`; `swr_request_ticks`, `swr_request_modal` -> `SWR_E_STALE_HANDLE`; no window or `ime_*` callbacks.
- Host teardown contract: release text runs and drop node state in `window_closed` or during the pump; a text-run handle released after close returns `SWR_E_STALE_HANDLE` (README rev 0.5).
- Frame clock: `swr_request_ticks`, coalesced, QPC timestamp, stops when off or closed.

### 1.6 Commit transaction
Versioned, removes then upserts, all-or-nothing, version must increase (`SWR_E_STALE_VERSION`), window generation checked (`SWR_E_STALE_HANDLE`). Geometry in physical pixels. Node flags `HIT_TARGET 0x1`, `FOCUSABLE 0x2`, `EDITABLE 0x4`.
Primitives (kind): RECT 1, TEXT_RUN 2, IMAGE 3 and PATH 4 (declared, `SWR_E_UNSUPPORTED`), CLIP_PUSH 5, CLIP_POP 6, TRANSFORM_PUSH 7 (translation only), TRANSFORM_POP 8, **UNDERLINE 9** (rev 0.5: solid bar, `rect` = origin, length (w), thickness (h > 0), `color`).
Commit never calls Swift or GPUI. A commit inside an `ime_*` callback is stored and presented after unwind (`commits_deferred`).

### 1.7 Semantics, roles, actions, identifiers
- **Roles**: NONE 0, WINDOW 1, BUTTON 2, STATIC_TEXT 3, TEXT_FIELD 4, **LIST 5, LIST_ITEM 6**, GROUP 7. Contract canonical roles (window, button, text-field, list, list-item, static-text) are a subset; GROUP is the extra (CONTRACT §5 strips platform containers).
- Actions: INVOKE 0x1, FOCUS 0x2, SET_VALUE 0x4, SET_SELECTION 0x8. Semantic flags: HAS_SELECTION, MULTILINE, DISABLED.
- **Identifier** (rev 0.4): `swr_semantic.identifier` UTF-8, <= `SWR_IDENTIFIER_MAX` 256 (longer -> `SWR_E_TOO_LARGE`), mapped to AccessKit `set_author_id` -> UIA AutomationId (README rev 0.4, accesskit_windows 0.35.1 `automation_id`). Uniqueness among siblings is the host's job.
- Static-text label published as AccessKit value so UIA Name = label; empty editable node publishes one zero-length AX text run so TextPattern is offered (README rev 0.4).
- AX text runs: character lengths, positions, widths, word starts; selection.

### 1.8 Measurement
`swr_measure_text` synchronous: size, first/last baseline, line breaks into caller buffer, retained `swr_text_run`, `cache_hit`. Key: text, font, weight, size, width, locale, direction, DPI scale, **colour** (README: colour is baked into shaped runs; contract §6 originally omitted it, see contract change C4). `swr_text_run_cells` per-character geometry (`SWR_CELL_WORD_START`). Direction LTR only (`SWR_DIR_LTR 0`); `\n` rejected.

### 1.9 Events
Kinds: KEY 1, POINTER 2, FOCUS 3, IME 4, AX_ACTION 5, MODAL_RESULT 6, WINDOW_METRICS 7. Bounded queue 256, overflow drops newest and counts. Each tagged with window generation, node id, snapshot; stale-window events dropped at pop and again in Swift. Emitted in v0: key-down, pointer down/up, IME, AX actions, modal results, window metrics. Declared but not emitted: key-up, pointer-move, window-focus (README Deferred) -> the freeze should mark these RESERVED, not frozen behaviour.

### 1.10 Ownership and handles
Generation-tagged `swr_window` / `swr_text_run` (low 32 slot, high 32 generation, 0 invalid); owner-frees; stale handles fail `SWR_E_STALE_HANDLE`; borrowed request pointers; `swr_node_id` host-owned, non-zero, new id on reinsert; panics contained (`SWR_E_PANIC`).

## 2. Evidence per item

| Item | Evidence | State |
|---|---|---|
| Header compiles | `clang -std=c99 -Wall -Wextra -pedantic` clean (README, rev 0.5) | claimed in README; **not re-run by this review** |
| Bootstrap/size validation, ABI 0.5, stats_size 200 | `examples/BridgeSmoke/result-smoke-rev05.txt`: `PASS startup validation [abi 0.5 fn_count=14 stats_size=200]` | PROVEN (Windows) |
| Overall smoke | `examples/BridgeSmoke/result-smoke-rev05c.txt`: **`SMOKE PASS (26/26)`**; timeout mode `result-smoke-timeout05c.txt`: **`SMOKE PASS (27/27)`**. Earlier: rev05 23/23, rev05b 26/26 (96fcd30), re-run on the d45c98c renderer (ee5a4db) | PROVEN (Windows) |
| Measure (wrap at 2 widths, height, line-break coverage, cache hit, 77 char cells) | smoke PASS lines; v0 evidence `b907913` | PROVEN |
| Typed errors: stale run handle, `SWR_E_STALE_VERSION`, bogus window generation (`SWR_E_STALE_HANDLE`), commit after close (`SWR_E_SHUTDOWN`) | smoke PASS lines | PROVEN for these four; other codes (BAD_ARG, QUEUE_FULL, TOO_LARGE, BUSY, WRONG_THREAD, NOT_FOUND, PLATFORM, ABI, UNSUPPORTED, NOT_READY, STATE-before-close) have no smoke assertion in the reviewed output |
| `SWR_E_SHUTDOWN` in post-close | smoke `late async result after close rejected [commit=SWR_E_SHUTDOWN measure=SWR_E_SHUTDOWN]`; also hit in matrix-rev2 as the nil-root teardown commit failure | PROVEN |
| Post-close pump | rev05c: `pump ended by swr_shutdown_complete, not the timeout [shutdown=SWR_OK timeouts=0 run returned 0.02s after window_closed]`; `shutdown_complete before close returns SWR_E_STATE`; `repeat swr_shutdown_complete is idempotent`; stats `live_nodes=0 post_close_drains=1 post_close_timeouts=0`. timeout05c: `pump ended by the 5 s timeout [timeouts=1 run returned 5.00s]`, `shutdown_complete after timeout-ended run rc=SWR_OK` | PROVEN (happy path, early call, repeat, timeout; commit 27d93cc) |
| `swr_stats` size 200 / new fields | smoke `stats_size=200`; stats line prints the three new fields | PROVEN |
| Non-reentrant drain, thread violations, host panics | smoke: `selftest=1 swift_refused=0 rust_refused=0`, `thread_violations=0 host_panics=0` | PROVEN |
| `window_closed` once | smoke `calls=1` | PROVEN |
| No stale/unknown-node events | smoke `stale=0 unknown=0 rust_dropped_stale=0` | PROVEN |
| AX Invoke -> event tagged with generation and snapshot | smoke `AX Invoke handled [invokes=1 window gen tag ok=true]` | PROVEN |
| Typed char reaches text store via `ime_replace`; commit deferred inside IME | smoke PASS, `deferred_in_ime=1` | PROVEN (virtual key); real IME composition and marked-text path PROVEN by `probes/sr0-b/native-interaction/out/RESULT.md` (F7/F7live 20/20 on the final renderer). Known limitation (SR1): the already-open candidate list does not follow a mid-composition layout move (F8 18/19); a TSF text store is the likely fix; not an ABI change |
| Pointer edge click (DPI fix) | smoke `click 2px inside the client edge reached the window`; driver output `window_from_point_is_target=True wm_nchittest=1` | PROVEN |
| Ticks and frames while inactive | smoke `ticks=1078 max_gap_ms=22.6`; `ticks_with_inactive_window=210 of 1078` | PROVEN |
| Empty-edit TextPattern | driver output `empty_edit_textpattern=PASS selections=1 degenerate_at_0=True` | PROVEN |
| **UIA AutomationId** (rev 0.4 identifier) | `result-smoke-rev05c.txt` and `result-smoke-timeout05c.txt`: `automation_id_checks=5/5`, all `name_ok=True`. The rev05 0/5 was the timing race fixed by linger ticks (4000565) | **PROVEN** (5/5) |
| Roles list/list-item through the bridge | Emission added in cc605bf; F1 compare 317 diffs -> 52 after List AX roles (`probes/sr0-o/f1-cross/out/compare-strict-m1-w5.json`, only text-field labels), label fix in cc4c93a | List roles PROVEN by diff reduction; full F1-F9 compare rerun on the final tuple **PENDING (R6: signed Mac recorder, needs Adrian)** |
| **SWR_PRIM_UNDERLINE** | rev05c: `PASS underline primitive (IME marked text) accepted [accepted 1->2 rejected 2->2]`; the renderer exposes no per-primitive draw counter, so painting is not asserted (`stats.paints` counts frames only) | PROVEN as acceptance only, not painting |
| Identifier on real fixture screens | `probes/sr0-s/fresh-on-bridge/out/matrix-rev4/RESULT.md` + `matrix-rev4b`: all 15 configs 3/3 PASS on Windows (ee5a4db) | PROVEN (3 runs per config) |
| Modal | Implemented, loops proven in SR0-B probes (`probes/sr0-b/*`, commit c0b93d8 per history); modal-loop probe updated (23933e1; open stall reported separately as `modal_open_one_off`, the p99 31 ms was the one-off TaskDialog open stall, an SR1 budget item); late-dispatch test and degenerate caret check built (88bfc7a), desktop runs on ABI 0.6: no committed receipt, PENDING; smoke does not exercise the result path (README) | partial |
| Frame budget | commit 011c83e: batch 5, 30/30 valid runs | PROVEN (separate from ABI shape) |

### UIA AutomationId diagnosis (resolved)
The rev05 0/5 result was a timing race: UIA lookups ran after the app self-quit. Linger ticks (4000565) fixed it; rev05c and timeout05c both show `automation_id_checks=5/5`.

## 3. Explicit freeze-blocking items

| # | Item | Needed to clear |
|---|---|---|
| B1 | UIA AutomationId | **CLOSED**: 5/5 in `result-smoke-rev05c.txt` and `result-smoke-timeout05c.txt` |
| B2 | `SWR_PRIM_UNDERLINE` | **CLOSED as acceptance only** (rev05c); no per-primitive draw counter, painting not asserted |
| B3 | List/list-item AX through bridge | **CLOSED**: WIN matrix 15/15 PASS; F1 cross-platform compare 0 diffs (eaf40dc) |
| B4 | Contract freeze dependency | Waits on the SR0-C contract freeze. Closed on 0.5: 20-run matrix (matrix-20b 300/300, `65e0f29`) and F1 compare (`eaf40dc`). On the final 0.6 tuple: matrix 320/320 (R1b, `5a67f23`) and IME/Narrator automatable checks (R9, `541129c`) done; **PENDING:** signed recorder cross-compare (R6), §11 W5 (R10), full runner run and F6 decision (R8), Narrator speech |
| B5 | Post-close pump edge paths | **CLOSED**: early `SWR_E_STATE`, idempotent repeat, 5 s timeout (timeouts=1) in rev05c / timeout05c (27d93cc) |
| B6 | Incomplete size table | **CLOSED** (02e660f) |
| B7 | Smoke evidence reachable | **CLOSED**: rev05c and timeout05c committed (ee5a4db) |
| B9 | **ABI 0.6 smoke and timeout mode** | **CLOSED on tuple 08:** smoke 40/40 (`examples/BridgeSmoke/result-smoke-rev08.txt:83`) and timeout mode 41/41 (`result-smoke-timeout08.txt:84`), exe `21992F16…`, renderer `E280F4A9…` (ARTIFACTS lines `result-smoke-rev08.txt:104`, `result-smoke-timeout08.txt:105`), Dell desktop; the tuple 06 pair (`result-smoke-rev06final.txt`, `541129c`) is history. Earlier: rev06c on `777F14C4…` (`862997c`) and rev06f on `4FB068F0…` (`45f707d`), each 40/40 and 41/41, history. The real menu and dialog modal result paths now have a receipt on tuple 08 (section 6, Modal06 20/20) |
| B10 | Snapshot manifest | **CLOSED:** tuple 08 in `docs/sr0-snapshot.md` section 2d with receipts: matrix-08 319/320 plus rerun 3/3 (`probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md`), BridgeSmoke (`result-smoke-rev08.txt`), MSIX pair built and signed on the renderer pin (`examples/SliceApp/RESULT-R5-08.md`). Renderer provenance: the committed-tree rebuild of `9c261d4` hashed `E280F4A9` (`renderer-pin.json`), so the bytes match the committed source; the DLL is unsigned |
| B8 | Declared-not-emitted events | **Decided:** freeze as RESERVED (key-up, pointer-move, window-focus): codes fixed, hosts must tolerate but not rely on them; emitting them later is an append-only minor bump |

Non-blocking but record in the freeze note: arm64 (README Deferred), packaging/checksum-pinned payload/signing (README Deferred, `docs/sr0-status.md` SR0-P blocked), multi-window, IMAGE/PATH primitives, non-translation transforms, bidi, multi-paragraph text, font fallback, modal result smoke, menus, scroll/touch/drag. Rev 0.5 is ABI-incompatible with 0.4 by bootstrap check (`stats_size`, function count 13 -> 14), so the freeze also fixes the "minor mismatch rejects" policy: the loader validates exact sizes, so any later minor bump needs a host rebuild.

## 4. Proposed freeze decision

Freeze **ABI 0.6** (sections 1 to 3 as the baseline plus section 5) as the SR0 interface, built from renderer DLL sha256 `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` (tuple 08). B9 and B10 are closed and the matrix on tuple 08 passed (319/320, the failure is external typed input, rerun 3/3); the freeze itself waits on the contract freeze (B4) and its PENDING blockers. On 0.5, B1, B2, B5, B6, B7 are closed by receipts and B8 is decided (RESERVED); B3 closed on 0.5; B4 closes through the contract freeze. A 0.5 receipt does not close a 0.6 item. Changes after freeze append only (struct tails, function-table tail, new codes) and bump the minor; layout of existing fields and numeric constants in sections 1.3-1.9 do not change. Because the loader validates exact sizes and function count, any later minor bump needs a host rebuild.

## 5. ABI 0.6 delta over 0.5 (append-only; part of the retargeted freeze)

The rule holds: from 0.5 to 0.6, changes are append-only (struct tails, function-table tail, new codes and constants); no layout change to an existing field, constant or offset. ABI 0.6 (SR1, `render/README-abi-v0.md` "0.6") follows it and bumps the bootstrap minor to 6, so a 0.5 host or renderer is rejected at startup. Nothing in sections 1 to 4 changes meaning.

| Addition | How it stays append-only |
|---|---|
| Roles 8..14 (`CHECKBOX`, `SWITCH`, `IMAGE`, `MENU`, `MENU_ITEM`, `ALERT`, `DIALOG`) | new constants after `GROUP 7`; AccessKit `Role` / UIA mapping cited in the README |
| `swr_semantic.toggled`, `SWR_SEM_SELECTABLE 0x8`, `SWR_SEM_SELECTED 0x10`, `SWR_TOGGLED_*` | `toggled` reuses the former `reserved` slot (offset 84, size 4; old hosts zeroed it = NONE); flags are new bits. `swr_semantic` stays 88 bytes |
| `SWR_SEM_DISABLED` now honoured | constant unchanged (declared since 0.4); behaviour was "ignored", now AccessKit disabled plus input routing |
| `swr_image`, `swr_image_register`, `swr_image_release`, `SWR_PRIM_IMAGE` live | `swr_api` gains two function pointers at the TAIL (14 -> 16, 120 -> 136 bytes); `swr_primitive.image` reuses the former `reserved[2]` (offset 72, size 8; `swr_primitive` stays 80); `SWR_PRIM_IMAGE 3` was declared since v0 (it returned `SWR_E_UNSUPPORTED`) |
| `SWR_MODAL_MENU 2`, `SWR_MODAL_DIALOG 3`, `swr_modal_item` | new kinds; `swr_modal_request` gains a TAIL (48 -> 80 bytes, old fields untouched); result events reuse `SWR_EV_MODAL_RESULT` (`action` = kind, `i0` = item id, `i1` = index) |
| `\n` in `swr_measure_text`, `SWR_CELL_LINE_BREAK 0x2` | the v0 rejection (`SWR_E_UNSUPPORTED`) is lifted; the cell flag is a new bit; no struct changed. `\r` is still rejected |

Consequences for this proposal: section 1.8's "`\n` rejected" and the IMAGE row of section 1.6 ("declared, `SWR_E_UNSUPPORTED`") describe 0.5; in 0.6 IMAGE is live and `\n` is accepted. Section 1.2's 14-function table is the 0.5 table; 0.6 appends `image_register` and `image_release`. The freeze hash in section 4 now names the 0.6 renderer. The 0.6 smoke has run on a desktop (section 6). It stays PROPOSED until the contract freeze closes.

## 6. ABI 0.6 evidence on the final tuple (tuple 08)

| Item | Evidence | State |
|---|---|---|
| Startup validation | `result-smoke-rev06final.txt` line 67 (tuple 06; tuple 08 `result-smoke-rev08.txt`, same line): `PASS startup validation [abi 0.6 fn_count=16 stats_size=200]` | PROVEN (final renderer) |
| Smoke and timeout mode | 40/40 and 41/41 on tuple 08 (`result-smoke-rev08.txt:83`, `result-smoke-timeout08.txt:84`; exe `21992F16…`, renderer `E280F4A9…`) | PROVEN |
| Roles 8..14, toggled, selected, disabled | smoke `r06[...]` UIA lines (checkbox `toggle=On`, switch, mixed `toggle=Indeterminate`, image `ControlType.Image`) and `PASS rev 0.6 roles, toggled, selected and disabled accepted in one commit` | PROVEN (acceptance and UIA mapping) |
| Image register/release | smoke: registered (`live_nodes +1`), `SWR_PRIM_IMAGE` accepted, release drops the host handle only, freed once unreferenced, released handle rejected (`SWR_E_STALE_HANDLE`), argument errors typed | PROVEN as acceptance and lifetime; painting not asserted (no per-primitive draw counter) |
| `\n` in `swr_measure_text` | smoke: multi-paragraph measure, per-line AX runs, caret after a trailing newline, each paragraph wraps on its own, `\r` still `SWR_E_UNSUPPORTED` | PROVEN |
| Menu and dialog modal kinds | smoke: argument validation only (`0 buttons=SWR_E_BAD_ARG`, `9 buttons=SWR_E_TOO_LARGE`, duplicate ids, default out of range, only separators, 65 items) | arguments PROVEN; real result paths PROVEN on tuple 08: Modal06 (`examples/BridgeGeoModal/result-modal08.txt:268`) 20/20 runs first attempt, 0 stalls in 120 modals (`:257`), the lost-wake fix `02b3cc0` proven by A/B (`result-modalfix-legacy.txt` 2 stalls in 180 modals, `result-modalfix-fixed.txt` 0 in 360) |
| Post-close pump, `live_nodes` | smoke: `live nodes zero after teardown`, `pump ended by swr_shutdown_complete`, timeout mode `post_close_timeouts=1` | PROVEN |
| Text geometry | `examples/BridgeGeoModal/result-textgeom08.txt:93` TextGeom06 20/20 (66 checks each); AX fix proof `result-textgeom-axfix.txt` (`9c261d4`, 60/60) | PROVEN |
| Fixture matrix through the bridge | matrix-08 `RESULT.md`: 319/320, rerun of the one external-input failure 3/3 (earlier tuple 06 matrix-final 320/320, history) | PROVEN |
| Real IME, Narrator | native-interaction on tuple 08 (`probes/sr0-b/native-interaction/out/*-tuple08.txt`, `840f9ec`): IME F7 20/20, F7live 20/21, F8 18/19, Narrator 8/8 automatable | PROVEN except the limitation below |
| Throughput | §11 workload on the final renderer (`probes/sr0-b/workload/results/ITERATION.md`): bridge time per input p95 0.45 ms and per committed frame p95 0.80 ms (`r10-20261010-renderer7533-windows.txt`, run r1; limits 1.0 and 2.0 ms) | PROVEN for W2 and W3; W5 zero missed vblanks NOT MET on tuple 08 (5, 1, 1 per run, `r10-20261010-tuple08-renderere280-windows.txt:40,79,118`; status doc) |

Known limitations of the 0.6 surface as frozen (sources: `docs/sr0-freeze-slice-contract-v1.md` section 6): IME candidate list does not follow a mid-composition layout move (SR1, TSF text store; F7live 20/21 and F8 18/19 fail only `candidate-window-follows-layout-move`, `native-ime-f8-tuple08.txt`); Narrator speech not machine-verifiable (`native-narrator-tuple08.txt`); W5 1-6 missed vblanks per 60 s on the hybrid-GPU Dell (`r10-20261010-tuple08-renderere280-windows.txt`); the cold first dialog open can exceed the 50 ms open bound (60.90 ms once on tuple 07, `result-modal07.txt:4`; tuple 08 max 39.59 ms, `result-modal08.txt:262`); no per-primitive draw counter (underline and image painting not asserted); reserved events (key-up, pointer-move, window-focus) are declared, not emitted (B8).

## 7. Binding to tuple 11, proposed contract changes and what still blocks (11 October 2026)

ABI evidence on the final tuple. A receipt carries only where the binaries are byte-identical (`docs/sr0-snapshot.md` section 2e).

| Item | Evidence | State |
|---|---|---|
| Startup validation, smoke, timeout mode | Tuple 09, carried (BridgeSmoke `85D5F8BA…`, renderer `E280F4A9…` byte-identical on tuple 11): `examples/BridgeSmoke/result-smoke-rev09.txt:83` (40/40) and `result-smoke-timeout09.txt:84` (41/41); ARTIFACTS lines `:104`, `:105`; startup validation `abi 0.6 fn_count=16 stats_size=200` | PROVEN |
| Rendered output (underline, image cells, corners, clips, translate) | `examples/BridgeSmoke/result-smoke-pixels09.txt:4`, `result-bridgepixels09.txt:4,22`: 10/10 runs on two capture methods (PrintWindow and screen), negative controls fail | PROVEN; supersedes "painting not asserted" in sections 2, 3 (B2) and 6 |
| Text geometry, real modal paths, cold open | `result-textgeom09.txt:93` (20/20); `result-modal09.txt:256,263,269` (20/20, 0 stalls in 120 modals, `modal_open_one_off` max 39.46 ms); `result-coldopen09.txt:7-12` (cold dialog M1 max 45.99 ms; M2 request-to-visible max 52.16 ms, 1 of 20 above 50 ms) | PROVEN; M2 above 50 ms once is a recorded limitation |
| Fixture matrix through the bridge | Matrix 11, tuple 11: 320/320 PASS first attempt (`probes/sr0-s/fresh-on-bridge/out/matrix-11/RESULT.md:7`, `2c84c0f4`) | PROVEN |
| Real IME, Narrator | Tuple 10 (fixture host replaced on tuple 11): F7 17/20 then 20/20, F7live 20/21, F8 18/19, Narrator 8/8 automatable (`probes/sr0-b/native-interaction/out/*-tuple10*.txt`, `0c0a4f93`) | **tuple 11 run: running, no committed result**; limitation unchanged |
| Throughput | Tuple 10 workload (WorkloadWin `5270D3E5…`, byte-identical on tuple 11): W2 p95 0.55 ms or less per input (limit 1.0), W3 p95 0.89 ms or less per committed frame (limit 2.0), W4 p95 46.37-48.83 ms, W6 p99 9.14 ms or less (`probes/sr0-b/workload/results/r10-20261011-tuple10-renderere280-windows.txt`) | PROVEN for W2, W3, W6; presentation under the 2026-10-10 bar (below) |

Proposed contract changes that touch the bridge's acceptance (full text and basis in `docs/sr0-freeze-slice-contract-v1.md` section 3): **C9** the F6 animation completion pair is unordered (a comparison rule; no ABI effect); **C10** the zero-missed-vblank criterion is replaced by "no worse than Mac SwiftUI on the same workload for input-to-visible latency and frame-interval p95, missed vblanks reported, not gated" (Adrian, 2026-10-10, `docs/sr0-findings.md` section 11, `docs/architecture.md` §11 revision 2); **C11** `onAppear`/`onDisappear` counts of List rows inserted under an animation are unspecified (a comparison rule). None changes a header field, constant or offset.

Performance-bar decision and numbers: Windows tuple 10 W4 p95 46.37 / 48.73 / 48.83 ms and interval p95 16.73-16.74 ms, missed vblanks 1, 1, 1; Mac SwiftUI W4 p95 71.6 / 75.9 / 78.9 ms and interval p95 17.82-17.94 ms, 0 missed through a ScreenCaptureKit proxy (`probes/sr0-b/workload/results/MAC-WORKLOAD.md`, with its caveats).

**What still blocks the freeze (all must close, or be accepted by Adrian):** (1) tuple 11 cross-compare of the 16 configs, running; (2) tuple 11 R9, running; (3) Narrator speech content, a person listening at the Dell, about 2 min; (4) the R5 W08 acceptance decision; (5) the record of the retry-cap overruns; (6) contract text C1-C8, C3, C9-C11 applied to `CONTRACT.md` and the analyzer's W5 verdict changed to the C10 bar; (7) cross-compare items R5, R6, R8 unproven; (8) a full runner run on tuple 11. Companion list with lanes: `docs/sr0-freeze-slice-contract-v1.md` section 4.

Known limitations of the 0.6 surface as proposed for freeze: the tuple 08 list above, plus: F7 had one flaky run on tuple 10 (17/20, rerun 20/20); missed vblanks are reported, not gated; cold dialog M2 request-to-visible occasionally above 50 ms (52.16 ms, 1 of 20); selection highlight is not painted (caret only; the AX selection is published, `0e4927aa`); W08 has three measured user recoveries (`examples/SliceApp/RESULT-R5-W08-recovery-08.md`).
