# swiftright-02 ready metrics (APPLIED; was a held patch)

Patch: `swiftright-02-ready-metrics.patch` (renderer + bridge; `git apply --check` passes against the repo; Swift files only syntax-parsed with `swiftc -parse`, never compiled or run).

Confirmed by a run (docs/sr0-findings.md section 12, `padding-settled-capture-v4/actual-single-r1/native-01/host.stdout.txt`): at ready the host read 800x1396 (client 800x600, scale 2.5); the first layout preceded any window-metrics event; the event carried 800x600; `metrics` still read 800x1396 afterwards.

## Half 1: renderer reports the pre-settle size at ready (cause established from source)

- `loop_ready(ctx, window)` carries no metrics (abi.rs:183); the host reads `swr_window_get_metrics` (lib.rs:172-192), which returns WIN_W/WIN_H/WIN_SCALE_BITS (rt.rs:173-175).
- Those are first written at view.rs:1315-1317 from one `GetClientRect` taken right after `open_window` with `show:false` (view.rs:1270-1280), and are not refreshed before `loop_ready` (view.rs:~1357). Only `paint_root` (view.rs:722-740) updates them later, and it is the only emitter of EV_WINDOW_METRICS. Which Win32/GPUI step makes that first sample stale is not established; the fix does not depend on it.
- Change (view.rs): `settle_client_metrics` re-reads `GetClientRect` and `GetDpiForWindow` just before `loop_ready` (`read_client_metrics`) and publishes them. Log lines print requested DIP, expected px, initial client, ready client.

## Half 2: `metrics` stays stale after the event

- The bridge does not cache. `BridgeWindow.metrics()` (Bridge.swift:401-406) calls `swr_window_get_metrics` on every read; the event is surfaced in `eventsAvailable` (Bridge.swift:~251-265) to `onEvent`/`eventStream` unchanged (decode at Marshal.swift:137-151). So source alone does not explain a getter that disagrees with a payload the same renderer just emitted: in paint_root the three atomics are stored before the event is queued (view.rs:731-743), and in the recorded case (width equal, height and nothing else different) the height swap does run. The run's tuple-11 renderer may differ from this source; the cause of the observed disagreement is NOT established.
- A real source defect of the same family, found while tracing: paint_root's condition `WIN_W.swap(..) != w || WIN_H.swap(..) != h || WIN_SCALE_BITS.swap(..) != bits` short-circuits, so a changed width leaves WIN_H and WIN_SCALE_BITS un-stored (the event carries the new height and scale, the getter keeps the old ones). This is a getter/event disagreement on any width change, though not the recorded one (that run changed height only).
- Changes:
  - Renderer (view.rs): one `publish_window_metrics(w, h, scale)` stores all three values (no short-circuit) and then pushes EV_WINDOW_METRICS carrying exactly the stored values. paint_root and `settle_client_metrics` both use it, so the getter and the event cannot disagree and the cache is updated at the moment the event is emitted. (This was missing in the old patch: its settle path stored then pushed, but paint_root kept the short-circuit.)
  - Bridge (new `MetricsLatch.swift`, Bridge.swift): `eventsAvailable` latches a `.windowMetrics` event's `i0`/`i1`/`x` on the live `BridgeWindow` before calling `onEvent`; `metrics()` returns the latched size and scale once an event was delivered (`active` still from the getter). Documented on `metrics()` and `MetricsLatch`.
  - Test: `MetricsLatchTests.swift` (4 headless XCTest cases, no DLL): stale getter 800x1396 vs event 800x600 at 2.5; later event replaces earlier; non-metrics events ignored; negative size and non-positive scale clamped.

## Contract

- `ready` reports the settled client size (physical px) and per-window scale (DPI / 96).
- A window-metrics event's payload is authoritative; from the moment the bridge delivers it, `BridgeWindow.metrics()` equals its size and scale, including inside `onEvent`.
- When the settled size differs from the early sample, the metrics event is queued before the ready callback runs (it accompanies ready; the host sees it on its next event drain, which may be after its first ready-time layout, which is why ready itself must already be correct).
- Caveat: paint_root recomputes from the GPUI viewport and may later publish a different value; any change publishes a new event and the latch follows it.

## Reopens

Renderer DLL hash; therefore the pin and every receipt bound to the renderer. Bridge package; therefore FreshOnBridge, BridgeSmoke, WorkloadWin, SliceApp exe, and both MSIX packages.

## Check owed (desktop, one run, Dell scale 2.5, request 320x240 DIP)

Log requested, `initial-client`, `ready-client`, `Bridge.metrics` at ready, the first window-metrics event, `Bridge.metrics` inside `onEvent`, and host `GetClientRect`: expect 800x600 throughout. Also run `swift test` for SwiftRightBridge and `cargo test` for the renderer (client_size tests).

UNBUILT. UNTESTED.

## Status (21 Oct): applied
The change is in the tree (see #49); the .patch file is kept as history only and must not be re-applied.
