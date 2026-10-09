//! Process-wide state shared by every module: statistics, the bounded event queue,
//! the wake/signal future, the non-reentrant host-callback guard and UI-thread checks.
//! Nothing here holds a lock while calling the host.

use std::cell::Cell;
use std::collections::VecDeque;
use std::future::Future;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering::SeqCst};
use std::sync::Mutex;
use std::task::{Context as TaskContext, Poll, Waker};

use crate::abi::*;

#[allow(non_snake_case)]
extern "system" {
    pub fn GetCurrentThreadId() -> u32;
    pub fn WaitForSingleObject(handle: *mut std::ffi::c_void, millis: u32) -> u32;
    pub fn QueryPerformanceCounter(out: *mut i64) -> i32;
    pub fn QueryPerformanceFrequency(out: *mut i64) -> i32;
}

// ---------------------------------------------------------------- statistics

pub const S_DRAIN_CALLS: usize = 0;
pub const S_REENTRY: usize = 1;
pub const S_THREAD_VIOL: usize = 2;
pub const S_HOST_PANICS: usize = 3;
pub const S_WAKES: usize = 4;
pub const S_TICKS_REQ: usize = 5;
pub const S_TICKS_DEL: usize = 6;
pub const S_PAINTS: usize = 7;
pub const S_COMMITS_OK: usize = 8;
pub const S_COMMITS_REJ: usize = 9;
pub const S_COMMITS_DEFERRED: usize = 10;
pub const S_MEASURE: usize = 11;
pub const S_MEASURE_HITS: usize = 12;
pub const S_EV_PUSHED: usize = 13;
pub const S_EV_FULL: usize = 14;
pub const S_EV_STALE: usize = 15;
pub const S_AX_ENQ: usize = 16;
pub const S_AX_REJ: usize = 17;
pub const S_IME_CALLS: usize = 18;
pub const S_IME_BUSY: usize = 19;
pub const S_SELFTEST: usize = 20;
pub const S_POST_DRAINS: usize = 21;
pub const S_POST_TIMEOUTS: usize = 22;
const S_COUNT: usize = 23;

static STATS: [AtomicU64; S_COUNT] = [const { AtomicU64::new(0) }; S_COUNT];

pub fn bump(i: usize) {
    STATS[i].fetch_add(1, SeqCst);
}

pub fn stat(i: usize) -> u64 {
    STATS[i].load(SeqCst)
}

pub fn fill_stats(out: &mut Stats) {
    out.struct_size = std::mem::size_of::<Stats>() as u32;
    out.drain_calls = stat(S_DRAIN_CALLS);
    out.reentry_refused = stat(S_REENTRY);
    out.thread_violations = stat(S_THREAD_VIOL);
    out.host_panics = stat(S_HOST_PANICS);
    out.wake_signals = stat(S_WAKES);
    out.ticks_requested = stat(S_TICKS_REQ);
    out.ticks_delivered = stat(S_TICKS_DEL);
    out.paints = stat(S_PAINTS);
    out.commits_accepted = stat(S_COMMITS_OK);
    out.commits_rejected = stat(S_COMMITS_REJ);
    out.commits_deferred = stat(S_COMMITS_DEFERRED);
    out.measure_calls = stat(S_MEASURE);
    out.measure_cache_hits = stat(S_MEASURE_HITS);
    out.events_pushed = stat(S_EV_PUSHED);
    out.events_dropped_full = stat(S_EV_FULL);
    out.events_dropped_stale = stat(S_EV_STALE);
    out.ax_actions_enqueued = stat(S_AX_ENQ);
    out.ax_actions_rejected = stat(S_AX_REJ);
    out.ime_calls = stat(S_IME_CALLS);
    out.ime_busy_rejected = stat(S_IME_BUSY);
    out.selftest_reentry_detected = stat(S_SELFTEST);
    out.live_nodes = LIVE_TREE_NODES.load(SeqCst) + LIVE_RUNS.load(SeqCst) + LIVE_IMAGES.load(SeqCst);
    out.post_close_drains = stat(S_POST_DRAINS);
    out.post_close_timeouts = stat(S_POST_TIMEOUTS);
}

// ------------------------------------------------------------------- flags

pub static UI_THREAD: AtomicU32 = AtomicU32::new(0);
pub static RUN_STARTED: AtomicBool = AtomicBool::new(false);
pub static SHUTDOWN: AtomicBool = AtomicBool::new(false);
pub static WAKE_HANDLE: AtomicUsize = AtomicUsize::new(0);
pub static MAIN_HWND: AtomicUsize = AtomicUsize::new(0);

/// Live window handle (generation<<32 | slot) or 0 when no window is live.
pub static LIVE_WINDOW: AtomicU64 = AtomicU64::new(0);
pub static NEXT_WINDOW_GEN: AtomicU32 = AtomicU32::new(1);
/// Focus target of the latest accepted commit when it is editable, else 0 (IME target).
pub static IME_NODE: AtomicU64 = AtomicU64::new(0);
/// Focus target of the latest accepted commit (editable or not).
pub static FOCUS_NODE: AtomicU64 = AtomicU64::new(0);
/// Version of the latest accepted commit.
pub static SNAPSHOT: AtomicU64 = AtomicU64::new(0);

pub static QUIT_REQUESTED: AtomicBool = AtomicBool::new(false);
pub static CLOSE_REQUESTED: AtomicBool = AtomicBool::new(false);
pub static WINDOW_CLOSED: AtomicBool = AtomicBool::new(false);
pub static PRESENT_PENDING: AtomicBool = AtomicBool::new(false);
pub static ANIMATING: AtomicBool = AtomicBool::new(false);
pub static KICK: AtomicBool = AtomicBool::new(false);
pub static TICK_PENDING: AtomicBool = AtomicBool::new(false);
pub static TICK_TARGET: AtomicU64 = AtomicU64::new(0);

pub static WIN_W: AtomicU32 = AtomicU32::new(0);
pub static WIN_H: AtomicU32 = AtomicU32::new(0);
pub static WIN_SCALE_BITS: AtomicU32 = AtomicU32::new(0);
pub static WIN_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Atomic mirrors of the UI-thread state, so swr_get_stats can read them from any thread.
/// Nodes in the committed tree, and live (unreleased) text-run handles.
pub static LIVE_TREE_NODES: AtomicU64 = AtomicU64::new(0);
pub static LIVE_RUNS: AtomicU64 = AtomicU64::new(0);
/// Rev 0.6: images alive in the renderer (host handle still held OR referenced by a
/// committed node); freed images are removed by `TrackedImage::drop`. Counted in live_nodes.
pub static LIVE_IMAGES: AtomicU64 = AtomicU64::new(0);
/// Rev 0.6: host-held swr_image handles (slab occupancy; not reported).
pub static IMAGE_HANDLES: AtomicU64 = AtomicU64::new(0);

/// Post-close pump (rev 0.5). ACTIVE is set before window_closed is entered; COMPLETE by
/// swr_shutdown_complete; EXPIRED by the timer thread when SWR_POST_CLOSE_TIMEOUT_MS passes.
pub static POST_CLOSE_ACTIVE: AtomicBool = AtomicBool::new(false);
pub static SHUTDOWN_COMPLETE: AtomicBool = AtomicBool::new(false);
pub static POST_CLOSE_EXPIRED: AtomicBool = AtomicBool::new(false);

pub fn on_ui_thread() -> bool {
    let t = UI_THREAD.load(SeqCst);
    t != 0 && unsafe { GetCurrentThreadId() } == t
}

pub fn new_window_handle() -> u64 {
    let gen = NEXT_WINDOW_GEN.fetch_add(1, SeqCst) as u64;
    (gen << 32) | 1
}

pub fn qpc_now() -> i64 {
    let mut v = 0i64;
    unsafe { QueryPerformanceCounter(&mut v) };
    v
}

pub fn qpc_to_ns(t: i64) -> u64 {
    static FREQ: AtomicU64 = AtomicU64::new(0);
    let mut f = FREQ.load(SeqCst);
    if f == 0 {
        let mut v = 0i64;
        unsafe { QueryPerformanceFrequency(&mut v) };
        f = v.max(1) as u64;
        FREQ.store(f, SeqCst);
    }
    ((t.max(0) as u128 * 1_000_000_000u128) / f as u128) as u64
}

// ------------------------------------------------------------ event queue

pub const EVENT_CAP: usize = 256;
static EVENTS: Mutex<VecDeque<Event>> = Mutex::new(VecDeque::new());
static NEXT_SEQ: AtomicU64 = AtomicU64::new(1);

fn lock_events() -> std::sync::MutexGuard<'static, VecDeque<Event>> {
    EVENTS.lock().unwrap_or_else(|e| e.into_inner())
}

/// Bounded push (callable from any thread). A full queue drops the NEW event and
/// counts it. Wakes the UI loop on success.
pub fn push_event(mut ev: Event) -> bool {
    ev.seq = NEXT_SEQ.fetch_add(1, SeqCst);
    {
        let mut q = lock_events();
        if q.len() >= EVENT_CAP {
            drop(q);
            bump(S_EV_FULL);
            return false;
        }
        q.push_back(ev);
    }
    bump(S_EV_PUSHED);
    signal_notify();
    true
}

pub fn events_pending() -> bool {
    !lock_events().is_empty()
}

/// Pops the oldest event whose window is still live. Events for a dead window are
/// dropped (counted) unless they carry no window (modal results).
pub fn pop_event() -> Option<Event> {
    loop {
        let ev = lock_events().pop_front()?;
        let live = LIVE_WINDOW.load(SeqCst);
        if ev.window != 0 && ev.window != live {
            bump(S_EV_STALE);
            continue;
        }
        return Some(ev);
    }
}

pub fn clear_events() {
    lock_events().clear();
}

// ----------------------------------------------------------- wake / signal

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

/// Record one wake and wake the drain task. Callable from any thread, any context.
pub fn signal_notify() {
    let waker = {
        let mut s = lock_signal();
        s.pending += 1;
        s.waker.take()
    };
    if let Some(w) = waker {
        w.wake();
    }
}

/// Resolves once per batch of signals; pending wakes coalesce into one poll so no
/// wake is lost between a drain and the next wait.
pub struct WaitSignal;

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

/// Blocks on the host's main-queue wake handle and turns each signal into a wake of
/// the drain task. Never touches GPUI.
pub fn waiter_loop(handle: usize) {
    loop {
        // WAIT_OBJECT_0 == 0, INFINITE == u32::MAX
        let rc = unsafe { WaitForSingleObject(handle as *mut std::ffi::c_void, u32::MAX) };
        if rc != 0 {
            eprintln!("[swiftright-render] WaitForSingleObject returned {rc:#x}; waiter stopped");
            return;
        }
        bump(S_WAKES);
        signal_notify();
    }
}

// ----------------------------------------------------------- host callbacks

#[derive(Clone, Copy)]
pub struct Host {
    pub ctx: usize,
    pub loop_ready: Option<extern "C" fn(*mut std::ffi::c_void, u64)>,
    pub drain: Option<extern "C" fn(*mut std::ffi::c_void)>,
    pub events_available: Option<extern "C" fn(*mut std::ffi::c_void)>,
    pub tick: Option<extern "C" fn(*mut std::ffi::c_void, u64, u64)>,
    pub window_closed: Option<extern "C" fn(*mut std::ffi::c_void, u64)>,
    pub ime_get_selection:
        Option<extern "C" fn(*mut std::ffi::c_void, u64, u64, *mut Utf16Selection) -> Status>,
    pub ime_get_marked: Option<
        extern "C" fn(*mut std::ffi::c_void, u64, u64, *mut Utf16Range, *mut i32) -> Status,
    >,
    pub ime_copy_text: Option<
        extern "C" fn(
            *mut std::ffi::c_void,
            u64,
            u64,
            Utf16Range,
            *mut u16,
            u32,
            *mut u32,
            *mut Utf16Range,
        ) -> Status,
    >,
    pub ime_replace: Option<
        extern "C" fn(*mut std::ffi::c_void, u64, u64, *const Utf16Range, *const u16, u32) -> Status,
    >,
    pub ime_replace_and_mark: Option<
        extern "C" fn(
            *mut std::ffi::c_void,
            u64,
            u64,
            *const Utf16Range,
            *const u16,
            u32,
            *const Utf16Range,
        ) -> Status,
    >,
    pub ime_unmark: Option<extern "C" fn(*mut std::ffi::c_void, u64, u64) -> Status>,
    pub ime_caret_bounds:
        Option<extern "C" fn(*mut std::ffi::c_void, u64, u64, Utf16Range, *mut Rect) -> Status>,
}

impl Host {
    pub fn from_abi(cb: &HostCallbacks) -> Host {
        Host {
            ctx: cb.ctx as usize,
            loop_ready: cb.loop_ready,
            drain: cb.drain,
            events_available: cb.events_available,
            tick: cb.tick,
            window_closed: cb.window_closed,
            ime_get_selection: cb.ime_get_selection,
            ime_get_marked: cb.ime_get_marked,
            ime_copy_text: cb.ime_copy_text,
            ime_replace: cb.ime_replace,
            ime_replace_and_mark: cb.ime_replace_and_mark,
            ime_unmark: cb.ime_unmark,
            ime_caret_bounds: cb.ime_caret_bounds,
        }
    }

    pub fn ctx_ptr(&self) -> *mut std::ffi::c_void {
        self.ctx as *mut std::ffi::c_void
    }
}

static HOST: Mutex<Option<Host>> = Mutex::new(None);

pub fn set_host(h: Option<Host>) {
    *HOST.lock().unwrap_or_else(|e| e.into_inner()) = h;
}

pub fn host() -> Option<Host> {
    *HOST.lock().unwrap_or_else(|e| e.into_inner())
}

static HOST_ACTIVE: AtomicBool = AtomicBool::new(false);

thread_local! {
    /// Depth of ime_* host callbacks on this thread (commits are "deferred" inside).
    pub static IN_IME: Cell<u32> = const { Cell::new(0) };
}

pub fn in_ime_callback() -> bool {
    IN_IME.with(|c| c.get() > 0)
}

pub fn host_active() -> bool {
    HOST_ACTIVE.load(SeqCst)
}

/// RAII non-reentrancy guard: at most one host callback runs at a time.
pub struct HostGuard;

pub fn enter_host() -> Option<HostGuard> {
    if HOST_ACTIVE.swap(true, SeqCst) {
        None
    } else {
        Some(HostGuard)
    }
}

impl Drop for HostGuard {
    fn drop(&mut self) {
        HOST_ACTIVE.store(false, SeqCst);
    }
}

/// Runs a host callback under the guard with panics contained. Returns false when the
/// callback was refused (nested, or off the UI thread); the caller re-signals if needed.
pub fn call_host(f: impl FnOnce()) -> bool {
    if !on_ui_thread() {
        bump(S_THREAD_VIOL);
        return false;
    }
    let Some(_guard) = enter_host() else {
        bump(S_REENTRY);
        return false;
    };
    if catch_unwind(AssertUnwindSafe(f)).is_err() {
        bump(S_HOST_PANICS);
    }
    true
}

/// `swr_selftest_reentry`: only meaningful from inside a drain callback.
pub fn selftest_reentry() -> Status {
    if !host_active() {
        return -1;
    }
    match enter_host() {
        None => {
            bump(S_SELFTEST);
            1
        }
        Some(_g) => 0, // would have been allowed: guard failed to protect (cannot happen)
    }
}

/// Bounded, lossy copy of `src` into an event text buffer; returns bytes written.
pub fn copy_text(dst: &mut [u8], at: usize, src: &[u8]) -> usize {
    let room = dst.len().saturating_sub(at);
    let n = src.len().min(room);
    dst[at..at + n].copy_from_slice(&src[..n]);
    n
}
