# swiftright-render

Rust cdylib `swiftright_render.dll` (GPUI =0.2.2, AccessKit, Windows x64 only; the crate is `cfg(windows)`). ABI and revision notes: `render/README-abi-v0.md`, header `render/swiftright-abi/include/swiftright.h`.

## Build and test (RightKit only)

From this directory, on the Mac, through the managed Windows host (never `--target-dir` / `CARGO_TARGET_DIR`):

```sh
rightkit list                                                                  # one managed root build per host
rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc
rightkit remote windows cargo test  --release --target x86_64-pc-windows-msvc  # unit tests (tree.rs)
rightkit remote status <request-id>                                            # never re-submit after a disconnect
```

## Diagnostic toggles (environment, read once at window launch)

| Variable | Effect |
|---|---|
| `SWR_MODAL_LEGACY_SPAWN=1` | Start a modal (`SWR_MODAL_MENU` / `SWR_MODAL_DIALOG` / message) the old way, as a GPUI foreground runnable (`cx.spawn(run_modal)`), instead of the default posted `WM_SWR_MODAL`. Only for the A/B proof of the modal stall below; never set it in a product. |

Other diagnostics: `SWR_AX_OFF`, `SWR_AX_MIN_MS`, `SWR_FRAME_LOG`, `SWR_MEM_DEEP` (see `src/view.rs`, `src/trace.rs`).

## Modal start path and the Modal06 stall

A modal (`TrackPopupMenu`, `TaskDialogIndirect`, `MessageBoxW`) blocks in the OS modal loop. It used to be started from the drain task with `cx.spawn(run_modal)`, i.e. as a GPUI foreground runnable. GPUI 0.2.2 runs the foreground queue in snapshots (`run_foreground_task`: `main_receiver.drain()` takes the whole flume queue), so the modal ran inside a snapshot. If the drain task's wake runnable had been queued behind the modal runnable in that same snapshot, it could not run until the modal returned, and `signal_notify` had already taken the drain task's waker (`s.waker.take()`), so every later host wake only incremented `pending` and posted nothing: the Swift main queue stopped draining for the whole modal (2/20 Modal06 runs, `ticks_during=0`, latency = modal duration).

The default start is now a `WM_SWR_MODAL` posted by the drain task to the main window and handled in the window subclass (`ime_subclass_proc`) at the thread's top-level `DispatchMessage`, outside every foreground snapshot. Wake runnables posted during the modal are then dispatched by the modal's own message pump as before.

Each modal logs one stderr line: `[swiftright-render] modal id=<id> kind=<menu|dialog|message> path=<posted|spawn> waker_none=<bool> queued_ms=<n> elapsed_ms=<n> wakes_during=<n> drain_calls_during=<n> i0=<n> i1=<n>`. `waker_none` is the drain task's waker slot at modal entry; `wakes_during` / `drain_calls_during` are the host wake and host drain counter deltas across the modal. `drain_calls_during=0` with `wakes_during>0` is the stall. `waker_none=true` alone is not (a wake runnable that is already in the foreground queue still runs from the nested pump).

## ABI 0.8 text extension (minimal form)

`swiftright.h` "REVISION 0.8" and decisions G60-G69 in `docs/sr1-decisions.md`. Sources: `src/faces.rs` (pure face policy: named-instance mapping, simulation clamp, sfnt metrics), `src/dwr.rs` (DirectWrite face resolver: real faces, identity, axes; no shaping), `src/text.rs` (`build_font`, tracking in cells), `src/view.rs` (`paint_tracked`: `Window::paint_glyph` at adjusted positions), `src/lib.rs` (`swr_*_v08` exports, `swr_text_run_faces`, `swr_font_face_metrics`, `swr_system_font_info`). gpui still shapes and paints; there is no own DirectWrite run pipeline (that is block F3b). Build and test only through `.github/workflows/render-windows.yml` (CI); the 0.8 DLL is staged under a new name, never over the pinned 0.7 DLL.
