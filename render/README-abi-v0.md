# SwiftRight renderer bridge, ABI v0 (revision 0.4)

Consolidates the SR0-B/SR0-D probes into the planned packages. Not frozen (freeze waits on the SR0-C contract freeze). Nothing committed.

| Path | What |
|---|---|
| `render/swiftright-abi/include/swiftright.h` | The C ABI: bootstrap query, handles, status codes, host callback table, commit transaction, measurement, events, modal request. Threading and ownership rules are in its header comment. Clean under `clang -std=c99 -Wall -Wextra -pedantic`. |
| `render/swiftright-render/` | Rust cdylib `swiftright_render.dll` (gpui =0.2.2, accesskit =0.25.1, accesskit_windows =0.35.1, raw-window-handle =0.6.2; `Cargo.lock` from `probes/sr0-b/text-geometry`). |
| `packages/SwiftRightBridge/` | Swift package: `CSwiftRight` systemLibrary (header is a symlink to the single source, no `link` directive), loader, marshalling, `Bridge` / `BridgeWindow`. Windows code behind `#if os(Windows)`; on macOS it builds and `Bridge.load` throws `unsupportedPlatform`. |
| `examples/BridgeSmoke/` | Windows smoke executable + scripts (`build-smoke.ps1`, `drive-smoke.ps1`, `schedule-smoke.ps1`). |

## Revision notes

- **0.4** (SR0-B): `swr_semantic` gains an optional stable identifier, `identifier` (UTF-8 ptr + `identifier_len`, at most `SWR_IDENTIFIER_MAX` = 256 bytes, longer is `SWR_E_TOO_LARGE`; NULL/0 = none), plus a reserved word. Appended at the end of the struct: `swr_semantic` 72 -> 88 bytes, `swr_node` 128 -> 144 bytes (clang-measured; the Rust mirror asserts the same). The renderer maps it to AccessKit `Node::set_author_id` (accesskit 0.25.1, `src/lib.rs` `AuthorId` entry), which accesskit_windows 0.35.1 publishes as the UIA `AutomationId` (`src/node.rs` `automation_id`, falls back to `author_id` when no `html_id` is set; `UIA_AutomationIdPropertyId` mapping). Mac counterpart: `AXIdentifier`. Uniqueness among siblings is the host's job and is not checked. Swift: `SemanticNode(identifier:)`.
  Same revision, two UIA mappings the SR0-O recorder found:
  - Static text: accesskit_consumer `label_comes_from_value()` is true for `Role::Label` (`src/node.rs`), and accesskit_windows `name()` (`src/node.rs`) writes the value as the UIA Name. The renderer therefore publishes a static text's label as its AccessKit value when the value is empty, so UIA Name = label.
  - Empty editable node: accesskit_consumer `supports_text_ranges()` (`src/text.rs`) needs at least one text run, and UIA TextPattern is offered only when it holds. `makeAXTextRuns` publishes one zero-length run for empty text, so an empty field exposes TextPattern with a degenerate selection at 0. Run id = `firstRunID`.
  - Source citations: accesskit_consumer 0.39.1 (lockfile), docs.rs source; accesskit 0.25.1 `set_author_id`; accesskit_windows 0.35.1 `automation_id` and the `Role::Label` / `TextInput` / `Button` control-type mapping.
- **0.3**: previous revision, no node identifier (the SR0-S gap: Windows rows could only be labelled "Row N").

## What v0 covers

- **Bootstrap**: caller-sized `swr_bootstrap_query` (abi 0.3, arch, pointer width, 12 struct sizes, fn count), then `swr_get_api` fills the function table. The Swift loader uses `LoadLibraryW`/`GetProcAddress` only, validates before resolving anything else, and emits typed `SWR_STARTUP_ERROR:` lines (missing DLL, error 127 hints at the ComCtl v6 manifest, abi/arch/size mismatch) with exit 78.
- **Handles**: generation-tagged window and text-run handles, explicit release, stale handles fail `SWR_E_STALE_HANDLE`. Typed status enum (`SWR_E_*`). Every entry point is wrapped in `catch_unwind` (`SWR_E_PANIC`).
- **Loop**: `swr_run` blocks on the initial thread; the Swift main dispatch queue is drained from a GPUI foreground task (`_dispatch_main_queue_callback_4CF`), outside every GPUI borrow, behind a non-reentrant guard on both sides (self-test included). Wake path = waiter thread on the dispatch wake HANDLE.
- **Frame clock**: `swr_request_ticks`; ticks come from presented-frame `request_animation_frame`, coalesced, delivered with a QPC timestamp, stop when off or closed.
- **Commit**: versioned transaction (removes then upserts, all-or-nothing, version must increase, window generation checked). Physical-px geometry; primitives: rect (radius, border), text run, clip push/pop, translate push/pop; semantic node (role, label, value, actions, AX text runs with character lengths/positions/widths/word starts, selection); focus target. Commit never calls Swift or GPUI: it updates Rust-owned state, and the drain task presents it (refresh + AccessKit update). A commit made inside an IME callback is stored at once and presented after the callback unwinds (counted as `commits_deferred`).
- **Measurement**: synchronous `swr_measure_text` (size, first/last baseline, line breaks into a caller buffer, retained run handle, `cache_hit`, cache key over text, font, weight, size, width, locale, direction, DPI scale, colour) and `swr_text_run_cells` (per-character geometry for AX/caret). Uses an independently retained text system, never a GPUI borrow.
- **AccessKit**: one `SubclassingAdapter` (window created hidden, adapter attached, then shown). Actions (Invoke, Focus, SetValue, SetSelection) only validate against the live tree, enqueue a window/node/snapshot tagged record and wake the loop.
- **IME**: GPUI's IMM32 `EntityInputHandler` bridged to the `ime_*` callback table (selection, marked range, text, replace, replace-and-mark, unmark, caret bounds), UTF-16 ranges, host owns the buffer. Same non-reentrancy guard; busy calls are refused and counted.
- **Events**: bounded pop queue (256, overflow drops the new event and counts it) for key-down, pointer down/up (Rust hit-tests the committed snapshot), IME notices, AX actions, modal results, window metrics; each tagged with window generation, node and snapshot; stale-window events dropped at pop and again in Swift.
- **Modal**: `swr_request_modal` queues a `MessageBoxW`, opened from a separate foreground task after the drain unwinds; result arrives as an event.
- **Window**: opaque background (`WindowBackgroundAppearance::Opaque`) plus a full-window rect painted every frame; the renderer sets per-monitor-v2 DPI awareness before creating the window and logs `WS_EX_*` styles at startup.

## Deferred (declared in the header or absent)

- More than one window; `swr_window_open`. v0 opens exactly one window inside `swr_run`.
- `SWR_PRIM_IMAGE` and `SWR_PRIM_PATH` (return `SWR_E_UNSUPPORTED`); non-translation transforms.
- RTL/bidi (`direction != 0`), multi-paragraph text (`\n` rejected), font fallback/locale-specific shaping control.
- Key-up, pointer-move and window-focus events (kinds declared, not emitted); touch, scroll, drag.
- Modal result path is implemented but not exercised by the smoke (a `MessageBoxW` needs a human or extra driver); menus are not implemented.
- Real controls (no theme metrics, no list/scroll primitives). Painting is minimal by design.
- arm64, packaging/MSIX staging, checksum-pinned payload, reproducibility check, signing.
- Colour is part of the cache key and baked into the shaped run (GPUI bakes colour at shaping); CONTRACT section 6's key omits it. Needs a CONTRACT note.
- Rendering when the host does not set DPI awareness itself: the renderer calls `SetProcessDpiAwarenessContext` as a fallback, but hosts should declare it in their manifest.

## Evidence: Windows smoke run (Dell XPS, interactive session, 2026-10-09)

`examples/BridgeSmoke` through a one-shot interactive scheduled task (`schedule-smoke.ps1`, deleted afterwards), driven by `drive-smoke.ps1` (real mouse click, UIA Invoke, virtual-key `a`). Final run output: **`SMOKE PASS (19/19)`**, exit 0.

- Wrap at two widths: 1050 px -> 2 lines (906.7x120), 500 px -> 3 lines (487.5x180) at scale 2.5; height = lines x line height; line breaks cover all 77 bytes; repeat measure hits the cache; 77 char cells.
- Fault injection: second release of a run handle, stale commit version (`SWR_E_STALE_VERSION`), forged window generation (`SWR_E_STALE_HANDLE`), commit after close (`SWR_E_SHUTDOWN`) all rejected with typed errors.
- AX Invoke on "Press me" arrived as one event tagged with the live window generation and snapshot; UIA `ValuePattern` of the edit node read `[a]` after the virtual-key `a` reached `ime_replace` (commit inside that callback counted as deferred).
- 471 ticks, max tick gap 22.3 ms (60 Hz display); **frames keep presenting while the window is not foreground**: 170 of 471 ticks and 172 of 473 paints happened with the window inactive.
- Drain: self-test refused the nested drain, 0 refusals in Swift and Rust, 489 drains, 0 thread violations, 0 host panics, `window_closed` once.
- Click-through finding (coordinator request): a first run showed the process was DPI-unaware (GPUI saw 640x480 at scale 1 inside a 1600x1200 stretched window, `WindowFromPoint` 2 px inside the client edge missed the window, pointer events landed in the wrong place). After `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` in `swr_run`: `WindowFromPoint` at 2 px inside the edge returns the window, `WM_NCHITTEST` = HTCLIENT, the real click arrives as a pointer event (smoke check "click 2px inside the client edge reached the window" passes). Styles logged: `WS_EX_NOREDIRECTIONBITMAP` set (GPUI's composition swap chain), not `LAYERED`/`TRANSPARENT`. The background was already `Opaque` by default; it is now set explicitly and a full rect is painted each frame.
- Known wrinkle: metrics read at `loop_ready` (client 1600x1396, scale 2.5) were taken before the window reached its final size; the first paint sends `SWR_EV_WINDOW_METRICS` with the real size and the smoke re-renders on it.
- Rust builds: 2 of 4 used (`rr-1791500259707-a963e83c6a6ff9e4` built first time; `rr-1791501276615-90b478882a1ad507` adds DPI awareness and Win32 initial metrics). The first Swift run crashed on an empty-text AX run (fixed in `makeAXTextRuns`) before any Rust change.

## Build and run

```sh
# Mac: Swift packages (type-checks the platform-neutral layer, header, marshalling)
cd packages/SwiftRightBridge && swift build
cd examples/BridgeSmoke && swift build        # runs as "unsupported platform" on macOS

# Rust (Windows host through RightKit; never --target-dir / CARGO_TARGET_DIR)
win "rightkit list"
cd render/swiftright-render && rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc
# then, once: sleep 840; rightkit remote status <id>

# Windows: stage and run (header symlink must be dereferenced when syncing)
rsync -aL --exclude .build packages/SwiftRightBridge/ <stage>/pkg/ ; scripts/sync-to-win.sh <stage>/pkg 'D:\Claude\sr0b-abi0\packages\SwiftRightBridge'
rsync -aL --exclude .build examples/BridgeSmoke/ <stage>/ex/      ; scripts/sync-to-win.sh <stage>/ex  'D:\Claude\sr0b-abi0\examples\BridgeSmoke'
# copy swiftright_render.dll from the receipt's target dir to D:\Claude\sr0b-abi0\payload\bin\
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-abi0\examples\BridgeSmoke\scripts\build-smoke.ps1'
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-abi0\examples\BridgeSmoke\scripts\schedule-smoke.ps1 -Tag run1'
```

The host executable needs the ComCtl v6 manifest link flags (`/MANIFEST:EMBED` + `/MANIFESTDEPENDENCY:...`, see `build-smoke.ps1`); without them `LoadLibraryW` fails with error 127 and the loader reports it.
