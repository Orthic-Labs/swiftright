//! Paint pacing: when, inside each display refresh, the window is painted.
//!
//! GPUI on Windows draws from a WM_PAINT that its vsync thread provokes (`RedrawWindow`) after every `DwmFlush()` return, that
//! is right after each DWM composition pass. What is presented is composed by DWM for the vblank after next: DWM takes the
//! newest frame whose GPU work (render plus, on a hybrid laptop, the cross-adapter copy of the whole back buffer) is complete
//! when its next composition starts, and shows it at the vblank after that. R10 evidence (PresentMon, Dell hybrid laptop,
//! 2400x1396 back buffer, 60 Hz, 20261009-233129-full r1, phase = ms after the last vblank):
//!   * presents land two vblanks later (k = 2, the fast case) exactly when `present phase + msUntilRenderComplete` is under
//!     one refresh period (16.67 ms); otherwise three vblanks later (k = 3) and the previous frame is not replaced in time:
//!     a missed vblank in the displayed stream;
//!   * `msUntilRenderComplete` is 6.1 ms at the median on that machine (the copy of 13 MB over PCIe), p90 7.4, p99 11.1;
//!   * so a present later than about 5-7 ms into the period misses its vblank whenever the GPU side has a normal hiccup.
//! The first pacing version waited a fixed 5.5 ms after the (late-delivered) WM_PAINT, because `DwmGetCompositionTimingInfo`
//! fails on this host (0x88980090 for a NULL and for any window handle: the timing API wants a queued present) and the
//! fallback timer started from the WM_PAINT arrival, which itself jitters by several ms when the UI thread is busy: a quarter
//! of the presents landed after the deadline.
//!
//! Now the pacing thread owns the clock. It loops on `DwmFlush()` itself (the very signal GPUI's vsync thread waits for), so
//! each return is a composition edge with a known QPC time; at `edge + phase` it posts WM_SWR_PAINT to the window. The WM_PAINT
//! GPUI's vsync thread provokes is swallowed (window validated); the WM_SWR_PAINT handler invalidates and updates the window,
//! which delivers one WM_PAINT to GPUI. One paint per period, at a phase chosen from the edge instead of from a message that
//! may be late. If the previous paint message has not been handled when the next edge arrives, no second one is queued.
//!
//! Every failure fails open: no timer / no edges for a few periods / a paint message that never arrives -> WM_PAINT goes to
//! GPUI at once, as before.
//!
//! `SWR_PAINT_PHASE_MS` (environment, read once): the paint phase in milliseconds after the composition edge. DEFAULT: 0 = OFF.
//! Pacing is off by default because it measured worse on the Dell (R10, interleaved A/B, same session, median of 6 sub-runs): GPUI's own WM_PAINT arrives ~1 ms
//! after the composition edge, the earliest a paint can sensibly start, and every millisecond of added delay is a millisecond less for the GPU side
//! (`msUntilRenderComplete` p99 11 ms, bursts to 14 ms) and for UI-thread collisions (a 3 ms key handler or a 4-6 ms host drain landing on the paint). The later a
//! frame is presented, the earlier the next input is displayed (a frame is displayed two vblanks after the one it was presented in), but the input to display
//! latency limit (50 ms at p95) is met without pacing on this machine. The mechanism stays as an opt-in for hosts whose GPU path is faster than 6 ms
//! (set the phase to about `16.7 - msUntilRenderComplete p99 - 2` ms). When the trace is on (`SWR_FRAME_LOG`) the edge thread also runs with pacing
//! off, so the edges are recorded.

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering::SeqCst};

use crate::rt::*;
use crate::trace;

/// WM_APP + 0x5A1: posted by the pacing thread when the paint is due; wparam = the edge count.
pub const WM_SWR_PAINT: u32 = 0x8000 + 0x5A1;

/// Default: pacing off (see the header). With a phase of p ms the present call lands about 0.9 (edge after vblank) + p + 0.8 (GPUI draw to Present)
/// ms into the period, and the GPU has the rest of the 16.67 ms to finish.
const DEFAULT_PHASE_US: u64 = 0;
/// No edge for this many periods: the thread is considered dead and WM_PAINT is passed through.
const STALE_PERIODS: i64 = 6;
/// A posted paint message not handled for this many periods is considered lost and may be posted again.
const PENDING_PERIODS: i64 = 4;

#[link(name = "user32")]
extern "system" {
    fn ValidateRect(hwnd: *mut c_void, rect: *const c_void) -> i32;
    fn InvalidateRect(hwnd: *mut c_void, rect: *const c_void, erase: i32) -> i32;
    fn UpdateWindow(hwnd: *mut c_void) -> i32;
    fn PostMessageW(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn CreateWaitableTimerExW(attrs: *mut c_void, name: *const u16, flags: u32, access: u32) -> *mut c_void;
    fn SetWaitableTimer(h: *mut c_void, due: *const i64, period: i32, cb: *mut c_void, arg: *mut c_void, resume: i32) -> i32;
    fn CloseHandle(h: *mut c_void) -> i32;
    fn GetCurrentThread() -> *mut c_void;
    fn SetThreadPriority(h: *mut c_void, p: i32) -> i32;
}

#[link(name = "dwmapi")]
extern "system" {
    fn DwmFlush() -> i32;
}

/// Target phase in microseconds after the edge; 0 = pacing off.
static PHASE_US: AtomicU64 = AtomicU64::new(0);
/// QPC time of the latest composition edge (0 until the first), and the smoothed period in QPC ticks.
static EDGE_QPC: AtomicI64 = AtomicI64::new(0);
static PERIOD_QPC: AtomicI64 = AtomicI64::new(0);
/// QPC time the pending paint message was posted (0 = none pending).
static PENDING_SINCE: AtomicI64 = AtomicI64::new(0);
/// True while our own paint is being delivered (the WM_PAINT it causes goes to GPUI untouched).
static PASS: AtomicBool = AtomicBool::new(false);
static STOP: AtomicBool = AtomicBool::new(false);

pub static EDGES: AtomicU64 = AtomicU64::new(0);
pub static POSTED: AtomicU64 = AtomicU64::new(0);
pub static SKIPPED_PENDING: AtomicU64 = AtomicU64::new(0);
pub static EXPIRED: AtomicU64 = AtomicU64::new(0);
pub static SWALLOWED: AtomicU64 = AtomicU64::new(0);
pub static PASSED_STALE: AtomicU64 = AtomicU64::new(0);
pub static NO_WAIT_EDGES: AtomicU64 = AtomicU64::new(0);

pub fn phase_us() -> u64 {
    PHASE_US.load(SeqCst)
}

/// Mean composition period in microseconds as measured by the edge thread (0 if none).
pub fn period_us() -> u64 {
    let p = PERIOD_QPC.load(SeqCst);
    if p <= 0 {
        0
    } else {
        (p as u128 * 1_000_000 / qpc_freq() as u128) as u64
    }
}

/// QPC time of the latest composition edge, 0 if none yet.
pub fn latest_edge() -> i64 {
    EDGE_QPC.load(SeqCst)
}

fn ticks_from_us(us: u64) -> i64 {
    (us as u128 * qpc_freq() as u128 / 1_000_000) as i64
}

/// Starts the edge thread for the window (UI thread, once, after the window exists).
pub fn init(hwnd: *mut c_void) {
    trace::init();
    let phase = match std::env::var("SWR_PAINT_PHASE_MS") {
        Ok(v) => v.trim().parse::<f64>().map(|ms| (ms * 1000.0).max(0.0) as u64).unwrap_or(DEFAULT_PHASE_US),
        Err(_) => DEFAULT_PHASE_US,
    };
    if phase == 0 {
        eprintln!("[swiftright-render] paint pacing off (SWR_PAINT_PHASE_MS=0)");
        if !trace::enabled() {
            return;
        }
    }
    let wnd = hwnd as usize;
    // 60 Hz until measured.
    PERIOD_QPC.store(ticks_from_us(16_667), SeqCst);
    let spawned = std::thread::Builder::new().name("swr-paint-edge".into()).spawn(move || edge_thread(wnd, phase));
    if spawned.is_err() {
        eprintln!("[swiftright-render] paint pacing off (edge thread did not start)");
        return;
    }
    PHASE_US.store(phase, SeqCst);
    if phase != 0 {
        eprintln!("[swiftright-render] paint pacing on: paint {phase} us after each DWM composition edge");
    }
}

/// Waits `ticks` QPC ticks on the high-resolution timer (returns at once for <= 0 or a timer that cannot be armed).
fn wait_ticks(timer: *mut c_void, ticks: i64) {
    if timer.is_null() || ticks <= 0 {
        return;
    }
    let due: i64 = -((ticks as i128 * 10_000_000 / qpc_freq() as i128).max(1) as i64); // relative, 100 ns units
    let armed = unsafe { SetWaitableTimer(timer, &due, 0, std::ptr::null_mut(), std::ptr::null_mut(), 0) } != 0;
    if armed {
        unsafe { WaitForSingleObject(timer, u32::MAX) };
    }
}

/// The edge thread: DwmFlush loop, one composition edge per return; posts the paced paint `phase_us` after each edge.
fn edge_thread(hwnd: usize, phase_us: u64) {
    // THREAD_PRIORITY_TIME_CRITICAL: the thread sleeps nearly always; it must run the moment its edge or timer fires.
    unsafe { SetThreadPriority(GetCurrentThread(), 15) };
    // CREATE_WAITABLE_TIMER_HIGH_RESOLUTION (0x2), TIMER_ALL_ACCESS (0x1F0003): the default 15.6 ms timer cannot place a paint.
    let timer = unsafe { CreateWaitableTimerExW(std::ptr::null_mut(), std::ptr::null(), 0x2, 0x1F0003) };
    if timer.is_null() && phase_us != 0 {
        eprintln!("[swiftright-render] paint pacing off (no high-resolution timer)");
        PHASE_US.store(0, SeqCst);
    }
    let freq = qpc_freq() as i64;
    let mut prev_edge: i64 = 0;
    let mut n: u64 = 0;
    while !STOP.load(SeqCst) && !SHUTDOWN.load(SeqCst) && !WINDOW_CLOSED.load(SeqCst) {
        let t_wait = qpc_now();
        let rc = unsafe { DwmFlush() };
        let mut now = qpc_now();
        let period = PERIOD_QPC.load(SeqCst);
        // DwmFlush returns at once when nothing is composed (occluded window, display asleep, DWM busy): pace by the clock.
        if rc < 0 || (now - t_wait) < freq / 1000 {
            NO_WAIT_EDGES.fetch_add(1, SeqCst);
            let due = if prev_edge != 0 { prev_edge + period } else { now + period };
            wait_ticks(timer, due - now);
            now = qpc_now();
        } else if prev_edge != 0 {
            let d = now - prev_edge;
            if d > period / 2 && d < period * 3 / 2 {
                PERIOD_QPC.store((period * 15 + d) / 16, SeqCst);
            }
        }
        prev_edge = now;
        EDGE_QPC.store(now, SeqCst);
        EDGES.fetch_add(1, SeqCst);
        n += 1;
        if n % 60 == 0 {
            trace::memory_sample();
        }
        let phase = PHASE_US.load(SeqCst);
        let mut post_t = 0i64;
        if phase != 0 {
            wait_ticks(timer, now + ticks_from_us(phase) - qpc_now());
            let since = PENDING_SINCE.load(SeqCst);
            let t = qpc_now();
            if since != 0 && t - since < PENDING_PERIODS * PERIOD_QPC.load(SeqCst) {
                SKIPPED_PENDING.fetch_add(1, SeqCst);
            } else {
                if since != 0 {
                    EXPIRED.fetch_add(1, SeqCst);
                }
                PENDING_SINCE.store(t, SeqCst);
                if unsafe { PostMessageW(hwnd as *mut c_void, WM_SWR_PAINT, n as usize, 0) } != 0 {
                    POSTED.fetch_add(1, SeqCst);
                    post_t = t;
                } else {
                    PENDING_SINCE.store(0, SeqCst);
                }
            }
        }
        trace::edge(now, post_t);
    }
    if !timer.is_null() {
        unsafe { CloseHandle(timer) };
    }
}

/// True when the edge thread is alive: an edge within the last STALE_PERIODS periods.
fn edge_fresh(now: i64) -> bool {
    let e = EDGE_QPC.load(SeqCst);
    e != 0 && now - e < STALE_PERIODS * PERIOD_QPC.load(SeqCst).max(1)
}

/// Called for a WM_PAINT that is about to reach GPUI. True: the paint was swallowed (window validated; the paced
/// WM_SWR_PAINT paints instead). False: paint now (pacing off, our own paint, shutdown, or no edge clock).
pub fn defer_paint(hwnd: *mut c_void) -> bool {
    let phase_us = PHASE_US.load(SeqCst);
    let now = qpc_now();
    trace::span(trace::K_WM_PAINT, now, now);
    if phase_us == 0 || PASS.load(SeqCst) || SHUTDOWN.load(SeqCst) || WINDOW_CLOSED.load(SeqCst) {
        return false;
    }
    if !edge_fresh(now) {
        PASSED_STALE.fetch_add(1, SeqCst);
        return false;
    }
    SWALLOWED.fetch_add(1, SeqCst);
    unsafe { ValidateRect(hwnd, std::ptr::null()) };
    true
}

/// WM_SWR_PAINT: the paint is due. Invalidates and updates the window now, which sends GPUI its WM_PAINT.
pub fn run_deferred_paint(hwnd: *mut c_void) {
    PENDING_SINCE.store(0, SeqCst);
    if SHUTDOWN.load(SeqCst) || WINDOW_CLOSED.load(SeqCst) {
        return;
    }
    let t0 = qpc_now();
    PASS.store(true, SeqCst);
    unsafe {
        InvalidateRect(hwnd, std::ptr::null(), 0);
        UpdateWindow(hwnd);
    }
    PASS.store(false, SeqCst);
    trace::span(trace::K_HANDLER, t0, qpc_now());
}

/// Ends the edge thread (window closed / shutdown).
pub fn stop() {
    STOP.store(true, SeqCst);
}
