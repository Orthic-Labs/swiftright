//! SR0-B drain probe.
//!
//! `swr_run` blocks and runs GPUI 0.2.2's Windows application on the calling
//! (initial) thread. Swift's main dispatch queue is drained from a GPUI
//! foreground task, which runs from GPUI's window proc with no App or Window
//! borrow held.
//!
//! Wake path: a waiter thread blocks on Swift's main-queue wake HANDLE
//! (libdispatch auto-reset event). Each signal calls `signal_notify()`, which
//! wakes the `WaitSignal` future that the drain task awaits. The waker is
//! GPUI's own: `ForegroundExecutor` runnables woken from another thread go
//! through `PlatformDispatcher::dispatch_on_main_thread`, which queues the
//! runnable and posts WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD to GPUI's
//! message-only window. `WindowsPlatform::run_foreground_task` then runs it.

use std::ffi::c_void;
use std::future::Future;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering::SeqCst};
use std::sync::Mutex;
use std::task::{Context as TaskContext, Poll, Waker};
use std::time::Duration;

use gpui::{
    div, prelude::*, px, size, App, AsyncApp, Application, Bounds, Context, IntoElement, Render,
    TitlebarOptions, Window, WindowBounds, WindowHandle, WindowOptions,
};

pub const SWR_OK: i32 = 0;
const SWR_ERR_ARGS: i32 = -1;
const SWR_ERR_PANIC: i32 = -2;
const SWR_ERR_NOT_READY: i32 = -3;
const SWR_ERR_RUNNING: i32 = -4;
const SWR_ERR_APP: i32 = -5;
const SWR_ERR_WAKE: i32 = -6;
const SWR_ERR_STALE: i32 = -7; // target generation/node is gone
const SWR_ERR_FULL: i32 = -8; // job queue at capacity

const ABI_MAJOR: u32 = 0;
const ABI_MINOR: u32 = 2; // 0.2: adds the late-dispatch fault surface (swr_post_job & co.)
const FN_TABLE_SIZE: u32 = 10;
const JOB_QUEUE_CAP: usize = 4096;

#[allow(non_snake_case)]
extern "system" {
    fn GetCurrentThreadId() -> u32;
    fn WaitForSingleObject(handle: *mut c_void, millis: u32) -> u32;
}

// ---- Shared state (no lock is held while calling into Swift) ----

static WAKE_HANDLE: AtomicUsize = AtomicUsize::new(0);
static RUNNING: AtomicBool = AtomicBool::new(false);
static DRAINING: AtomicBool = AtomicBool::new(false);
static UI_THREAD: AtomicU32 = AtomicU32::new(0);
static QUIT_REQUESTED: AtomicBool = AtomicBool::new(false);
static WINDOW_CLOSED: AtomicBool = AtomicBool::new(false);
static OPEN_FAILED: AtomicBool = AtomicBool::new(false);

static DRAIN_CALLS: AtomicU64 = AtomicU64::new(0);
static DRAIN_VIOLATIONS: AtomicU64 = AtomicU64::new(0);
static THREAD_VIOLATIONS: AtomicU64 = AtomicU64::new(0);
static SELFTEST_DETECTED: AtomicU64 = AtomicU64::new(0);
static WAKE_SIGNALS: AtomicU64 = AtomicU64::new(0);
static WAKE_WAIT_FAILURES: AtomicU64 = AtomicU64::new(0);
static LOOP_READY_CALLS: AtomicU64 = AtomicU64::new(0);
static WINDOW_CLOSED_EVENTS: AtomicU64 = AtomicU64::new(0);
static QUIT_REQUESTS: AtomicU64 = AtomicU64::new(0);
static FRAMES: AtomicU64 = AtomicU64::new(0);

// ---- Late-dispatch fault surface ----
// A job is a continuation addressed to (target generation, node). It is accepted only while
// both are live, and delivered to the host only while both are still live at delivery.
// WINDOW_GEN changes only under the JOBS lock, and the same lock covers the accept check and
// the push, so a job can never be left queued behind a close that already flushed the queue.
// Delivery and close both run on the UI thread, so a job cannot be delivered after close.
static WINDOW_GEN: AtomicU64 = AtomicU64::new(0);
static NEXT_GEN: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy)]
struct Job {
    gen: u64,
    node: u64,
    token: u64,
}

static JOBS: Mutex<Vec<Job>> = Mutex::new(Vec::new());
static LIVE_NODES: Mutex<Vec<u64>> = Mutex::new(Vec::new());

static LATE_POSTED_OK: AtomicU64 = AtomicU64::new(0);
static LATE_DELIVERED: AtomicU64 = AtomicU64::new(0);
static LATE_DROPPED_AT_CLOSE: AtomicU64 = AtomicU64::new(0);
static LATE_DROPPED_AT_DELIVER: AtomicU64 = AtomicU64::new(0);
static LATE_REJ_CLOSED: AtomicU64 = AtomicU64::new(0);
static LATE_REJ_GEN: AtomicU64 = AtomicU64::new(0);
static LATE_REJ_NODE: AtomicU64 = AtomicU64::new(0);
static LATE_REJ_FULL: AtomicU64 = AtomicU64::new(0);

fn lock_jobs() -> std::sync::MutexGuard<'static, Vec<Job>> {
    JOBS.lock().unwrap_or_else(|e| e.into_inner())
}

fn node_is_live(node: u64) -> bool {
    LIVE_NODES.lock().unwrap_or_else(|e| e.into_inner()).contains(&node)
}

/// Target opened: publish a fresh generation.
fn open_target() -> u64 {
    let _q = lock_jobs();
    let gen = NEXT_GEN.fetch_add(1, SeqCst);
    WINDOW_GEN.store(gen, SeqCst);
    gen
}

/// Target gone: retire the generation and drop every queued job addressed to it.
/// Idempotent. Never calls the host.
fn close_target() {
    let mut q = lock_jobs();
    WINDOW_GEN.store(0, SeqCst);
    let n = q.len() as u64;
    q.clear();
    if n > 0 {
        LATE_DROPPED_AT_CLOSE.fetch_add(n, SeqCst);
    }
}

/// UI thread, outside any App/Window borrow. Hands each still-valid job to the host and
/// drops the rest. No lock is held while calling Swift.
fn deliver_jobs(h: HostRef) {
    let batch = std::mem::take(&mut *lock_jobs());
    for j in batch {
        let cur = WINDOW_GEN.load(SeqCst);
        if cur == 0 || j.gen != cur || (j.node != 0 && !node_is_live(j.node)) {
            LATE_DROPPED_AT_DELIVER.fetch_add(1, SeqCst);
            continue;
        }
        LATE_DELIVERED.fetch_add(1, SeqCst);
        if let Some(f) = h.job {
            let _ = catch_unwind(AssertUnwindSafe(|| f(h.ctx as *mut c_void, j.node, j.token)));
        }
    }
}

/// Plain copy of the host callbacks. `ctx` is stored as usize so the static
/// below is Send. Callbacks are fn pointers, which are Send.
#[derive(Clone, Copy)]
struct HostRef {
    ctx: usize,
    loop_ready: Option<extern "C" fn(*mut c_void)>,
    drain: Option<extern "C" fn(*mut c_void)>,
    window_closed: Option<extern "C" fn(*mut c_void)>,
    job: Option<extern "C" fn(*mut c_void, u64, u64)>,
}

static HOST: Mutex<Option<HostRef>> = Mutex::new(None);

#[derive(Default)]
struct SignalState {
    pending: u64,
    waker: Option<Waker>,
}

static SIGNAL: Mutex<SignalState> = Mutex::new(SignalState {
    pending: 0,
    waker: None,
});

fn lock_signal() -> std::sync::MutexGuard<'static, SignalState> {
    SIGNAL.lock().unwrap_or_else(|e| e.into_inner())
}

/// Record one wake and wake the drain task. Callable from any thread.
fn signal_notify() {
    let waker = {
        let mut s = lock_signal();
        s.pending += 1;
        s.waker.take()
    };
    if let Some(w) = waker {
        w.wake();
    }
}

/// Resolves once per batch of signals. Pending wakes are coalesced into one
/// poll, so no wake is lost between a drain and the next wait.
struct WaitSignal;

impl Future for WaitSignal {
    type Output = u64;

    fn poll(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<u64> {
        let mut s = lock_signal();
        if s.pending > 0 {
            let n = s.pending;
            s.pending = 0;
            Poll::Ready(n)
        } else {
            s.waker = Some(cx.waker().clone());
            Poll::Pending
        }
    }
}

fn call(f: Option<extern "C" fn(*mut c_void)>, ctx: usize) -> bool {
    match f {
        Some(f) => catch_unwind(AssertUnwindSafe(|| f(ctx as *mut c_void))).is_ok(),
        None => false,
    }
}

/// Non-reentrant drain. Returns without calling Swift if a drain is active.
fn guarded_drain(h: HostRef) {
    DRAIN_CALLS.fetch_add(1, SeqCst);
    if DRAINING.swap(true, SeqCst) {
        DRAIN_VIOLATIONS.fetch_add(1, SeqCst);
        return;
    }
    if unsafe { GetCurrentThreadId() } != UI_THREAD.load(SeqCst) {
        THREAD_VIOLATIONS.fetch_add(1, SeqCst);
    }
    call(h.drain, h.ctx);
    DRAINING.store(false, SeqCst);
}

fn waiter_loop(handle: usize) {
    loop {
        // WAIT_OBJECT_0 == 0, INFINITE == u32::MAX
        let rc = unsafe { WaitForSingleObject(handle as *mut c_void, u32::MAX) };
        if rc != 0 {
            WAKE_WAIT_FAILURES.fetch_add(1, SeqCst);
            eprintln!("[sr0-b rust] WaitForSingleObject returned {rc:#x}; waiter stopped");
            return;
        }
        WAKE_SIGNALS.fetch_add(1, SeqCst);
        signal_notify();
    }
}

struct ProbeView;

impl Render for ProbeView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let frame = FRAMES.fetch_add(1, SeqCst) + 1;
        div()
            .size_full()
            .child(format!("SR0-B drain probe, frame {frame}"))
    }
}

fn launch(cx: &mut App, host: HostRef) {
    let bounds = Bounds::centered(None, size(px(640.), px(360.)), cx);
    let handle: WindowHandle<ProbeView> = match cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("SR0-B drain".into()),
                ..Default::default()
            }),
            ..Default::default()
        },
        |_, cx| cx.new(|_| ProbeView),
    ) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("[sr0-b rust] open_window failed: {e:?}");
            OPEN_FAILED.store(true, SeqCst);
            cx.quit();
            return;
        }
    };

    // Runs inside App's close path. Only sets flags and wakes the drain task.
    open_target();
    let closed_sub = cx.on_window_closed(|_cx| {
        close_target();
        WINDOW_CLOSED.store(true, SeqCst);
        signal_notify();
    });

    // Frame clock: 16 ms ticks force a re-render, so frames keep flowing.
    cx.spawn(async move |cx: &mut AsyncApp| loop {
        cx.background_executor()
            .timer(Duration::from_millis(16))
            .await;
        let alive = cx.update(|cx| handle.update(cx, |_v, _w, cx| cx.notify()).is_ok());
        if !matches!(alive, Ok(true)) || QUIT_REQUESTED.load(SeqCst) {
            break;
        }
    })
    .detach();

    // Drain task. Its body runs as a GPUI foreground runnable, outside any
    // App or Window borrow.
    cx.spawn(async move |cx: &mut AsyncApp| {
        let _keep_subscription_alive = closed_sub;
        LOOP_READY_CALLS.fetch_add(1, SeqCst);
        call(host.loop_ready, host.ctx);

        let mut close_issued = false;
        loop {
            WaitSignal.await;
            guarded_drain(host);
            deliver_jobs(host);

            if QUIT_REQUESTED.load(SeqCst) && !close_issued {
                close_issued = true;
                let _ = cx.update(|cx| {
                    let _ = handle.update(cx, |_, window, _| window.remove_window());
                });
            }

            if WINDOW_CLOSED.load(SeqCst) {
                WINDOW_CLOSED_EVENTS.fetch_add(1, SeqCst);
                call(host.window_closed, host.ctx);
                let _ = cx.update(|cx| cx.quit());
                break;
            }
        }
    })
    .detach();
}

fn run_inner(cb: *const SwrHostCallbacks) -> i32 {
    if cb.is_null() {
        return SWR_ERR_ARGS;
    }
    let raw = unsafe { *cb };
    if (raw.struct_size as usize) < std::mem::size_of::<SwrHostCallbacks>() || raw.drain.is_none() {
        return SWR_ERR_ARGS;
    }
    let wake = WAKE_HANDLE.load(SeqCst);
    if wake == 0 {
        return SWR_ERR_NOT_READY;
    }
    if RUNNING.swap(true, SeqCst) {
        return SWR_ERR_RUNNING;
    }

    let host = HostRef {
        ctx: raw.ctx as usize,
        loop_ready: raw.loop_ready,
        drain: raw.drain,
        window_closed: raw.window_closed,
        job: raw.job,
    };
    *HOST.lock().unwrap_or_else(|e| e.into_inner()) = Some(host);
    UI_THREAD.store(unsafe { GetCurrentThreadId() }, SeqCst);

    if std::thread::Builder::new()
        .name("swr-wake-waiter".into())
        .spawn(move || waiter_loop(wake))
        .is_err()
    {
        RUNNING.store(false, SeqCst);
        return SWR_ERR_WAKE;
    }

    Application::new().run(move |cx: &mut App| launch(cx, host));

    close_target();
    let rc = if OPEN_FAILED.load(SeqCst) { SWR_ERR_APP } else { SWR_OK };
    println!(
        "[sr0-b rust] loop_ready_calls={} drain_calls={} drain_reentry_violations={} thread_violations={} selftest_detected={} wake_signals={} wake_wait_failures={} frames_rendered={} window_closed_events={} quit_requests={} open_failed={} run_rc={}",
        LOOP_READY_CALLS.load(SeqCst),
        DRAIN_CALLS.load(SeqCst),
        DRAIN_VIOLATIONS.load(SeqCst),
        THREAD_VIOLATIONS.load(SeqCst),
        SELFTEST_DETECTED.load(SeqCst),
        WAKE_SIGNALS.load(SeqCst),
        WAKE_WAIT_FAILURES.load(SeqCst),
        FRAMES.load(SeqCst),
        WINDOW_CLOSED_EVENTS.load(SeqCst),
        QUIT_REQUESTS.load(SeqCst),
        OPEN_FAILED.load(SeqCst),
        rc,
    );
    println!(
        "[sr0-b rust] late_dispatch posted_ok={} delivered={} dropped_at_close={} dropped_at_deliver={} rejected_closed={} rejected_stale_gen={} rejected_stale_node={} rejected_full={}",
        LATE_POSTED_OK.load(SeqCst),
        LATE_DELIVERED.load(SeqCst),
        LATE_DROPPED_AT_CLOSE.load(SeqCst),
        LATE_DROPPED_AT_DELIVER.load(SeqCst),
        LATE_REJ_CLOSED.load(SeqCst),
        LATE_REJ_GEN.load(SeqCst),
        LATE_REJ_NODE.load(SeqCst),
        LATE_REJ_FULL.load(SeqCst),
    );
    *HOST.lock().unwrap_or_else(|e| e.into_inner()) = None;
    RUNNING.store(false, SeqCst);
    rc
}

// ---- C ABI ----

#[repr(C)]
pub struct SwrBootstrapInfo {
    pub struct_size: u32,
    pub abi_major: u32,
    pub abi_minor: u32,
    pub pointer_width: u32,
    pub arch: [u8; 16],
    pub fn_table_size: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct SwrHostCallbacks {
    pub struct_size: u32,
    pub ctx: *mut c_void,
    pub loop_ready: Option<extern "C" fn(*mut c_void)>,
    pub drain: Option<extern "C" fn(*mut c_void)>,
    pub window_closed: Option<extern "C" fn(*mut c_void)>,
    pub job: Option<extern "C" fn(*mut c_void, u64, u64)>,
}

#[no_mangle]
pub extern "C" fn swr_bootstrap_query(out: *mut SwrBootstrapInfo, caller_size: u32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let need = std::mem::size_of::<SwrBootstrapInfo>() as u32;
        if out.is_null() || caller_size < need {
            return SWR_ERR_ARGS;
        }
        let mut arch = [0u8; 16];
        let name = b"x86_64";
        arch[..name.len()].copy_from_slice(name);
        unsafe {
            *out = SwrBootstrapInfo {
                struct_size: need,
                abi_major: ABI_MAJOR,
                abi_minor: ABI_MINOR,
                pointer_width: (std::mem::size_of::<usize>() * 8) as u32,
                arch,
                fn_table_size: FN_TABLE_SIZE,
            };
        }
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

#[no_mangle]
pub extern "C" fn swr_set_wake_handle(handle: *mut c_void) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return SWR_ERR_ARGS;
        }
        if RUNNING.load(SeqCst) {
            return SWR_ERR_RUNNING;
        }
        WAKE_HANDLE.store(handle as usize, SeqCst);
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Blocks on the calling thread until the window closes and GPUI quits.
#[no_mangle]
pub extern "C" fn swr_run(cb: *const SwrHostCallbacks) -> i32 {
    catch_unwind(AssertUnwindSafe(|| run_inner(cb))).unwrap_or(SWR_ERR_PANIC)
}

/// Thread-safe. Sets a flag and wakes the drain task, which closes the window
/// and quits outside any borrow. Safe to call from inside the drain callback.
#[no_mangle]
pub extern "C" fn swr_request_quit() -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        QUIT_REQUESTS.fetch_add(1, SeqCst);
        QUIT_REQUESTED.store(true, SeqCst);
        signal_notify();
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

#[no_mangle]
pub extern "C" fn swr_frames_rendered() -> u64 {
    catch_unwind(|| FRAMES.load(SeqCst)).unwrap_or(0)
}

/// Called only from inside a drain callback. Re-enters the guarded drain and
/// checks that it is refused. Returns 1 when the guard refused re-entry, 0 when
/// it did not, -1 when not called inside a drain. The refusal is removed from
/// the violation count, so the reported violations come only from real drains.
#[no_mangle]
pub extern "C" fn swr_selftest_reentry() -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if !DRAINING.load(SeqCst) {
            return -1;
        }
        let host = match *HOST.lock().unwrap_or_else(|e| e.into_inner()) {
            Some(h) => h,
            None => return -1,
        };
        let before = DRAIN_VIOLATIONS.load(SeqCst);
        guarded_drain(host);
        let after = DRAIN_VIOLATIONS.load(SeqCst);
        if after == before + 1 {
            DRAIN_VIOLATIONS.fetch_sub(1, SeqCst);
            SELFTEST_DETECTED.fetch_add(1, SeqCst);
            1
        } else {
            0
        }
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

// ---- Late-dispatch fault surface (ABI 0.2) ----

#[repr(C)]
pub struct SwrLateStats {
    pub struct_size: u32,
    pub reserved: u32,
    pub window_gen: u64,
    pub posted_ok: u64,
    pub delivered: u64,
    pub dropped_at_close: u64,
    pub dropped_at_deliver: u64,
    pub rejected_closed: u64,
    pub rejected_stale_gen: u64,
    pub rejected_stale_node: u64,
    pub rejected_full: u64,
}

/// Current live target generation, or 0 when none exists. Thread-safe.
#[no_mangle]
pub extern "C" fn swr_window_generation() -> u64 {
    catch_unwind(|| WINDOW_GEN.load(SeqCst)).unwrap_or(0)
}

/// Marks a node live (nonzero `live`) or gone (zero). Thread-safe. Node 0 means "no node".
#[no_mangle]
pub extern "C" fn swr_node_set(node: u64, live: i32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if node == 0 {
            return SWR_ERR_ARGS;
        }
        let mut n = LIVE_NODES.lock().unwrap_or_else(|e| e.into_inner());
        n.retain(|x| *x != node);
        if live != 0 {
            n.push(node);
        }
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Thread-safe. Queues a continuation for the host's `job` callback on the UI thread.
/// Returns SWR_ERR_STALE (and counts why) when the generation is not the live one, no
/// target exists, or `node` (when nonzero) is not live; SWR_ERR_FULL at capacity.
/// A job accepted here is still dropped, uncalled, if its target dies before delivery.
#[no_mangle]
pub extern "C" fn swr_post_job(generation: u64, node: u64, token: u64) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        {
            let mut q = lock_jobs();
            let cur = WINDOW_GEN.load(SeqCst);
            if cur == 0 {
                LATE_REJ_CLOSED.fetch_add(1, SeqCst);
                return SWR_ERR_STALE;
            }
            if generation != cur {
                LATE_REJ_GEN.fetch_add(1, SeqCst);
                return SWR_ERR_STALE;
            }
            if node != 0 && !node_is_live(node) {
                LATE_REJ_NODE.fetch_add(1, SeqCst);
                return SWR_ERR_STALE;
            }
            if q.len() >= JOB_QUEUE_CAP {
                LATE_REJ_FULL.fetch_add(1, SeqCst);
                return SWR_ERR_FULL;
            }
            q.push(Job { gen: generation, node, token });
            LATE_POSTED_OK.fetch_add(1, SeqCst);
        }
        signal_notify();
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

#[no_mangle]
pub extern "C" fn swr_late_stats(out: *mut SwrLateStats, caller_size: u32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let need = std::mem::size_of::<SwrLateStats>() as u32;
        if out.is_null() || caller_size < need {
            return SWR_ERR_ARGS;
        }
        unsafe {
            *out = SwrLateStats {
                struct_size: need,
                reserved: 0,
                window_gen: WINDOW_GEN.load(SeqCst),
                posted_ok: LATE_POSTED_OK.load(SeqCst),
                delivered: LATE_DELIVERED.load(SeqCst),
                dropped_at_close: LATE_DROPPED_AT_CLOSE.load(SeqCst),
                dropped_at_deliver: LATE_DROPPED_AT_DELIVER.load(SeqCst),
                rejected_closed: LATE_REJ_CLOSED.load(SeqCst),
                rejected_stale_gen: LATE_REJ_GEN.load(SeqCst),
                rejected_stale_node: LATE_REJ_NODE.load(SeqCst),
                rejected_full: LATE_REJ_FULL.load(SeqCst),
            };
        }
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}
