//! Paint pacing: when, inside each display refresh, the window is painted.
//!
//! GPUI on Windows draws from a WM_PAINT that its vsync thread provokes (`RedrawWindow`) right after every DWM
//! composition, so every frame is painted at the very start of its refresh period. DWM has by then already picked the
//! frame it will show at the next vblank, so what is painted now reaches the display at the vblank after that: two
//! refresh periods later. PresentMon on the SR0 workload (R10, 60 Hz): `msUntilDisplayed` 31.4 ms for the bulk of
//! presents, and an input that landed any time after a paint waited for the *next* period's paint on top (input to
//! visible p50 44 ms against a 50 ms p95 limit; the architecture floor of that scheme is 50 ms at p95).
//!
//! DWM latches a presented frame for the next-but-one vblank as long as it is presented before a point late in the period
//! (measured here: presents up to ~12 ms into a 16.7 ms period still showed two vblanks later; later ones one more). So a
//! frame painted at ~7 ms into the period shows at exactly the same vblank as one painted at 1 ms, and contains whatever
//! the host committed in between: a keystroke that arrives up to the paint point is in this period's frame instead of the
//! next one's, which is up to a whole refresh period (16.7 ms) earlier on screen.
//!
//! The mechanism is a window subclass hook (view.rs `ime_subclass_proc`): the WM_PAINT GPUI is about to receive at the
//! start of a period is swallowed (the window validated, so Windows does not repeat it), a high-resolution timer thread
//! posts WM_SWR_PAINT at the target phase of the same period, and that handler paints (invalidate + update-now), which
//! delivers the WM_PAINT to GPUI. One paint per period, so nothing is presented and then replaced within a period.
//!
//! The phase comes from DWM (`DwmGetCompositionTimingInfo`: QPC time of the latest vblank and the refresh period). Every
//! failure fails open: no timer, no DWM timing that makes sense, a deferral that was never delivered, or a WM_PAINT that
//! arrives already late in its period paint at once, as before.
//!
//! `SWR_PAINT_PHASE_MS` (environment, read once): the target phase in milliseconds, default 7; 0 turns pacing off.

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering::SeqCst};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;

use crate::rt::*;

/// WM_APP + 0x5A1: posted by the timer thread when the deferred paint is due.
pub const WM_SWR_PAINT: u32 = 0x8000 + 0x5A1;

const DEFAULT_PHASE_US: u64 = 7_000;
/// Used when DWM gives no usable vblank time: paint this long after the WM_PAINT arrived (which is ~1 ms into the period).
const FALLBACK_WAIT_NS: u64 = 5_500_000;
/// Below this remaining wait the paint is simply done now.
const MIN_WAIT_NS: u64 = 400_000;
/// A deferral older than this is abandoned: the next WM_PAINT paints at once.
const DEFER_EXPIRY_NS: u64 = 30_000_000;

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
}

#[link(name = "dwmapi")]
extern "system" {
    fn DwmGetCompositionTimingInfo(hwnd: *mut c_void, info: *mut DwmTimingInfo) -> i32;
}

/// The head of DWM_TIMING_INFO (dwmapi.h) and enough zeroed tail to make the struct its full 320 bytes on x64; the API
/// checks `cbSize` and refuses a mismatch, which then just turns the DWM phase off (the fixed fallback wait applies).
#[repr(C)]
struct DwmTimingInfo {
    cb_size: u32,
    rate_refresh: [u32; 2],
    qpc_refresh_period: u64,
    rate_compose: [u32; 2],
    qpc_vblank: u64,
    tail: [u64; 35],
}
const _: () = assert!(std::mem::size_of::<DwmTimingInfo>() == 320);

/// Target phase in microseconds; 0 = pacing off.
static PHASE_US: AtomicU64 = AtomicU64::new(0);
static PENDING: AtomicBool = AtomicBool::new(false);
static PENDING_SINCE: AtomicI64 = AtomicI64::new(0);
/// True while our own paint is being delivered (the WM_PAINT it causes goes to GPUI untouched).
static PASS: AtomicBool = AtomicBool::new(false);
static TX: Mutex<Option<Sender<u64>>> = Mutex::new(None);
static DWM_FAILED: AtomicBool = AtomicBool::new(false);

pub static DEFERRED: AtomicU64 = AtomicU64::new(0);
pub static PASSED_THROUGH: AtomicU64 = AtomicU64::new(0);
pub static FAILED_OPEN: AtomicU64 = AtomicU64::new(0);
pub static FALLBACK_WAITS: AtomicU64 = AtomicU64::new(0);

pub fn phase_us() -> u64 {
    PHASE_US.load(SeqCst)
}

/// Starts pacing for the window (UI thread, once, after the window exists).
pub fn init(hwnd: *mut c_void) {
    let phase = match std::env::var("SWR_PAINT_PHASE_MS") {
        Ok(v) => v.trim().parse::<f64>().map(|ms| (ms * 1000.0).max(0.0) as u64).unwrap_or(DEFAULT_PHASE_US),
        Err(_) => DEFAULT_PHASE_US,
    };
    if phase == 0 {
        eprintln!("[swiftright-render] paint pacing off (SWR_PAINT_PHASE_MS=0)");
        return;
    }
    let (tx, rx) = channel::<u64>();
    let wnd = hwnd as usize;
    let spawned = std::thread::Builder::new().name("swr-paint-timer".into()).spawn(move || timer_thread(rx, wnd));
    if spawned.is_err() {
        eprintln!("[swiftright-render] paint pacing off (timer thread did not start)");
        return;
    }
    *TX.lock().unwrap_or_else(|e| e.into_inner()) = Some(tx);
    PHASE_US.store(phase, SeqCst);
    eprintln!("[swiftright-render] paint pacing on: paint {} us after each vblank", phase);
}

/// The timer thread: a high-resolution waitable timer (the default timer resolution of 15.6 ms cannot place a paint).
/// With no such timer, pacing is switched off and the senders find the channel closed.
fn timer_thread(rx: Receiver<u64>, hwnd: usize) {
    // CREATE_WAITABLE_TIMER_HIGH_RESOLUTION (0x2), TIMER_ALL_ACCESS (0x1F0003).
    let timer = unsafe { CreateWaitableTimerExW(std::ptr::null_mut(), std::ptr::null(), 0x2, 0x1F0003) };
    if timer.is_null() {
        PHASE_US.store(0, SeqCst);
        eprintln!("[swiftright-render] paint pacing off (no high-resolution timer)");
        return;
    }
    while let Ok(wait_ns) = rx.recv() {
        let due: i64 = -((wait_ns / 100).max(1) as i64); // relative, 100 ns units
        let armed = unsafe { SetWaitableTimer(timer, &due, 0, std::ptr::null_mut(), std::ptr::null_mut(), 0) } != 0;
        if armed {
            unsafe { WaitForSingleObject(timer, u32::MAX) };
        }
        // Post even if the timer could not be armed: the paint is then early instead of lost.
        unsafe { PostMessageW(hwnd as *mut c_void, WM_SWR_PAINT, 0, 0) };
    }
    unsafe { CloseHandle(timer) };
}

/// Nanoseconds since the latest vblank, from DWM; None when DWM gives nothing usable.
pub fn vblank_phase_ns(now: i64) -> Option<u64> {
    if DWM_FAILED.load(SeqCst) {
        return None;
    }
    let mut info = DwmTimingInfo {
        cb_size: std::mem::size_of::<DwmTimingInfo>() as u32,
        rate_refresh: [0; 2],
        qpc_refresh_period: 0,
        rate_compose: [0; 2],
        qpc_vblank: 0,
        tail: [0; 35],
    };
    let hr = unsafe { DwmGetCompositionTimingInfo(std::ptr::null_mut(), &mut info) };
    if hr < 0 || info.qpc_refresh_period == 0 || info.qpc_vblank == 0 {
        // A refusal is permanent (wrong struct size, no DWM): do not ask again every frame.
        DWM_FAILED.store(true, SeqCst);
        return None;
    }
    let elapsed = now - info.qpc_vblank as i64;
    if elapsed < 0 {
        return None;
    }
    let period = info.qpc_refresh_period as i64;
    // The vblank time can be a few periods old if DWM has not updated it; a modulo gives the phase either way.
    Some(qpc_to_ns(elapsed % period))
}

/// Called for a WM_PAINT that is about to reach GPUI. True: the paint was deferred (window validated, nothing for GPUI to
/// do now). False: paint now.
pub fn defer_paint(hwnd: *mut c_void) -> bool {
    let phase_us = PHASE_US.load(SeqCst);
    if phase_us == 0 || PASS.load(SeqCst) || SHUTDOWN.load(SeqCst) || WINDOW_CLOSED.load(SeqCst) {
        return false;
    }
    let now = qpc_now();
    if PENDING.load(SeqCst) {
        // A deferred paint is on its way; WM_PAINT repeats are swallowed, but not for long.
        if qpc_to_ns(now - PENDING_SINCE.load(SeqCst)) > DEFER_EXPIRY_NS {
            PENDING.store(false, SeqCst);
            FAILED_OPEN.fetch_add(1, SeqCst);
            return false;
        }
        unsafe { ValidateRect(hwnd, std::ptr::null()) };
        return true;
    }
    let wait_ns = match vblank_phase_ns(now) {
        Some(phase) => (phase_us * 1000).saturating_sub(phase),
        None => {
            FALLBACK_WAITS.fetch_add(1, SeqCst);
            FALLBACK_WAIT_NS
        }
    };
    if wait_ns < MIN_WAIT_NS {
        // Already at or past the target phase: waiting would only push the frame past DWM's latch.
        PASSED_THROUGH.fetch_add(1, SeqCst);
        return false;
    }
    let sent = match TX.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        Some(tx) => tx.send(wait_ns).is_ok(),
        None => false,
    };
    if !sent {
        PHASE_US.store(0, SeqCst);
        FAILED_OPEN.fetch_add(1, SeqCst);
        return false;
    }
    PENDING.store(true, SeqCst);
    PENDING_SINCE.store(now, SeqCst);
    DEFERRED.fetch_add(1, SeqCst);
    unsafe { ValidateRect(hwnd, std::ptr::null()) };
    true
}

/// WM_SWR_PAINT: the deferred paint is due. Invalidates and updates the window now, which sends GPUI its WM_PAINT.
pub fn run_deferred_paint(hwnd: *mut c_void) {
    PENDING.store(false, SeqCst);
    if SHUTDOWN.load(SeqCst) || WINDOW_CLOSED.load(SeqCst) {
        return;
    }
    PASS.store(true, SeqCst);
    unsafe {
        InvalidateRect(hwnd, std::ptr::null(), 0);
        UpdateWindow(hwnd);
    }
    PASS.store(false, SeqCst);
}
