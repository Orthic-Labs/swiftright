# SR0-D dispatch-drain probe: RESULT

Question: can Swift's main dispatch queue on Windows x64 be driven non-recursively from a host-owned Win32 message loop using libdispatch's private `_4CF` symbols, and what is enqueue-to-execution latency?

Verdict: **PASS** on all criteria, 3 of 3 runs. No GPUI or Rust is involved.

## 1. Exports found (dispatch.dll, Swift 6.4.0 runtime)

`dumpbin /exports` on `C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin\dispatch.dll`, filtered for `4CF|main_queue|runloop|port|handle`:

```
16    F 00012220 _dispatch_get_main_queue_handle_4CF
17   10 00012220 _dispatch_get_main_queue_port_4CF
23   16 00012260 _dispatch_main_queue_callback_4CF
27   1A 00011BC0 _dispatch_runloop_root_queue_create_4CF
28   1B 000121F0 _dispatch_runloop_root_queue_get_port_4CF
29   1C 00011E90 _dispatch_runloop_root_queue_perform_4CF
30   1D 00012150 _dispatch_runloop_root_queue_wakeup_4CF
```

The tool used was `dumpbin.exe` from `C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\dumpbin.exe`.

## 2. Signatures used

Source: `swift-corelibs-libdispatch` `main`, `private/private.h` lines 204-215, and `src/queue.c`.

```c
void *_dispatch_get_main_queue_handle_4CF(void);   // queue.c: returns dispatch_runloop_handle_t
void *_dispatch_get_main_queue_port_4CF(void);     // queue.c: forwards to the handle getter
void  _dispatch_main_queue_callback_4CF(void *msg); // queue.c: drains _dispatch_main_q; msg ignored
```

Notes from the source:
- On `_WIN32`, `dispatch_runloop_handle_t` is `void *`. `_dispatch_runloop_queue_handle_init` creates it with `CreateEventW(NULL, FALSE, FALSE, NULL)`, an auto-reset event. That event is what the main queue pokes on enqueue, so it is the handle to wait on.
- `_dispatch_main_queue_callback_4CF` crashes unless the main queue is thread-bound and the caller holds its drain lock. It returns early if `dq_side_suspend_cnt` is already set, which is libdispatch's own reentrancy guard. Our own non-reentrant flag is still required.
- The probe uses `_dispatch_get_main_queue_handle_4CF`, not the `_port_` alias. The two share an address in dispatch.dll.

## 3. Probe layout

`probes/sr0-d/dispatch-drain/DrainProbe/`
- `Package.swift`: swift-tools 5.9, targets `CDispatchPrivate` (C) and `DrainProbe` (executable).
- `Sources/CDispatchPrivate/include/CDispatchPrivate.h`: the three prototypes above.
- `Sources/CDispatchPrivate/shim.c`: includes the header.
- `Sources/DrainProbe/main.swift`: synchronous top-level entry, no async main.

Behavior:
1. Creates a message-only window (`CreateWindowExW` with class `STATIC`, parent `HWND_MESSAGE`) on the initial thread, and records that thread's id.
2. Gets the wake handle with `_dispatch_get_main_queue_handle_4CF`.
3. Host loop: `MsgWaitForMultipleObjectsEx(1, &handle, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE)`. On the handle, it calls `_dispatch_main_queue_callback_4CF(nil)` through a non-reentrant guard. Otherwise it pumps `PeekMessageW`/`TranslateMessage`/`DispatchMessageW`.
4. Workload from a background `Thread`:
   - 10,000 `DispatchQueue.main.async` jobs paced at 1 kHz, each timestamped with QPC.
   - Job 5000 enqueues a nested `DispatchQueue.main.async`.
   - A `Task { @MainActor }` chain of 1,000 hops, each hop bouncing through `DispatchQueue.global()` via a checked continuation.
5. Idle window of 5 s with no enqueued work. Counts loop iterations that executed no work.
6. Exit by `PostQuitMessage(0)` from a main-queue job, after which the loop sees `WM_QUIT`.
7. A guard self-test, reported separately: forces one re-entrant drain call and checks that it is counted and skipped.

## 4. Exact commands

```
win "<dumpbin /exports dispatch.dll | Select-String '4CF|main_queue|runloop|port|handle'>"
scripts/sync-to-win.sh probes/sr0-d/dispatch-drain/DrainProbe 'D:\Claude\sr0d-dispatch'
win "<set Path per Swift quirk>; cd D:\Claude\sr0d-dispatch; swift build -c release"
win "<set Path per Swift quirk>; cd D:\Claude\sr0d-dispatch; .\.build\out\Products\Release-windows-x86_64\DrainProbe.exe"   # run 3 times
```

Build fix iterations: 1 of 4 used. The first build failed on two type errors, both fixed in `main.swift`:
- `HWND_MESSAGE` must be `HWND(bitPattern: -3)`, not `UnsafeMutableRawPointer(bitPattern: -3)`.
- `PeekMessageW` returns `Bool` in Swift 6.4 WinSDK, so `.boolValue` was removed.

The final build was `Build complete! (3.60 secs)`, with no further errors.

## 5. Verbatim outputs (3 runs)

Each run was executed as `swift build -c release` output followed by `DrainProbe.exe` on the same Windows host, sequentially in one PowerShell invocation.

Run 1:
```
=== RUN 1
initial_thread_id=38900 hwnd_message=ok
main_queue_wake_handle=Optional(0x0000000000000298)
producer enqueue_rate_hz=1000.097459497428
jobs_run=10000/10000
latency_ms p50=0.0213 p95=0.0432 p99=0.0650 max=0.4859
thread_mismatches=0
reentrancy_violations=0 drain_calls=11001 guard_selftest_detected=true
nested_ran=true nested_recursion_violations=0
mainactor_hops=1000/1000 mainactor_thread_mismatches=0
idle_window_s=5.0163 idle_wakeups=0 event_wakes=11000 msg_wakes=0 loop_iterations=11000
workload_timed_out=false
total_runtime_s=15.0168 loop_s=15.0159
exit=0
```

Run 2:
```
=== RUN 2
initial_thread_id=26988 hwnd_message=ok
main_queue_wake_handle=Optional(0x0000000000000274)
producer enqueue_rate_hz=1000.0830568978753
jobs_run=10000/10000
latency_ms p50=0.0255 p95=0.0504 p99=0.0819 max=2.2792
thread_mismatches=0
reentrancy_violations=0 drain_calls=10966 guard_selftest_detected=true
nested_ran=true nested_recursion_violations=0
mainactor_hops=1000/1000 mainactor_thread_mismatches=0
idle_window_s=5.0213 idle_wakeups=0 event_wakes=10965 msg_wakes=0 loop_iterations=10965
workload_timed_out=false
total_runtime_s=15.0218 loop_s=15.0210
exit=0
```

Run 3:
```
=== RUN 3
initial_thread_id=25980 hwnd_message=ok
main_queue_wake_handle=Optional(0x0000000000000280)
producer enqueue_rate_hz=1000.098329667773
jobs_run=10000/10000
latency_ms p50=0.0240 p95=0.0491 p99=0.0779 max=0.8051
thread_mismatches=0
reentrancy_violations=0 drain_calls=11002 guard_selftest_detected=true
nested_ran=true nested_recursion_violations=0
mainactor_hops=1000/1000 mainactor_thread_mismatches=0
idle_window_s=5.0133 idle_wakeups=0 event_wakes=11001 msg_wakes=0 loop_iterations=11001
workload_timed_out=false
total_runtime_s=15.0139 loop_s=15.0131
exit=0
```

## 6. Criteria

| Criterion | Target | Run 1 | Run 2 | Run 3 | Result |
|---|---|---|---|---|---|
| All jobs run | 10000/10000 | 10000 | 10000 | 10000 | PASS |
| Thread mismatches (jobs) | 0 | 0 | 0 | 0 | PASS |
| Reentrancy violations | 0 | 0 | 0 | 0 | PASS |
| p99 latency | <= 16.7 ms | 0.0650 ms | 0.0819 ms | 0.0779 ms | PASS |
| MainActor hops on initial thread | 1000/1000 on main | 1000/1000, 0 mismatches | same | same | PASS |
| Idle wakeups (5 s) | low, ~0 | 0 | 0 | 0 | PASS |

Additional observations:
- Max latency was 0.49, 2.28 and 0.81 ms. Run 2's 2.28 ms max is a single outlier. The p99 is far below the threshold.
- The nested job ran after its outer job returned. No recursion occurred.
- `msg_wakes=0` in all runs. No window messages arrived before the quit, so the message path was not exercised under load. Only the `WM_QUIT` path was tested.
- `drain_calls` and `event_wakes` vary by run (10965 to 11002). Event wakes coalesce several enqueued items into one callback, so the count is not fixed. `loop_iterations` equals `event_wakes` in every run, so no spurious wakeups occurred.
- `drain_calls` includes the single guard self-test call.

## 7. Caveats

- The producer spins with `Sleep(0)` for pacing, so the 1 kHz rate is achieved by burning one core. The latency numbers are measured from enqueue, not from the pacing target.
- The probe drives the main queue without calling `dispatch_main()`. It relies on the private `_4CF` SPI, which Apple and swift-corelibs may change, so this result does not establish a stable public contract.
- The 5 s idle window was measured with INFINITE waits. No timers were armed, so zero wakeups is expected by construction for this loop. The result does not cover timers or other sources.
- Only one Windows x64 host and one Swift 6.4.0 toolchain were tested.
