# SR0-B GPUI drain probe: RESULT

Overall: **PASS on 5 of 5 desktop runs** for the stated criteria: all jobs, 0 thread mismatches, 0 re-entrancy, p99 at or under 16.7 ms, frames continue, clean exit. Caveats are listed below. Earlier batch (3 runs, `result-run1-3.txt`) had one run with p99 423 ms that the rerun did not reproduce.

## Design

- `swr_run` blocks on the calling (initial) thread and runs `Application::new().run`.
- A waiter thread blocks on Swift's main-queue wake HANDLE (`_dispatch_get_main_queue_handle_4CF`, an auto-reset event). It consumes each signal and calls `signal_notify()`. The waiter never touches gpui.
- `signal_notify()` wakes a `WaitSignal` future that the drain task awaits on GPUI's foreground executor. Waking it from a non-UI thread goes through gpui's own `dispatch_on_main_thread` (flume queue, then `PostMessageW(WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD)`). Sources: `src/platform/windows/dispatcher.rs`, `src/platform/windows/platform.rs` (`run_foreground_task`), `src/executor.rs`.
- The drain body runs from `run_foreground_task`, which holds no App or Window borrow. `loop_ready` is also called from this task, not from inside `on_finish_launching`.
- Non-reentrancy: a Rust `DRAINING` atomic guards the drain; Swift keeps its own flag. A self-test re-enters the guarded drain from inside a drain and confirms the refusal (`selftest_detected=1`), then removes that refusal from the violation count.
- Lost wakes: `WaitSignal` coalesces pending wakes, and each auto-reset consumption is followed by a drain. All 5000 jobs ran in every run.
- Window close: the close observer only sets flags and wakes the task. Swift's `window_closed` and `cx.quit()` run after the update returns.

## Findings

1. **ComCtl v6 manifest is required.** The Rust DLL imports `comctl32.dll!TaskDialogIndirect`, which the default v5 `comctl32` on PATH does not export. Without a manifest dependency the process fails to load with error 127 (`ERROR_PROC_NOT_FOUND`), before any Swift code runs. Fix used: link flags `/MANIFEST:EMBED` and `/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' ...`. Any SwiftRight host that loads the gpui DLL must embed this manifest.
2. **DXGI needs a desktop session, not SSH.** Launched through `win` (SSH, session 0), `open_window` fails with `DXGI_ERROR_NOT_CURRENTLY_AVAILABLE` (0x887A0022) while creating the DirectX renderer. The same binary runs from an interactive session. The first SSH attempt also exited `-1073741511` before any output, which was the import problem above.
3. **Frame rate is ~26 to 35 fps, not 60.** Each run rendered 130 to 177 frames in 5 s (`frames_during_workload`). Per-frame intervals were not recorded, so p50 and p95 frame intervals are **not available** from the existing counters.
4. **Focus was not measured.** The desktop runner sampled `FindWindowW(null, "SR0-B drain")` and `GetForegroundWindow()` every 250 ms. The title lookup found no window in any run (`window_visible=0`), even though frames rendered, so the title probably does not match gpui's window text on Windows. Foreground status is therefore **unknown**.
5. **Latency tails.** Every run had a max above 16.7 ms: 3.2, 664, 314, 17.0 and 17.6 ms. p99 stayed under 16.7 ms in all five runs, and the earlier 423 ms p99 did not recur. The Swift binary emits no per-sample timestamps, so the time of each slow sample is **not available**.

## Commands

- Rust: `rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc` in `swiftright-render-probe/`. Request `rr-1791487144505-6dba95e2d8f26ec7` SUCCEEDED, exit 0. The first submit returned REMOTE_HOST_UNREACHABLE. A replica slot ran the same build and the coordinator cancelled it.
- Payload: DLL to `payload/bin`, import lib renamed to `payload/lib/swiftright_render_probe.lib`, header to `payload/include`.
- Swift: `swift build -c release --scratch-path D:\Claude\sr0b-gpui-drain\scratch-1 -Xcc -I<payload>\include -Xlinker -L<payload>\lib -Xlinker /MANIFEST:EMBED -Xlinker /MANIFESTDEPENDENCY:"..."`. Build complete.
- Run: `scripts/run-desktop.ps1` through a one-shot interactive scheduled task (`SR0B-DrainRun`, user adrds). Task deleted after the rerun.

## Five-run rerun (desktop, verbatim `result.txt`, binary unchanged)

```
host=BOGUS-DELL user=adrds session=1 started=2026-10-09T01:22:35.2715719+05:30
exe=D:\Claude\sr0b-gpui-drain\scratch-1\out\Products\Release-windows-x86_64\SwiftHost.exe exists=True
=== RUN 1 start=2026-10-09T01:22:35.3239321+05:30
focus_samples: total=21 window_visible=0 window_foreground=0
focus_first_visible: 
focus_last_visible: 
[sr0-b rust] loop_ready_calls=1 drain_calls=4993 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=5499 wake_wait_failures=0 frames_rendered=177 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
initial_thread_id=32364
bootstrap_query_rc=0 abi=0.1 pointer_width=64 fn_table_size=6
main_queue_wake_handle=Optional(0x0000000000000280)
producer enqueue_rate_hz=1000.198359338624 hops_enqueued=500
jobs_run=5000/5000
latency_ms p50=0.0585 p95=0.2276 p99=0.7201 max=3.1760
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=4992 selftest_swift_result=1
mainactor_hops=500/500
frames_during_workload=176 workload_s=5.000 frames_at_start=1 frames_at_end=177
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=PASS


exit=0 end=2026-10-09T01:22:47.9174332+05:30
=== RUN 2 start=2026-10-09T01:22:47.9174332+05:30
focus_samples: total=2 window_visible=0 window_foreground=0
focus_first_visible: 
focus_last_visible: 
[sr0-b rust] loop_ready_calls=1 drain_calls=3468 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=3888 wake_wait_failures=0 frames_rendered=132 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
initial_thread_id=21632
bootstrap_query_rc=0 abi=0.1 pointer_width=64 fn_table_size=6
main_queue_wake_handle=Optional(0x0000000000000284)
producer enqueue_rate_hz=999.8746157231884 hops_enqueued=500
jobs_run=5000/5000
latency_ms p50=0.0722 p95=1.0740 p99=1.2242 max=664.1759
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=3467 selftest_swift_result=1
mainactor_hops=500/500
frames_during_workload=131 workload_s=5.000 frames_at_start=1 frames_at_end=132
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=PASS


exit=0 end=2026-10-09T01:23:02.0905511+05:30
=== RUN 3 start=2026-10-09T01:23:02.0905511+05:30
focus_samples: total=21 window_visible=0 window_foreground=0
focus_first_visible: 
focus_last_visible: 
[sr0-b rust] loop_ready_calls=1 drain_calls=2873 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=3524 wake_wait_failures=0 frames_rendered=130 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
initial_thread_id=12932
bootstrap_query_rc=0 abi=0.1 pointer_width=64 fn_table_size=6
main_queue_wake_handle=Optional(0x000000000000028c)
producer enqueue_rate_hz=1000.196038423531 hops_enqueued=500
jobs_run=5000/5000
latency_ms p50=0.1092 p95=4.9365 p99=12.1921 max=314.2565
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=2872 selftest_swift_result=1
mainactor_hops=500/500
frames_during_workload=129 workload_s=5.000 frames_at_start=1 frames_at_end=130
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=PASS


exit=0 end=2026-10-09T01:23:08.0330244+05:30
=== RUN 4 start=2026-10-09T01:23:08.0330244+05:30
focus_samples: total=22 window_visible=0 window_foreground=0
focus_first_visible: 
focus_last_visible: 
[sr0-b rust] loop_ready_calls=1 drain_calls=4502 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=5103 wake_wait_failures=0 frames_rendered=170 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
initial_thread_id=11448
bootstrap_query_rc=0 abi=0.1 pointer_width=64 fn_table_size=6
main_queue_wake_handle=Optional(0x0000000000000280)
producer enqueue_rate_hz=1000.0142402027805 hops_enqueued=500
jobs_run=5000/5000
latency_ms p50=0.0697 p95=0.4486 p99=1.1619 max=17.0147
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=4501 selftest_swift_result=1
mainactor_hops=500/500
frames_during_workload=169 workload_s=5.002 frames_at_start=1 frames_at_end=170
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=PASS


exit=0 end=2026-10-09T01:23:13.8981503+05:30
=== RUN 5 start=2026-10-09T01:23:13.8981503+05:30
focus_samples: total=22 window_visible=0 window_foreground=0
focus_first_visible: 
focus_last_visible: 
[sr0-b rust] loop_ready_calls=1 drain_calls=4326 drain_reentry_violations=0 thread_violations=0 selftest_detected=1 wake_signals=5007 wake_wait_failures=0 frames_rendered=168 window_closed_events=1 quit_requests=1 open_failed=false run_rc=0
initial_thread_id=11652
bootstrap_query_rc=0 abi=0.1 pointer_width=64 fn_table_size=6
main_queue_wake_handle=Optional(0x0000000000000280)
producer enqueue_rate_hz=1000.0159202534505 hops_enqueued=500
jobs_run=5000/5000
latency_ms p50=0.0662 p95=0.7942 p99=4.8625 max=17.6164
thread_mismatches=0 (jobs=0 hops=0 drain=0 loop_ready=0)
reentrancy_violations_swift=0 drain_calls_swift=4325 selftest_swift_result=1
mainactor_hops=500/500
frames_during_workload=167 workload_s=4.999 frames_at_start=1 frames_at_end=168
loop_ready_calls=1 window_closed_calls=1 watchdog_fired=false
swr_set_wake_handle_rc=0 swr_run_rc=0 main_thread_after_run_same=true
verdict=PASS


exit=0 end=2026-10-09T01:23:19.6190166+05:30
finished=2026-10-09T01:23:19.6190166+05:30
```

## Criteria (5-run rerun)

| Criterion | Runs 1-5 |
|---|---|
| All jobs 5000/5000 | PASS (5/5) |
| Thread mismatches 0 | PASS (5/5) |
| Re-entrancy 0 | PASS (5/5) |
| p99 <= 16.7 ms | PASS (p99 0.72, 1.22, 12.19, 1.16, 4.86 ms) |
| Frames continue | PASS (130 to 177 frames per run) |
| Clean exit | PASS (run_rc=0, exit 0) |
| Probe window foreground | UNKNOWN (title lookup failed) |
| Frame interval p50/p95 | NOT AVAILABLE |

## Open items

- Fix the window lookup for focus measurement (title or class match) before claiming foreground behavior.
- Per-sample timestamps and per-frame intervals need a Swift/Rust counter change, which means a new build.
- Single host, one Swift 6.4.0 toolchain, private `_4CF` SPI. Not a stable public contract.
- Probe-only ABI 0.1, not frozen. Nothing committed.

## Primary verification & open items (2026-10-09)

Primary re-read `D:\Claude\sr0b-gpui-drain\result.txt` on the host: five runs PASS, p99 0.72 / 1.22 / 12.19 / 1.16 / 4.86 ms; scheduled task removed. Runs 2-3 overlapped interactive desktop activity (Windows restart sign-in and IME probe launch at ~01:23), which may explain their 314-664 ms maxima; unproven.

Open for SR0-B before ABI v0 freeze:
- Worst-case stalls: add per-sample timestamps and correlate >16.7 ms samples with GPUI frame and window-message activity under an idle desktop.
- Frame clock: 26-35 fps observed from a 16 ms GPUI timer. Architecture §11 requires presentation interval p95 ≤ 16.7 ms; replace the timer with on-demand display ticks and measure real presented-frame intervals.
- Window title lookup failed; foreground state unmeasured.
- Hosts loading the renderer DLL must embed the ComCtl v6 manifest dependency; renderer windows require an interactive desktop session (DXGI unavailable in session 0).
