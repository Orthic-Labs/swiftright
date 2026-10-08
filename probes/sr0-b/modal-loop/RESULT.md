# SR0-B modal-loop probe: RESULT

**Overall: FAIL.** Drain, job, AccessKit-queue and shutdown criteria pass. Live resize and the modal TaskDialog both fail, so the modal-loop criteria are not proven. No build 4 was spent, per the coordinator's instruction.

Host: Windows x64, Swift 6.4.0, Rust 1.98.0 (msvc), accesskit 0.25.1, accesskit_windows 0.35.1, gpui 0.2.2. Interactive desktop run via one-shot scheduled tasks (`SR0B-Modal-run1`, `SR0B-Modal-run2`, both deleted and verified absent).

## Design (what the probe does)

- `swr_run` blocks on the initial thread. Swift's main queue is drained from a GPUI foreground task via `_dispatch_main_queue_callback_4CF`, as in gpui-drain.
- Every host callback (loop_ready, drain, tick, window_closed) goes through `host_call`, a non-reentrant guard. A callback that arrives during another is deferred and counted, then run after the active one unwinds.
- AccessKit: one `SubclassingAdapter` (window created `show: false`, adapter created before `activate_window`). The 3-node tree is Window, Button "Probe action" (Click, Focus), Label. The ActionHandler only validates, pushes a record into a 256-entry bounded queue under the same lock that closes the queue, and `SetEvent`s the Swift wake handle. It never calls Swift or GPUI.
- Modal request: `swr_request_modal(1)` queues the request and wakes the drain task. The drain task spawns a separate foreground task, so the modal loop does not run inside the drain poll. TrackPopupMenu (kind 2) is declared in the ABI but returns `SWR_ERR_ARGS`.
- Phase tracking: our own `SetWindowSubclass` on the HWND (outermost) sets flags on WM_ENTERSIZEMOVE / WM_EXITSIZEMOVE and counts WM_NCLBUTTONDOWN.
- GPUI source refs (checked in `gpui-0.2.2/src/platform/windows/`):
  - `events.rs`: `WM_ENTERSIZEMOVE` starts a `SIZE_MOVE_LOOP_TIMER_ID` timer (`handle_size_move_loop`), and `handle_timer_msg` runs `main_receiver.drain()` during the size loop.
  - `dispatcher.rs` `dispatch_on_main_thread`: posts `WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD` to the platform window, so wakes reach the window proc inside modal loops.
  - `platform.rs` `run_foreground_task`: drains the main receiver.
  - `events.rs` `handle_hit_test_msg`: uses the default (OS) hit test unless `hide_title_bar` is set; this probe does not set it.

## Commands

- Rust build (×3 submitted; iteration 4 not used):
  - Iter 1 `rr-1791495190500-2582a086a1ffc14e`: FAILED, E0502 borrow of `q.live_gen` inside `q.buf.push_back` (`lib.rs:402`).
  - Iter 2 `rr-1791495846151-ecc24cabc89b0952`: SUCCEEDED (broker `c811078f`).
  - Iter 3 `rr-1791496910411-86026d35051a8e3b` (broker `b9df7a20`): SUCCEEDED, adds diagnostics. This is the binary used for the final run.
- Swift: `scripts/build-swift.ps1` (ComCtl v6 manifest dependency passed correctly). An earlier attempt mis-quoted the manifest dependency and produced an SxS startup error; that was a quoting bug in my command, not a probe defect.
- Run: `scripts/schedule-modal.ps1 -Tag run1` (iter 2 binary) and `-Tag run2` (iter 3 binary). Each registers a one-shot interactive task, runs `scripts/run-modal.ps1`, then deletes the task.

## Verbatim trimmed output, run2 (iter 3 binary)

```
window_hwnd=7998526 found_after_polls=3 exited_early=False
resize_start rect=(908,583,2548,1581) grip=(2544,1577)
pre_drag cursor=(2544,1577) window_at_grip_is_target=True foreground_is_target=True sizeof_input=40
send_down_ret=1 lasterr=203
send_up_ret=1
move_sendinput_ok=200 of 200
resize_done drag_s=4.78 rect_after=(908,583,2548,1581)
uia_first_err_idx=1502 first_err_ms=25307
uia_invoke n=2000 ok=1502 err=498 notfound=0 close_sent_at_ms=25316 first_err='Exception calling "Invoke" with "0" argument(s): "Unrecognized error."' total_ms=34273 first_invoke_ms=10
stdout:
[sr0-b rust] drain_calls=12689 tick_calls=1172 deferred_total=1 nested_executed=0 drains_idle=12690 drains_sizing=0 drains_modal=0 drains_both=0 selftest_detected=1 panics=0 wake_signals=13498 wake_wait_failures=0 frames_rendered=1184 size_enter=0 size_exit=0 modal_requests=1 modal_opened=1 modal_results=1 modal_errors=1 run_rc=0
jobs_run=10000/10000 enqueued_before_close=10000 run_by_final_flush=10000 enqueued_after_close_refused=0 late_dropped=0
latency_ms all p99=0.5080 max=23.3097 n=10000
latency_ms during_live_resize p50=-1.0000 p99=-1.0000 max=-1.0000 n=0
latency_ms during_modal p50=-1.0000 p99=-1.0000 max=-1.0000 n=0
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
swift_drain_calls=12690 swift_reentry_violations=0 selftest_swift_result=1 ticks=1172
nc_lbuttondown=0 nc_last_hittest_code=0
size_loop_enter=0 size_loop_exit=0 frames_during_workload=1182 frames_at_start=2 frames_at_end=1184
modal_request_rc=0 modal_requests=1 modal_opened=1 modal_results=1 modal_errors=1 modal_result_values=[-2147024809]
ax_attempts=3004 enqueued=3004 full=0 rejected_stale_at_post=0
ax_popped_applied=3004 popped_stale=0 queue_len_end=0 swift_applied=1502 swift_unsupported=1502 swift_applied_after_close=0 rust_applied_after_close=0 model_clicks=1502
sum_attempts_ok=true sum_enqueued_ok=true swift_matches_rust=true
window_closed_calls=1 close_flush_ok=true watchdog_fired=false wake_signals=13498 wake_wait_failures=0
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=FAIL
stderr: [sr0-b rust] TaskDialogIndirect hr=0x80070057
```

Run 1 (iter 2 binary, `SR0B-Modal-run1`) showed the same pattern: `size_enter=0`, rect unchanged, `modal_result_values=[-1]` (the old code did not log the HRESULT), `uia` ok 712 / err 1288 with the error run starting after close.

## PASS / FAIL table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Build succeeds (iter 3) | PASS | rr-...86026d35051a8e3b, terminal exit 0 |
| 2 | All 10,000 async jobs run, zero thread mismatches | PASS | jobs_run=10000/10000, mismatches=0 |
| 3 | Job p99 at or under 16.7 ms (idle) | PASS | p99 0.508 ms (all phases; no jobs tagged resize/modal) |
| 4 | Drains during live resize > 0 | **FAIL** | drains_sizing=0, size_enter=0 |
| 5 | Job p99 during resize / modal | **NOT MEASURED** | n=0 in both phases |
| 6 | Modal TaskDialog opens and returns | **FAIL** | HRESULT 0x80070057 (E_INVALIDARG); modal_results=-2147024809 |
| 7 | Zero nested drains (Swift and Rust) | PASS | swift reentry 0; nested_executed 0 |
| 8 | Deferred re-entrant callbacks counted | PASS (>=0) | deferred_total=1 (the self-test) |
| 9 | Zero borrow / panics | PASS | panics=0 |
| 10 | AX sums consistent | PASS | attempts 3004 = enqueued 3004 + rejected 0 + full 0; enqueued = applied 3004 + stale 0; queue empty |
| 11 | No AX apply after close | PASS | swift_applied_after_close=0, rust_applied_after_close=0 |
| 12 | Stale-after-close rejection exercised | **NOT EXERCISED** | rejected_stale_at_post=0 and popped_stale=0; UIA calls failed before reaching the adapter after close |
| 13 | UIA 2,000 Invokes while closing | PARTIAL | 1502 ok before close; 498 failed, first failure at call 1502, 9 ms after WM_CLOSE posted |
| 14 | Clean shutdown (window_closed once, rc 0, same thread) | PASS | window_closed_calls=1, swr_run_rc=0, close_flush_ok |
| 15 | Live resize via SendInput on border | **FAIL** | SendInput down/up returned 1, moves 200/200, grip is target and foreground; WM_NCLBUTTONDOWN count 0 and rect unchanged |

## Root cause evidence (not proven, no build 4 spent)

- **Resize (criteria 4, 15).** SendInput delivery succeeded and the target window was under the grip and in the foreground, yet no WM_NCLBUTTONDOWN reached the window subclass. Since the hit-test path never ran, neither the SizeMove loop nor the modal phase was entered. Candidate causes, unverified: the synthetic down is not landing in the non-client area (the 4 px inset may fall in client area under this DPI/frame), or GPUI's frame does not produce a sizing border here. Next diagnostic would log WM_NCHITTEST results at the grip point and try an inset of 1 to 2 px.
- **TaskDialog (criterion 6).** `TaskDialogIndirect` returned E_INVALIDARG. Candidate causes, unverified: the hand-written `TaskDialogConfig` layout (I matched x64 offsets by hand, cbSize 176) or a flag/field the v6 API rejects. Next diagnostic would compare with the SDK header layout or try a minimal config with no callback.
- **UIA errors (criterion 13)** are consistent with the window being destroyed mid-stream and are the expected close behaviour, not an independent defect.

## Not done

- Live-resize drains and job p99 during resize (4, 5). Blocked by criterion 15.
- Modal drains and job p99 during modal (6). Blocked by the HRESULT.
- Stale-after-close rejection (12) needs an AX action to reach the adapter after close. A direct probe path would be needed.
- Nothing has been committed or pushed; the probe sits in `probes/sr0-b/modal-loop/`.

---

## 2026-10-09 take-over: TaskDialog and live-resize fixes (runs run3, run4, run5)

**Overall: PARTIAL.** TaskDialog now opens and returns IDOK; the size/move modal loop is entered, the window rect changes, and drains and jobs continue through both loops. Remaining FAIL: job p99 during the modal TaskDialog is 31.1 ms (budget 16.7 ms), and real-mouse border drag still produces no WM_NCLBUTTONDOWN. Two Rust builds spent this session: `rr-1791497815583-49bcff325ce259d3` (packed(1) fix) and `rr-1791498872459-36629d6b6f95ecfb` (adds window-message event log); both SUCCEEDED. Swift rebuilt with `scripts/build-swift.ps1` (ComCtl v6 manifest flags kept).

### Root causes and fixes

1. **TaskDialogIndirect E_INVALIDARG (0x80070057).** commctrl.h declares TASKDIALOGCONFIG and TASKDIALOG_BUTTON under `#include <pshpack1.h>`. The windows crate in Cargo.lock mirrors that: `windows-0.61.3/src/Windows/Win32/UI/Controls/mod.rs:9113` `#[repr(C, packed(1))] pub struct TASKDIALOGCONFIG` (and `:9177` TASKDIALOG_BUTTON, and the two anonymous unions at `:9148`). The hand-written struct used natural alignment (hwndParent at offset 8 instead of 4), so cbSize and every later field were wrong. Fix: `#[repr(C, packed(1))]` on `TaskDialogConfig` in `src/lib.rs` (kept hand-written to avoid a new dependency and Cargo.lock change; field order and types are identical to the crate's definition). The ComCtl v6 manifest dependency was in effect (dialog created and returned 1; with a v5 comctl32 the export is missing, not E_INVALIDARG). Result: `modal_errors=0 modal_result_values=[1]`.
2. **Live resize never entered the size loop.** GPUI 0.2.2 source (docs.rs `platform/windows/window.rs`, `events.rs`): window style is `WS_SYSMENU | WS_THICKFRAME | WS_MAXIMIZEBOX` (no WS_CAPTION), `hide_title_bar` comes from `titlebar.appears_transparent` (false here), and `handle_hit_test_msg` returns `None` (OS default hit test) when `!hide_title_bar`; `WM_NCCALCSIZE` is also default. So GPUI does not draw its own frame here and does not interfere with sizing. Logged `WM_NCHITTEST` via SendMessageTimeout at the corner: inset 1 and 2 px give HTNOWHERE (0), insets 4 to 16 px give HTBOTTOMRIGHT (17), 24 px gives HTCLIENT. So the earlier 4 px inset was a valid grip. In run4 and run5 a SendInput left-button-down at the HTBOTTOMRIGHT point (cursor verified at the grip, window under cursor is target and foreground, WM_NCHITTEST reaches the window and returns 0x11 at the moment of the click) still produced no WM_NCLBUTTONDOWN, no WM_SYSCOMMAND and no WM_ENTERSIZEMOVE. Cause of the dropped synthetic click is not determined (not GPUI: GPUI never saw a nonclient button message to reject). Run3 was invalid: absolute-coordinate SendInput mapped the cursor to the wrong point on this 3456x2160 multi-DPI display (cursor landed at 3004,1069 instead of 2544,1577); replaced with SetCursorPos for positioning.
   **Method used (documented): deterministic SC_SIZE.** `PostMessage(hwnd, WM_SYSCOMMAND, SC_SIZE | WMSZ_BOTTOMRIGHT = 0xF008, 0)`, then 80 mouse moves (SetCursorPos plus a 1 px relative SendInput so a real WM_MOUSEMOVE is generated), then Enter (keybd_event VK_RETURN) to end the loop. A click did not end the loop in run3. PostMessage, not SendMessage, because SendMessage would block the runner inside the target's loop. Method A (real border drag) is still attempted first and its failure logged; the runner falls back to B when the rect is unchanged.
3. **Schedule.** Swift now requests the TaskDialog at job 8,000 (was 6,000) so the resize loop (about 1.8 to 7.6 s of process time) and the modal phase do not overlap; `drains_both=0` in run5. In run3 they overlapped (`drains_both=983`) because the loop was still open when the dialog appeared.
4. **Foreground.** `SetForegroundWindow(hwnd)` now also called inside the probe right after `activate_window()`.
5. **Diagnostics.** `observe_proc` logs (bounded to 300 lines, stderr) ENTER/EXITSIZEMOVE, SYSCOMMAND, SIZING, SIZE, WINDOWPOSCHANGED, CAPTURECHANGED, NCLBUTTONDOWN, and the first NCHITTEST edge results.

### Verbatim trimmed output, run5 (final binaries, `SR0B-Modal-run5`, task deleted, verified absent)

```
nchittest_corner inset-3=0 inset1=0 inset2=0 inset4=17 inset6=17 inset8=17 inset12=17 inset16=17 inset24=1
resize_start rect=(908,583,2548,1581) grip=(2544,1577) inset=4 hit_at_grip=17
pre_drag cursor=(2544,1577) window_at_grip_is_target=True foreground_is_target=True
method_A_sendinput_border_drag down=1 moves_ok=80/80 up=1 rect_after=(908,583,2548,1581) rect_changed=False
method_B_sc_size post_ok=True moves_ok=80/80 end_enter=1/1 rect_after=(908,583,2788,1741) rect_changed=True
[sr0-b rust] drain_calls=12639 tick_calls=1190 deferred_total=1 nested_executed=0 drains_idle=8955 drains_sizing=2694 drains_modal=991 drains_both=0 selftest_detected=1 panics=0 ... size_enter=1 size_exit=1 modal_requests=1 modal_opened=1 modal_results=1 modal_errors=0 run_rc=0
jobs_run=10000/10000 ... late_dropped=0
latency_ms all p99=0.9389 max=41.1207 n=10000
latency_ms idle p99=0.6627 n=6259
latency_ms during_live_resize p50=0.0662 p99=0.4795 max=2.2464 n=2695
latency_ms during_modal p50=0.0710 p99=31.1238 max=41.1207 n=1046
thread_mismatches=0 ; swift_reentry_violations=0 ; nested_executed=0 ; mainactor_hops=500/500
nc_lbuttondown=0 size_loop_enter=1 size_loop_exit=1 frames_during_workload=1190
modal_request_rc=0 modal_requests=1 modal_opened=1 modal_results=1 modal_errors=0 modal_result_values=[1]
verdict=FAIL   (modal p99 over budget; AX/UIA close-race criteria unchanged)
event log: SYSCOMMAND 0xf008 @4891ms, ENTERSIZEMOVE @4892ms, SIZING edge 8 every ~33 ms until 7552ms, CAPTURECHANGED @7588, WINDOWPOSCHANGED 752x463 client (was 640x360) @7589, EXITSIZEMOVE @7595ms
```

Run4 (earlier binary, no event log) had the same pattern with an unrelated 0.47 s loop: resize p99 0.315 ms (n=470), modal p99 41.8 ms (n=1052).

### Updated PASS / FAIL table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Build succeeds | PASS | rr-...49bcff325ce259d3 and rr-...36629d6b6f95ecfb, exit 0 |
| 2 | 10,000 jobs run, zero thread mismatches | PASS | 10000/10000, mismatches 0 |
| 3 | Job p99 idle at or under 16.7 ms | PASS | 0.663 ms |
| 4 | Drains during live resize > 0 | **PASS** | drains_sizing=2694, size_enter=1, size_exit=1 (via SC_SIZE) |
| 5a | Job p99 'resize' at or under 16.7 ms | **PASS** | 0.4795 ms (n=2695, max 2.25 ms) |
| 5b | Job p99 'modal' at or under 16.7 ms | **FAIL** | 31.12 ms (n=1046, max 41.1 ms); 41.8 ms in run4. Only about 10 jobs exceed the budget, consistent with a stall of up to about 40 ms while TaskDialogIndirect builds and shows the dialog on the UI thread (cause not isolated; no per-message timing taken). Drains during the dialog itself keep running (drains_modal=991) |
| 6 | Modal TaskDialog opens and returns | **PASS** | result 1 (IDOK), modal_errors=0 |
| 7 | Zero nested drains | PASS | 0 / 0 |
| 8 | Deferred re-entrant callbacks counted | PASS | deferred_total=1 |
| 9 | Zero panics | PASS | 0 |
| 10 | AX sums consistent | PASS | unchanged from run2 pattern (sum_*_ok=true) |
| 11 | No AX apply after close | PASS | 0 / 0 |
| 12 | Stale-after-close rejection exercised | NOT EXERCISED | unchanged (UIA fails at close before reaching the adapter) |
| 13 | UIA 2,000 Invokes while closing | PARTIAL | 1501 ok, 499 err after WM_CLOSE |
| 14 | Clean shutdown | PASS | window_closed_calls=1, run_rc=0 |
| 15 | Live resize by real SendInput border drag | **FAIL** | hit test is HTBOTTOMRIGHT at the grip, but the injected button-down never became WM_NCLBUTTONDOWN (cause undetermined) |
| 15b | Size loop entered deterministically, rect changes | **PASS** | SC_SIZE|WMSZ_BOTTOMRIGHT: ENTERSIZEMOVE observed, rect 1640x998 to 1880x1158, EXITSIZEMOVE observed |

Not done: isolating the real-mouse nonclient click drop (candidates: injected input needs a real mouse-move before down, or the scheduled-task session's input path; try `mouse_event` and a delay after SetCursorPos); isolating the 40 ms dialog-creation stall (candidate mitigation: pre-load comctl or show the dialog from a worker-created window); stale-after-close needs a direct adapter path. Nothing committed or pushed.

## Primary disposition (2026-10-09)

- Modal-loop progress is proven: drains continue inside the system size/move loop (`drains_sizing=2694`, resize-tagged job p99 0.48 ms) and inside the TaskDialog modal loop (`drains_modal=991`), with no nested drains.
- The modal-tagged p99 of 31.1 ms comes from ~10 jobs queued while `TaskDialogIndirect` builds its window on the UI thread (≈40 ms). The SR0 slice fixtures contain no dialogs, so this does not gate SR0; it becomes an SR1 budget item for dialog/menu inventory (candidate mitigation: open dialogs only after a drain and accept a bounded one-off open cost, or measure against an AppKit sheet baseline).
- Real-mouse border drag through `SendInput` never produced `WM_NCLBUTTONDOWN` although `WM_NCHITTEST` returns `HTBOTTOMRIGHT`; the size loop was entered via `SC_SIZE`. A physical/desktop-session drag still needs to confirm the same behaviour.
