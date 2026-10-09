# SR0-B bridge interface (ABI rev 0.5): freeze proposal

**PROPOSAL — pending evidence noted inline.** Nothing here is frozen. Compiled 9 October 2026 from repository evidence only. Sources: `render/swiftright-abi/include/swiftright.h` (single source of truth), `render/README-abi-v0.md` (revision notes and evidence), `packages/SwiftRightBridge/`, `examples/BridgeSmoke/`. History: b907913 (v0, smoke 19/19), b9651bd (rev 0.4), 10c4877 (rev 0.5, "built; smoke pending desktop"). The README states "Not frozen (freeze waits on the SR0-C contract freeze)"; companion proposal: `docs/sr0-freeze-slice-contract-v1.md`.

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
bootstrap 88, host_callbacks 112, api 120, transaction 72, node 144, primitive 80, semantic 88, ax_text_run 80, event 136, measure_request 88, measure_result 56, line_info 24, char_cell 24, **stats 200** (176 -> 200 in 0.5). Further structs in the header (`swr_rect`, `swr_utf16_range`, `swr_utf16_selection`, `swr_run_options`, `swr_window_metrics`, `swr_modal_request`) have no size recorded in the README: **size table must be completed before freeze** (blocking item B6).
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
| Overall smoke | same file: **`SMOKE PASS (23/23)`** (app-side checks) | PROVEN app-side |
| Measure (wrap at 2 widths, height, line-break coverage, cache hit, 77 char cells) | smoke PASS lines; v0 evidence `b907913` | PROVEN |
| Typed errors: stale run handle, `SWR_E_STALE_VERSION`, bogus window generation (`SWR_E_STALE_HANDLE`), commit after close (`SWR_E_SHUTDOWN`) | smoke PASS lines | PROVEN for these four; other codes (BAD_ARG, QUEUE_FULL, TOO_LARGE, BUSY, WRONG_THREAD, NOT_FOUND, PLATFORM, ABI, UNSUPPORTED, NOT_READY, STATE-before-close) have no smoke assertion in the reviewed output |
| `SWR_E_SHUTDOWN` in post-close | smoke `late async result after close rejected [commit=SWR_E_SHUTDOWN measure=SWR_E_SHUTDOWN]`; also hit in matrix-rev2 as the nil-root teardown commit failure | PROVEN |
| Post-close pump | smoke: `cleanup ran in post-close pump [post_close_drains=1]`; `pump ended by swr_shutdown_complete, not the timeout [shutdown=SWR_OK timeouts=0]`; `live nodes zero after teardown [at cleanup=0 after run=0]`; stats line `live_nodes=0 post_close_drains=1 post_close_timeouts=0` | PROVEN on the happy path. **Not exercised**: timeout path (5000 ms), `SWR_E_STATE` for `shutdown_complete` before close, idempotent second call |
| `swr_stats` size 200 / new fields | smoke `stats_size=200`; stats line prints the three new fields | PROVEN |
| Non-reentrant drain, thread violations, host panics | smoke: `selftest=1 swift_refused=0 rust_refused=0`, `thread_violations=0 host_panics=0` | PROVEN |
| `window_closed` once | smoke `calls=1` | PROVEN |
| No stale/unknown-node events | smoke `stale=0 unknown=0 rust_dropped_stale=0` | PROVEN |
| AX Invoke -> event tagged with generation and snapshot | smoke `AX Invoke handled [invokes=1 window gen tag ok=true]` | PROVEN |
| Typed char reaches text store via `ime_replace`; commit deferred inside IME | smoke PASS, `deferred_in_ime=1` | PROVEN (virtual key; real IME composition and `ime_replace_and_mark`/marked-text path: not in smoke) |
| Pointer edge click (DPI fix) | smoke `click 2px inside the client edge reached the window`; driver output `window_from_point_is_target=True wm_nchittest=1` | PROVEN |
| Ticks and frames while inactive | smoke `ticks=1078 max_gap_ms=22.6`; `ticks_with_inactive_window=210 of 1078` | PROVEN |
| Empty-edit TextPattern | driver output `empty_edit_textpattern=PASS selections=1 degenerate_at_0=True` | PROVEN |
| **UIA AutomationId** (rev 0.4 identifier) | driver output `automation_id_checks=0/5`, all five `NOT_FOUND`, and `uia_edit=NOT_FOUND`; `AUTOMATIONID FAIL` | **FAILED in this run; suspected timing race** (see below) |
| Roles list/list-item through the bridge | Emission added in cc605bf (`fresh-on-bridge`); the pre-fix F1 compare (`probes/sr0-o/f1-cross/out/compare-strict-m1-w4.json`) failed with `role=list-item` absent | **PENDING**: no post-fix compare recorded |
| **SWR_PRIM_UNDERLINE** | Defined in header and README; no smoke assertion, no fixture use found | **NOT EXERCISED** |
| Identifier on real fixture screens | `probes/sr0-s/fresh-on-bridge/out/matrix-rev3/` (untracked, incomplete: F1, F2, F3 list/vstack/lazy-1s only) | PENDING completion |
| Modal | Implemented, loops proven in SR0-B probes (`probes/sr0-b/*`, commit c0b93d8 per history); smoke does not exercise the result path (README) | partial |
| Frame budget | commit 011c83e: batch 5, 30/30 valid runs | PROVEN (separate from ABI shape) |

### UIA AutomationId diagnosis (suspected, not confirmed)
Result file shows `uia_edit=NOT_FOUND` as well as all five ids, while `uia_invoke=ok` and `empty_edit_textpattern=PASS` succeeded earlier in the same run, and the app finished in about 2 minutes. Working-tree changes (uncommitted: `examples/BridgeSmoke/Sources/BridgeSmoke/main.swift`, `scripts/drive-smoke.ps1`; patch copy `examples/BridgeSmoke/uia-rev05-fix.patch`) add `SWR_SMOKE_LINGER_TICKS` (default 90 ticks, driver sets 900) so UIA lookups finish before the app self-quits after typing. That patch's own comment states the intent ("so UIA lookups cannot race the self-quit"). Whether `result-smoke-rev05.txt` was produced with or without the patch is **not stated in the file**. Until a rerun with the lingering driver finds 5/5 ids, treat the identifier path as unproven for rev 0.5 (it was the stated deliverable of rev 0.4, b9651bd).

## 3. Explicit freeze-blocking items

| # | Item | Needed to clear |
|---|---|---|
| B1 | UIA AutomationId 0/5 | Rerun with lingering driver (patch above) showing 5/5 `automation_id[...]` and `uia_edit` found; commit the patch and `result-smoke-rev05.txt` |
| B2 | `SWR_PRIM_UNDERLINE` unexercised | A smoke or fixture assertion that commits an underline (accepted, `h > 0`; `h == 0` behaviour per header), plus ideally a visual or paint-count check |
| B3 | List/list-item AX through bridge | Post-cc605bf F1 cross-platform compare passing (`probes/sr0-o/f1-cross`) and WIN-M3 completion (see contract doc) |
| B4 | Contract freeze dependency | README says ABI freeze waits on the SR0-C contract freeze; contract blockers listed in `docs/sr0-freeze-slice-contract-v1.md` section 4. `docs/sr0-status.md` SR0-B row still reads "ABI rev 0.4 smoke 19/19 ... freeze pending runtime-gap rerun" and needs updating to 0.5 (23/23) |
| B5 | Post-close pump edge paths | Evidence for `swr_shutdown_complete` before close (`SWR_E_STATE`), idempotent repeat, and timeout path (`post_close_timeouts` increments) |
| B6 | Incomplete size table | Record `sizeof` for `swr_rect`, `swr_utf16_range`, `swr_utf16_selection`, `swr_run_options`, `swr_window_metrics`, `swr_modal_request` (not in README list) and confirm the Rust mirror assertions |
| B7 | Uncommitted rev 0.5 smoke evidence | `result-smoke-rev05.txt` and `uia-rev05-fix.patch` are untracked; working-tree modifications to BridgeSmoke are uncommitted. Freeze evidence must be a reachable commit |
| B8 | Declared-not-emitted events | Decide: freeze as RESERVED (key-up, pointer-move, window-focus), not as shipped behaviour |

Non-blocking but record in the freeze note: arm64 (README Deferred), packaging/checksum-pinned payload/signing (README Deferred, `docs/sr0-status.md` SR0-P blocked), multi-window, IMAGE/PATH primitives, non-translation transforms, bidi, multi-paragraph text, font fallback, modal result smoke, menus, scroll/touch/drag. Rev 0.5 is ABI-incompatible with 0.4 by bootstrap check (`stats_size`, function count 13 -> 14), so the freeze also fixes the "minor mismatch rejects" policy: the loader validates exact sizes, so any later minor bump needs a host rebuild.

## 4. Proposed freeze decision

Freeze ABI 0.5 as the SR0 interface once B1, B2, B5, B6, B7 are closed by receipts, and B3/B4 close through the contract proposal. Changes after freeze append only (struct tails, function-table tail, new codes) and bump the minor; layout of existing fields and numeric constants in sections 1.3-1.9 do not change.
