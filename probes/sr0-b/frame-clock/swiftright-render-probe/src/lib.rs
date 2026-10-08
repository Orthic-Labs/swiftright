//! SR0-B frame-clock probe (C ABI 0.2, probe-only).
//!
//! `swr_run` blocks and runs GPUI 0.2.2's Windows application on the calling
//! (initial) thread. Swift's main dispatch queue is drained from a GPUI
//! foreground task with no App or Window borrow held (same drain path as
//! gpui-drain).
//!
//! Frame clock (no timer): GPUI 0.2.2 on Windows drives frames from a VSync
//! thread that calls RedrawWindow every vblank; WM_PAINT then runs
//! `on_request_frame`, which runs `Window::on_next_frame` callbacks before
//! deciding whether to draw. While animation is active, each paint calls
//! `Window::request_animation_frame()` (the next vblank redraws) and records a
//! tick request. The drain task (outside any borrow) delivers that tick to Swift
//! as `tick(ctx, timestamp_ns)`. Swift advances its counter, calls
//! `swr_submit_commit`, and the next paint consumes the committed value. When
//! animation is off, paints stop requesting frames and the chain ends.
//!
//! Measurement: every wake, drain, paint and tick is appended to a preallocated
//! event ring with QPC timestamps. A sampler thread polls DwmFlush and
//! DwmGetCompositionTimingInfo to record compositor-displayed frames (desktop
//! global, not per swap chain). `swr_report` prints presented-frame intervals and,
//! for each job over 16.7 ms, the overlapping wake/drain/paint/tick intervals and
//! the time where the UI thread was in none of them.

use std::cell::UnsafeCell;
use std::ffi::{c_char, c_void, CStr};
use std::fmt::Write as _;
use std::future::Future;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering::SeqCst};
use std::sync::{Mutex, OnceLock};
use std::task::{Context as TaskContext, Poll, Waker};
use std::time::Duration;

use gpui::{
    canvas, div, fill, point, prelude::*, px, rgb, size, App, AsyncApp, Application, Bounds,
    Context, IntoElement, Pixels, Render, TitlebarOptions, Window, WindowBounds, WindowHandle,
    WindowOptions,
};
use windows::core::PCWSTR;
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Dwm::{DwmFlush, DwmGetCompositionTimingInfo, DWM_TIMING_INFO};
use windows::Win32::Graphics::Gdi::{EnumDisplaySettingsW, DEVMODEW, ENUM_CURRENT_SETTINGS};
use windows::Win32::Media::timeBeginPeriod;
use windows::Win32::System::Performance::{QueryPerformanceCounter, QueryPerformanceFrequency};

pub const SWR_OK: i32 = 0;
const SWR_ERR_ARGS: i32 = -1;
const SWR_ERR_PANIC: i32 = -2;
const SWR_ERR_NOT_READY: i32 = -3;
const SWR_ERR_RUNNING: i32 = -4;
const SWR_ERR_APP: i32 = -5;
const SWR_ERR_WAKE: i32 = -6;

const ABI_MAJOR: u32 = 0;
const ABI_MINOR: u32 = 2;
const FN_TABLE_SIZE: u32 = 9;

const EV_CAP: usize = 1 << 17;
const DWM_CAP: usize = 1 << 13;
const STALL_THRESHOLD_MS: f64 = 16.7;
const MAX_STALL_BLOCKS: usize = 60;

// Event kinds (events.csv column `kind`).
const K_WAKE: u32 = 1;
const K_DRAIN: u32 = 2;
const K_PAINT: u32 = 3;
const K_TICK: u32 = 4;
// Wake sources (aux of K_WAKE).
const SRC_WAITER: u32 = 0;
const SRC_PAINT: u32 = 1;
const SRC_KICK: u32 = 2;
const SRC_QUIT: u32 = 3;

#[allow(non_snake_case)]
extern "system" {
    fn GetCurrentThreadId() -> u32;
    fn WaitForSingleObject(handle: *mut c_void, millis: u32) -> u32;
    fn EnumWindows(f: extern "system" fn(isize, isize) -> i32, lparam: isize) -> i32;
    fn GetWindowThreadProcessId(hwnd: isize, pid: *mut u32) -> u32;
    fn IsWindowVisible(hwnd: isize) -> i32;
    fn GetCurrentProcessId() -> u32;
    fn GetForegroundWindow() -> isize;
}

/// Visible top-level window owned by this process (the gpui window), for DWM queries.
static PROBE_HWND: AtomicUsize = AtomicUsize::new(0);

extern "system" fn find_own_window(hwnd: isize, _lparam: isize) -> i32 {
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
    if pid == unsafe { GetCurrentProcessId() } && unsafe { IsWindowVisible(hwnd) } != 0 {
        PROBE_HWND.store(hwnd as usize, SeqCst);
        return 0;
    }
    1
}

// ---- QPC ----

static QPC_FREQ: OnceLock<i64> = OnceLock::new();

fn qpc_freq() -> i64 {
    *QPC_FREQ.get_or_init(|| {
        let mut f = 0i64;
        unsafe {
            let _ = QueryPerformanceFrequency(&mut f);
        }
        f
    })
}

fn qpc_now() -> i64 {
    let mut c = 0i64;
    unsafe {
        let _ = QueryPerformanceCounter(&mut c);
    }
    c
}

fn qpc_to_ns(t: i64) -> u64 {
    ((t as i128) * 1_000_000_000i128 / qpc_freq() as i128).max(0) as u64
}

// ---- Event ring (single preallocated buffer, one writer per slot) ----

#[derive(Clone, Copy, Default)]
struct Ev {
    kind: u32,
    aux: u32,
    t0: i64,
    t1: i64,
    v: u64,
}

#[derive(Clone, Copy, Default)]
struct DwmSample {
    qpc: i64,
    c_fd: u64,
    qpc_fd: u64,
    qpc_vblank: u64,
    c_refresh: u64,
    rate_num: u32,
    rate_den: u32,
    fast: u32,
    fg: u32,
}

struct Ring<T: Copy + Default> {
    head: AtomicUsize,
    slots: Box<[UnsafeCell<T>]>,
}

// Each slot is written by exactly one reserved index; readers run after the
// writers are finished (dump/report happen after swr_run returns).
unsafe impl<T: Copy + Default + Send> Sync for Ring<T> {}

impl<T: Copy + Default> Ring<T> {
    fn new(cap: usize) -> Self {
        Ring {
            head: AtomicUsize::new(0),
            slots: (0..cap).map(|_| UnsafeCell::new(T::default())).collect(),
        }
    }

    fn push(&self, v: T) {
        let i = self.head.fetch_add(1, SeqCst);
        if i < self.slots.len() {
            unsafe { *self.slots[i].get() = v };
        }
    }

    fn snapshot(&self) -> Vec<T> {
        let n = self.head.load(SeqCst).min(self.slots.len());
        (0..n).map(|i| unsafe { *self.slots[i].get() }).collect()
    }

    fn dropped(&self) -> usize {
        self.head.load(SeqCst).saturating_sub(self.slots.len())
    }
}

static EVENTS: OnceLock<Ring<Ev>> = OnceLock::new();
static DWM: OnceLock<Ring<DwmSample>> = OnceLock::new();

fn events() -> &'static Ring<Ev> {
    EVENTS.get_or_init(|| Ring::new(EV_CAP))
}

fn dwm_ring() -> &'static Ring<DwmSample> {
    DWM.get_or_init(|| Ring::new(DWM_CAP))
}

// ---- Shared state (no lock is held while calling into Swift) ----

static WAKE_HANDLE: AtomicUsize = AtomicUsize::new(0);
static RUNNING: AtomicBool = AtomicBool::new(false);
static DRAINING: AtomicBool = AtomicBool::new(false);
static UI_THREAD: AtomicU32 = AtomicU32::new(0);
static QUIT_REQUESTED: AtomicBool = AtomicBool::new(false);
static WINDOW_CLOSED: AtomicBool = AtomicBool::new(false);
static OPEN_FAILED: AtomicBool = AtomicBool::new(false);
static SAMPLER_RUN: AtomicBool = AtomicBool::new(false);

static ANIMATING: AtomicBool = AtomicBool::new(false);
static KICK: AtomicBool = AtomicBool::new(false);
static TICK_PENDING: AtomicBool = AtomicBool::new(false);
static TICK_TARGET: AtomicU64 = AtomicU64::new(0);
static COMMIT_SEQ: AtomicU64 = AtomicU64::new(0);
static PREV_SEQ_SEEN: AtomicU64 = AtomicU64::new(0);

static DRAIN_CALLS: AtomicU64 = AtomicU64::new(0);
static DRAIN_VIOLATIONS: AtomicU64 = AtomicU64::new(0);
static THREAD_VIOLATIONS: AtomicU64 = AtomicU64::new(0);
static SELFTEST_DETECTED: AtomicU64 = AtomicU64::new(0);
static WAKE_SIGNALS: AtomicU64 = AtomicU64::new(0);
static WAKE_WAIT_FAILURES: AtomicU64 = AtomicU64::new(0);
static LOOP_READY_CALLS: AtomicU64 = AtomicU64::new(0);
static WINDOW_CLOSED_EVENTS: AtomicU64 = AtomicU64::new(0);
static QUIT_REQUESTS: AtomicU64 = AtomicU64::new(0);
static PAINTS: AtomicU64 = AtomicU64::new(0);
static STALE_PAINTS: AtomicU64 = AtomicU64::new(0);
static TICKS_REQUESTED: AtomicU64 = AtomicU64::new(0);
static TICKS_DELIVERED: AtomicU64 = AtomicU64::new(0);
static COMMITS_SUBMITTED: AtomicU64 = AtomicU64::new(0);
static TIMER_RES_RC: AtomicU32 = AtomicU32::new(u32::MAX);
static DWM_FAST_RETURNS: AtomicU64 = AtomicU64::new(0);

/// Plain copy of the host callbacks. `ctx` is stored as usize so the static
/// below is Send. Callbacks are fn pointers, which are Send.
#[derive(Clone, Copy)]
struct HostRef {
    ctx: usize,
    loop_ready: Option<extern "C" fn(*mut c_void)>,
    drain: Option<extern "C" fn(*mut c_void)>,
    window_closed: Option<extern "C" fn(*mut c_void)>,
    tick: Option<extern "C" fn(*mut c_void, u64)>,
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
fn signal_notify(src: u32) {
    events().push(Ev {
        kind: K_WAKE,
        aux: src,
        t0: qpc_now(),
        t1: 0,
        v: 0,
    });
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
    if unsafe { GetCurrentThreadId() } != UI_THREAD.load(SeqCst)
    {
        THREAD_VIOLATIONS.fetch_add(1, SeqCst);
    }
    let t0 = qpc_now();
    call(h.drain, h.ctx);
    let t1 = qpc_now();
    events().push(Ev {
        kind: K_DRAIN,
        aux: 0,
        t0,
        t1,
        v: DRAIN_CALLS.load(SeqCst),
    });
    DRAINING.store(false, SeqCst);
}

/// Delivers one coalesced display tick. Called from the drain task, outside any
/// GPUI borrow, after the drain callback returns.
fn deliver_tick(h: HostRef) {
    let target = TICK_TARGET.load(SeqCst);
    let t0 = qpc_now();
    if let Some(f) = h.tick {
        let ctx = h.ctx as *mut c_void;
        let ts = qpc_to_ns(target as i64);
        let _ = catch_unwind(AssertUnwindSafe(|| f(ctx, ts)));
    }
    let t1 = qpc_now();
    TICKS_DELIVERED.fetch_add(1, SeqCst);
    events().push(Ev {
        kind: K_TICK,
        aux: 0,
        t0,
        t1,
        v: target,
    });
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
        signal_notify(SRC_WAITER);
    }
}

// ---- Frame clock ----

/// Runs inside the window's paint. Never calls Swift; only records and requests.
fn paint_frame(bounds: Bounds<Pixels>, window: &mut Window) {
    let t0 = qpc_now();
    let idx = PAINTS.fetch_add(1, SeqCst) + 1;
    let animating = ANIMATING.load(SeqCst);
    let seq = COMMIT_SEQ.load(SeqCst);
    let prev = PREV_SEQ_SEEN.swap(seq, SeqCst);
    if animating && idx > 1 && seq == prev {
        STALE_PAINTS.fetch_add(1, SeqCst);
    }

    let track = bounds.size.width - px(40.0);
    let frac = (seq % 240) as f32 / 240.0;
    let x = track * frac;
    let quad = Bounds::new(
        point(bounds.origin.x + x, bounds.origin.y + px(10.0)),
        size(px(40.0), px(20.0)),
    );
    window.paint_quad(fill(quad, rgb(0x3366cc)));

    if animating {
        window.request_animation_frame();
        TICK_TARGET.store(t0 as u64, SeqCst);
        TICKS_REQUESTED.fetch_add(1, SeqCst);
        if !TICK_PENDING.swap(true, SeqCst) {
            signal_notify(SRC_PAINT);
        }
    }
    let t1 = qpc_now();
    events().push(Ev {
        kind: K_PAINT,
        aux: animating as u32,
        t0,
        t1,
        v: seq,
    });
}

struct ProbeView;

impl Render for ProbeView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let seq = COMMIT_SEQ.load(SeqCst);
        div()
            .size_full()
            .child(
                canvas(
                    |_bounds, _window, _cx| (),
                    |bounds, _, window, _cx| paint_frame(bounds, window),
                )
                .w_full()
                .h(px(120.0)),
            )
            .child(format!("SR0-B frame-clock, commit {seq}"))
    }
}

fn launch(cx: &mut App, host: HostRef) {
    let bounds = Bounds::centered(None, size(px(640.), px(360.)), cx);
    let handle: WindowHandle<ProbeView> = match cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("SR0-B frame-clock".into()),
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
    let closed_sub = cx.on_window_closed(|_cx| {
        WINDOW_CLOSED.store(true, SeqCst);
        signal_notify(SRC_QUIT);
    });

    // Drain task. Its body runs as a GPUI foreground runnable, outside any
    // App or Window borrow. There is no timer: work happens only on wakes.
    cx.spawn(async move |cx: &mut AsyncApp| {
        let _keep_subscription_alive = closed_sub;
        LOOP_READY_CALLS.fetch_add(1, SeqCst);
        call(host.loop_ready, host.ctx);

        let mut close_issued = false;
        loop {
            WaitSignal.await;
            guarded_drain(host);

            if KICK.swap(false, SeqCst) {
                // Start the frame chain: the next vblank paints and requests more.
                let _ = cx.update(|cx| {
                    let _ = handle.update(cx, |_, _, cx| cx.notify());
                });
            }

            if TICK_PENDING.swap(false, SeqCst) {
                deliver_tick(host);
            }

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

// ---- DWM sampler (independent thread, desktop-global compositor counters) ----

fn dwm_sampler() {
    while SAMPLER_RUN.load(SeqCst) {
        let t0 = qpc_now();
        let ok = unsafe { DwmFlush().is_ok() };
        if PROBE_HWND.load(SeqCst) == 0 {
            unsafe { EnumWindows(find_own_window, 0) };
        }
        let hwnd = PROBE_HWND.load(SeqCst);
        let mut ti: DWM_TIMING_INFO = unsafe { std::mem::zeroed() };
        ti.cbSize = std::mem::size_of::<DWM_TIMING_INFO>() as u32;
        let rc = unsafe { DwmGetCompositionTimingInfo(HWND(hwnd as *mut c_void), &mut ti) };
        let t1 = qpc_now();
        let fast = (t1 - t0) < qpc_freq() / 1000;
        if fast {
            DWM_FAST_RETURNS.fetch_add(1, SeqCst);
        }
        let fg = (hwnd != 0 && unsafe { GetForegroundWindow() } as usize == hwnd) as u32;
        if rc.is_ok() {
            dwm_ring().push(DwmSample {
                qpc: t1,
                c_fd: ti.cFrameDisplayed,
                qpc_fd: ti.qpcFrameDisplayed,
                qpc_vblank: ti.qpcVBlank,
                c_refresh: ti.cRefresh,
                rate_num: ti.rateRefresh.uiNumerator,
                rate_den: ti.rateRefresh.uiDenominator,
                fast: fast as u32,
                fg,
            });
        }
        if !ok || fast {
            std::thread::sleep(Duration::from_millis(1));
        }
    }
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
        tick: raw.tick,
    };
    *HOST.lock().unwrap_or_else(|e| e.into_inner()) = Some(host);
    UI_THREAD.store(unsafe { GetCurrentThreadId() }, SeqCst);
    let _ = qpc_freq();
    let _ = events();
    let _ = dwm_ring();

    SAMPLER_RUN.store(true, SeqCst);
    if std::thread::Builder::new()
        .name("swr-dwm-sampler".into())
        .spawn(dwm_sampler)
        .is_err()
    {
        RUNNING.store(false, SeqCst);
        return SWR_ERR_WAKE;
    }

    if std::thread::Builder::new()
        .name("swr-wake-waiter".into())
        .spawn(move || waiter_loop(wake))
        .is_err()
    {
        RUNNING.store(false, SeqCst);
        return SWR_ERR_WAKE;
    }

    Application::new().run(move |cx: &mut App| launch(cx, host));
    SAMPLER_RUN.store(false, SeqCst);

    let rc = if OPEN_FAILED.load(SeqCst) { SWR_ERR_APP } else { SWR_OK };
    println!(
        "[sr0-b rust] loop_ready_calls={} drain_calls={} drain_reentry_violations={} thread_violations={} selftest_detected={} wake_signals={} wake_wait_failures={} paints={} stale_paints={} ticks_requested={} ticks_delivered={} commits={} window_closed_events={} quit_requests={} open_failed={} run_rc={}",
        LOOP_READY_CALLS.load(SeqCst),
        DRAIN_CALLS.load(SeqCst),
        DRAIN_VIOLATIONS.load(SeqCst),
        THREAD_VIOLATIONS.load(SeqCst),
        SELFTEST_DETECTED.load(SeqCst),
        WAKE_SIGNALS.load(SeqCst),
        WAKE_WAIT_FAILURES.load(SeqCst),
        PAINTS.load(SeqCst),
        STALE_PAINTS.load(SeqCst),
        TICKS_REQUESTED.load(SeqCst),
        TICKS_DELIVERED.load(SeqCst),
        COMMITS_SUBMITTED.load(SeqCst),
        WINDOW_CLOSED_EVENTS.load(SeqCst),
        QUIT_REQUESTS.load(SeqCst),
        OPEN_FAILED.load(SeqCst),
        rc,
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
    pub tick: Option<extern "C" fn(*mut c_void, u64)>,
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

/// Process-wide timer resolution (A/B variable). Returns the timeBeginPeriod result.
#[no_mangle]
pub extern "C" fn swr_set_timer_resolution(ms: u32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let rc = unsafe { timeBeginPeriod(ms) };
        TIMER_RES_RC.store(rc, SeqCst);
        rc as i32
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
        signal_notify(SRC_QUIT);
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Thread-safe. Starting animation kicks the drain task, which invalidates the
/// root view; each paint while animating then requests the next vblank.
#[no_mangle]
pub extern "C" fn swr_set_animating(on: i32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let want = on != 0;
        let was = ANIMATING.swap(want, SeqCst);
        if want && !was {
            KICK.store(true, SeqCst);
            signal_notify(SRC_KICK);
        }
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Thread-safe. The next paint shows the highest committed sequence.
#[no_mangle]
pub extern "C" fn swr_submit_commit(seq: u64) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        COMMIT_SEQ.fetch_max(seq, SeqCst);
        COMMITS_SUBMITTED.fetch_add(1, SeqCst);
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

#[no_mangle]
pub extern "C" fn swr_paints() -> u64 {
    catch_unwind(|| PAINTS.load(SeqCst)).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn swr_ticks_requested() -> u64 {
    catch_unwind(|| TICKS_REQUESTED.load(SeqCst)).unwrap_or(0)
}

/// Called only from inside a drain callback. Re-enters the guarded drain and
/// checks that it is refused. Returns 1 when the guard refused re-entry, 0 when
/// it did not, -1 when not called inside a drain.
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

fn kind_name(k: u32) -> &'static str {
    match k {
        K_WAKE => "WAKE",
        K_DRAIN => "DRAIN",
        K_PAINT => "PAINT",
        K_TICK => "TICK",
        _ => "?",
    }
}

/// Writes events.csv and dwm.csv into `dir` (must exist).
#[no_mangle]
pub extern "C" fn swr_dump(dir: *const c_char) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if dir.is_null() {
            return SWR_ERR_ARGS;
        }
        let dir = match unsafe { CStr::from_ptr(dir) }.to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return SWR_ERR_ARGS,
        };
        let mut ev = String::from("kind,aux,t0_qpc,t1_qpc,v\n");
        for e in events().snapshot() {
            let _ = writeln!(ev, "{},{},{},{},{}", kind_name(e.kind), e.aux, e.t0, e.t1, e.v);
        }
        let mut dw = String::from("qpc_sample,c_frame_displayed,qpc_frame_displayed,qpc_vblank,c_refresh,rate_num,rate_den,fast,fg\n");
        for s in dwm_ring().snapshot() {
            let _ = writeln!(
                dw,
                "{},{},{},{},{},{},{},{},{}",
                s.qpc, s.c_fd, s.qpc_fd, s.qpc_vblank, s.c_refresh, s.rate_num, s.rate_den, s.fast, s.fg
            );
        }
        let mut meta = String::new();
        let _ = writeln!(meta, "qpc_freq={}", qpc_freq());
        let _ = writeln!(meta, "event_drops={} dwm_drops={}", events().dropped(), dwm_ring().dropped());
        let _ = writeln!(meta, "timer_resolution_rc={}", TIMER_RES_RC.load(SeqCst) as i32);
        let _ = writeln!(meta, "dwm_fast_returns={}", DWM_FAST_RETURNS.load(SeqCst));
        if std::fs::write(format!("{dir}\\events.csv"), ev).is_err()
            || std::fs::write(format!("{dir}\\dwm.csv"), dw).is_err()
            || std::fs::write(format!("{dir}\\meta.txt"), meta).is_err()
        {
            return SWR_ERR_APP;
        }
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return f64::NAN;
    }
    let rank = ((sorted.len() as f64) * p).ceil().max(1.0) as usize;
    sorted[rank.min(sorted.len()) - 1]
}

fn stats_line(label: &str, mut v: Vec<f64>) -> String {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    format!(
        "{label} n={} p50={:.3} p95={:.3} p99={:.3} max={:.3}",
        v.len(),
        pct(&v, 0.50),
        pct(&v, 0.95),
        pct(&v, 0.99),
        v.last().copied().unwrap_or(f64::NAN)
    )
}

/// Prints frame-clock statistics and stall attribution. Call after swr_run.
#[no_mangle]
pub extern "C" fn swr_report(enq: *const i64, exec: *const i64, n: u32, wins: *const i64) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if enq.is_null() || exec.is_null() || wins.is_null() {
            return SWR_ERR_ARGS;
        }
        let enq = unsafe { std::slice::from_raw_parts(enq, n as usize) };
        let exec = unsafe { std::slice::from_raw_parts(exec, n as usize) };
        let w = unsafe { std::slice::from_raw_parts(wins, 6) };
        let (ws, we, ia0, ia1, ib0, ib1) = (w[0], w[1], w[2], w[3], w[4], w[5]);
        let freq = qpc_freq() as f64;
        let to_ms = |ticks: i64| ticks as f64 * 1000.0 / freq;
        let in_win = |t: i64, a: i64, b: i64| t >= a && t <= b;

        let ev = events().snapshot();
        let dwm = dwm_ring().snapshot();

        // Monitor refresh rate (EnumDisplaySettings) and DWM rate.
        let mut dm: DEVMODEW = unsafe { std::mem::zeroed() };
        dm.dmSize = std::mem::size_of::<DEVMODEW>() as u16;
        let edm = unsafe { EnumDisplaySettingsW(PCWSTR::null(), ENUM_CURRENT_SETTINGS, &mut dm) };
        let dwm_hz = dwm
            .iter()
            .rev()
            .find(|s| s.rate_den != 0)
            .map(|s| s.rate_num as f64 / s.rate_den as f64)
            .unwrap_or(f64::NAN);
        println!(
            "[frame-clock] monitor enum_display_hz={} (ok={}) dwm_rate_hz={:.3} qpc_freq={} dwm_samples={} dwm_fast_returns={} event_count={} event_drops={}",
            dm.dmDisplayFrequency,
            edm.as_bool(),
            dwm_hz,
            qpc_freq(),
            dwm.len(),
            DWM_FAST_RETURNS.load(SeqCst),
            ev.len(),
            events().dropped(),
        );

        // Presented-frame intervals from compositor counters inside the workload window.
        let mut pres = Vec::new();
        let mut pres_in_win = 0u64;
        let mut jumps = 0u64;
        let (mut idle_a_disp, mut idle_b_disp) = (0u64, 0u64);
        let mut last: Option<(u64, u64)> = None;
        for s in &dwm {
            let q = s.qpc_fd as i64;
            match last {
                None => last = Some((s.c_fd, s.qpc_fd)),
                Some((c, prev_q)) if s.c_fd != c => {
                    let d = s.c_fd.wrapping_sub(c);
                    if d == 1 && s.qpc_fd > prev_q && in_win(q, ws, we) {
                        pres.push(to_ms((s.qpc_fd - prev_q) as i64));
                    }
                    if d > 1 {
                        jumps += 1;
                    }
                    if in_win(q, ws, we) {
                        pres_in_win += d;
                    }
                    if in_win(q, ia0, ia1) {
                        idle_a_disp += d;
                    }
                    if in_win(q, ib0, ib1) {
                        idle_b_disp += d;
                    }
                    last = Some((s.c_fd, s.qpc_fd));
                }
                _ => {}
            }
        }
        println!(
            "[frame-clock] {}",
            stats_line("presented_interval_ms(dwm)", pres.clone())
        );
        let fg_samples = dwm.iter().filter(|s| s.fg == 1).count();
        println!("[frame-clock] dwm_samples_foreground={}/{} probe_hwnd_found={}", fg_samples, dwm.len(), PROBE_HWND.load(SeqCst) != 0);
        println!(
            "[frame-clock] presented_frames_in_workload={} dwm_count_jumps={} dwm_displayed_in_idle_A={} dwm_displayed_in_idle_B={} (desktop-global counters)",
            pres_in_win, jumps, idle_a_disp, idle_b_disp
        );

        // Paint intervals during animation inside the workload window.
        let mut paints: Vec<&Ev> = ev
            .iter()
            .filter(|e| e.kind == K_PAINT && e.aux == 1 && in_win(e.t0, ws, we))
            .collect();
        paints.sort_by_key(|e| e.t0);
        let paint_iv: Vec<f64> = paints.windows(2).map(|p| to_ms(p[1].t0 - p[0].t0)).collect();
        let paint_dur: Vec<f64> = paints.iter().map(|e| to_ms(e.t1 - e.t0)).collect();
        println!("[frame-clock] {}", stats_line("paint_interval_ms(rust)", paint_iv));
        println!("[frame-clock] {}", stats_line("paint_duration_ms(rust)", paint_dur));
        let idle_paints = |a: i64, b: i64| ev.iter().filter(|e| e.kind == K_PAINT && in_win(e.t0, a, b)).count();
        println!(
            "[frame-clock] paints_in_workload={} paints_idle_A={} paints_idle_B={}",
            paints.len(),
            idle_paints(ia0, ia1),
            idle_paints(ib0, ib1)
        );
        let ticks_idle = ev.iter().filter(|e| e.kind == K_TICK && (in_win(e.t0, ia0, ia1) || in_win(e.t0, ib0, ib1))).count();
        println!("[frame-clock] ticks_idle_A_or_B={ticks_idle}");

        // Stall attribution: every job whose enqueue->execute latency exceeds 16.7 ms.
        let busy: Vec<(i64, i64, u32)> = {
            let mut v: Vec<(i64, i64, u32)> = ev
                .iter()
                .filter(|e| e.kind == K_DRAIN || e.kind == K_PAINT || e.kind == K_TICK)
                .map(|e| (e.t0, e.t1, e.kind))
                .collect();
            v.sort_by_key(|x| x.0);
            v
        };
        let wakes: Vec<&Ev> = ev.iter().filter(|e| e.kind == K_WAKE).collect();
        let mut stall_jobs = 0usize;
        let mut printed = 0usize;
        let mut causes: Vec<String> = Vec::new();
        for i in 0..(n as usize) {
            let (a, b) = (enq[i], exec[i]);
            if b < a {
                continue;
            }
            let lat_ms = to_ms(b - a);
            if lat_ms <= STALL_THRESHOLD_MS {
                continue;
            }
            stall_jobs += 1;
            if printed >= MAX_STALL_BLOCKS {
                continue;
            }
            printed += 1;

            // Union of busy intervals clipped to [a, b], and the largest uncovered gap.
            let mut covered = 0i64;
            let mut gaps: Vec<(i64, i64)> = Vec::new();
            let mut cursor = a;
            let mut per_kind = [0i64; 5];
            let mut overlaps: Vec<(i64, i64, u32)> = Vec::new();
            for &(s, e, k) in &busy {
                if e < a || s > b {
                    continue;
                }
                let cs = s.max(a);
                let ce = e.min(b);
                per_kind[k as usize] += ce - cs;
                overlaps.push((s, e, k));
                if cs > cursor {
                    gaps.push((cursor, cs));
                }
                if ce > cursor {
                    covered += ce - cursor.max(cs);
                    cursor = ce;
                }
            }
            if cursor < b {
                gaps.push((cursor, b));
            }
            let uncovered = (b - a) - covered;
            let largest_gap = gaps.iter().copied().max_by_key(|(s, e)| e - s);

            let first_wake = wakes.iter().filter(|e| e.t0 >= a).map(|e| e.t0).min();
            let wake_delay_ms = first_wake.map(|t| to_ms(t - a)).unwrap_or(f64::NAN);
            let first_drain_delay_ms = busy
                .iter()
                .filter(|x| x.2 == K_DRAIN && x.0 >= a)
                .map(|x| x.0)
                .min()
                .map(|t| to_ms(t - a))
                .unwrap_or(f64::NAN);

            let unc_ms = to_ms(uncovered);
            let paint_ms = to_ms(per_kind[K_PAINT as usize]);
            let drain_ms = to_ms(per_kind[K_DRAIN as usize]);
            let cause = if unc_ms >= 0.5 * lat_ms {
                let (gs, ge) = largest_gap.unwrap_or((a, a));
                format!(
                    "UI thread in no instrumented work for {:.3} ms of {:.3} ms (largest gap {:.3} ms at +{:.3} ms): blocked outside GPUI drain/paint/tick, e.g. DXGI Present, modal loop, or non-drain gpui message handling",
                    unc_ms, lat_ms, to_ms(ge - gs), to_ms(gs - a)
                )
            } else if paint_ms >= 0.5 * lat_ms {
                format!("paint-bound: paint {:.3} ms of {:.3} ms", paint_ms, lat_ms)
            } else if first_drain_delay_ms >= 0.5 * lat_ms {
                format!(
                    "not drained: first drain started {:.3} ms after enqueue (waiter wake delay {:.3} ms)",
                    first_drain_delay_ms, wake_delay_ms
                )
            } else {
                format!("drain-bound: drain {:.3} ms of {:.3} ms", drain_ms, lat_ms)
            };
            causes.push(cause.clone());

            let mut block = String::new();
            let _ = writeln!(
                block,
                "STALL job={} enq_rel_ms=0.000 latency_ms={:.3} wake_delay_ms={:.3} first_drain_delay_ms={:.3} drain_ms={:.3} paint_ms={:.3} tick_ms={:.3} uncovered_ms={:.3}",
                i, lat_ms, wake_delay_ms, first_drain_delay_ms, drain_ms, paint_ms, to_ms(per_kind[K_TICK as usize]), unc_ms
            );
            let _ = writeln!(block, "  cause: {cause}");
            let mut shown = 0;
            for w in wakes.iter().filter(|e| in_win(e.t0, a, b)).take(6) {
                let _ = writeln!(block, "  WAKE src={} at +{:.3} ms", w.aux, to_ms(w.t0 - a));
                shown += 1;
            }
            for (s, e, k) in overlaps.iter().take(12) {
                let _ = writeln!(
                    block,
                    "  {} [+{:.3}, +{:.3}] ms len={:.3} ms",
                    kind_name(*k),
                    to_ms(s - a),
                    to_ms(e - a),
                    to_ms(e - s)
                );
                shown += 1;
            }
            if overlaps.len() > 12 {
                let _ = writeln!(block, "  ... {} more busy intervals", overlaps.len() - 12);
            }
            for (gs, ge) in gaps.iter().filter(|(s, e)| e - s > 0).take(6) {
                let _ = writeln!(block, "  GAP (no drain/paint/tick) [+{:.3}, +{:.3}] ms len={:.3} ms", to_ms(gs - a), to_ms(ge - a), to_ms(ge - gs));
            }
            let _ = shown;
            print!("{block}");
        }
        println!(
            "[frame-clock] job_latency_over_{:.1}ms={} of {}",
            STALL_THRESHOLD_MS, stall_jobs, n
        );
        if stall_jobs > printed {
            println!("[frame-clock] ... {} further stall blocks not printed", stall_jobs - printed);
        }
        let mut tally: std::collections::BTreeMap<String, usize> = Default::default();
        for c in &causes {
            let key = c.split(':').next().unwrap_or("").split(" for ").next().unwrap_or("").to_string();
            *tally.entry(key).or_default() += 1;
        }
        println!("[frame-clock] stall_cause_tally={:?}", tally);
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}
