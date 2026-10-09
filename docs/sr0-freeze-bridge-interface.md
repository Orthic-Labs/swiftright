# SR0-B bridge interface (ABI rev 0.5): freeze proposal

**PROPOSAL — pending evidence noted inline.** Nothing here is frozen. Compiled 9 October 2026, updated evening against HEAD ee5a4db, from repository evidence only. Renderer changed after 10c4877 (d45c98c, post-close pump survives GPUI quit-on-last-window); the freeze names that build, DLL sha256 `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1`. Sources: `render/swiftright-abi/include/swiftright.h` (single source of truth), `render/README-abi-v0.md` (revision notes and evidence), `packages/SwiftRightBridge/`, `examples/BridgeSmoke/`. History: b907913 (v0, smoke 19/19), b9651bd (rev 0.4), 10c4877 (rev 0.5, "built; smoke pending desktop"). The README states "Not frozen (freeze waits on the SR0-C contract freeze)"; companion proposal: `docs/sr0-freeze-slice-contract-v1.md`.

## 1. Proposed frozen surface (ABI 0.5 -> "ABI 1" candidate)

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
| Typed char reaches text store via `ime_replace`; commit deferred inside IME | smoke PASS, `deferred_in_ime=1` | PROVEN (virtual key; real IME composition and `ime_replace_and_mark`/marked-text path: not in smoke) |
| Pointer edge click (DPI fix) | smoke `click 2px inside the client edge reached the window`; driver output `window_from_point_is_target=True wm_nchittest=1` | PROVEN |
| Ticks and frames while inactive | smoke `ticks=1078 max_gap_ms=22.6`; `ticks_with_inactive_window=210 of 1078` | PROVEN |
| Empty-edit TextPattern | driver output `empty_edit_textpattern=PASS selections=1 degenerate_at_0=True` | PROVEN |
| **UIA AutomationId** (rev 0.4 identifier) | `result-smoke-rev05c.txt` and `result-smoke-timeout05c.txt`: `automation_id_checks=5/5`, all `name_ok=True`. The rev05 0/5 was the timing race fixed by linger ticks (4000565) | **PROVEN** (5/5) |
| Roles list/list-item through the bridge | Emission added in cc605bf; F1 compare 317 diffs -> 52 after List AX roles (`probes/sr0-o/f1-cross/out/compare-strict-m1-w5.json`, only text-field labels), label fix in cc4c93a | List roles PROVEN by diff reduction; full compare rerun **PENDING (blocked: Windows desktop runs blocked by desktop-intrusion hook, pending Adrian)** |
| **SWR_PRIM_UNDERLINE** | rev05c: `PASS underline primitive (IME marked text) accepted [accepted 1->2 rejected 2->2]`; the renderer exposes no per-primitive draw counter, so painting is not asserted (`stats.paints` counts frames only) | PROVEN as acceptance only, not painting |
| Identifier on real fixture screens | `probes/sr0-s/fresh-on-bridge/out/matrix-rev4/RESULT.md` + `matrix-rev4b`: all 15 configs 3/3 PASS on Windows (ee5a4db) | PROVEN (3 runs per config) |
| Modal | Implemented, loops proven in SR0-B probes (`probes/sr0-b/*`, commit c0b93d8 per history); modal-loop probe updated (23933e1; open stall reported separately as `modal_open_one_off`, the p99 31 ms was the one-off TaskDialog open stall, an SR1 budget item); late-dispatch test and degenerate caret check built (88bfc7a), desktop runs PENDING (blocked); smoke does not exercise the result path (README) | partial |
| Frame budget | commit 011c83e: batch 5, 30/30 valid runs | PROVEN (separate from ABI shape) |

### UIA AutomationId diagnosis (resolved)
The rev05 0/5 result was a timing race: UIA lookups ran after the app self-quit. Linger ticks (4000565) fixed it; rev05c and timeout05c both show `automation_id_checks=5/5`.

## 3. Explicit freeze-blocking items

| # | Item | Needed to clear |
|---|---|---|
| B1 | UIA AutomationId | **CLOSED**: 5/5 in `result-smoke-rev05c.txt` and `result-smoke-timeout05c.txt` |
| B2 | `SWR_PRIM_UNDERLINE` | **CLOSED as acceptance only** (rev05c); no per-primitive draw counter, painting not asserted |
| B3 | List/list-item AX through bridge | WIN matrix 15/15 PASS; F1 cross-platform compare rerun **OPEN (blocked)** after cc4c93a |
| B4 | Contract freeze dependency | README says ABI freeze waits on the SR0-C contract freeze; contract blockers in `docs/sr0-freeze-slice-contract-v1.md` section 4 (C9 20-run Windows matrix OPEN). `docs/sr0-status.md` updated to 0.5 |
| B5 | Post-close pump edge paths | **CLOSED**: early `SWR_E_STATE`, idempotent repeat, 5 s timeout (timeouts=1) in rev05c / timeout05c (27d93cc) |
| B6 | Incomplete size table | **CLOSED** (02e660f) |
| B7 | Smoke evidence reachable | **CLOSED**: rev05c and timeout05c committed (ee5a4db) |
| B8 | Declared-not-emitted events | **Decided:** freeze as RESERVED (key-up, pointer-move, window-focus): codes fixed, hosts must tolerate but not rely on them; emitting them later is an append-only minor bump |

Non-blocking but record in the freeze note: arm64 (README Deferred), packaging/checksum-pinned payload/signing (README Deferred, `docs/sr0-status.md` SR0-P blocked), multi-window, IMAGE/PATH primitives, non-translation transforms, bidi, multi-paragraph text, font fallback, modal result smoke, menus, scroll/touch/drag. Rev 0.5 is ABI-incompatible with 0.4 by bootstrap check (`stats_size`, function count 13 -> 14), so the freeze also fixes the "minor mismatch rejects" policy: the loader validates exact sizes, so any later minor bump needs a host rebuild.

## 4. Proposed freeze decision

Freeze ABI 0.5 as the SR0 interface, built from renderer d45c98c (DLL sha256 `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1`). B1, B2, B5, B6, B7 are closed by receipts; B3/B4 close through the contract proposal (F1 compare rerun and C9); B8 decided (RESERVED). Changes after freeze append only (struct tails, function-table tail, new codes) and bump the minor; layout of existing fields and numeric constants in sections 1.3-1.9 do not change.
