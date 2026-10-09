//! swiftright-render: ABI v0 (revision 0.5) renderer for SwiftRight on Windows.
//! See render/swiftright-abi/include/swiftright.h for the contract (threading,
//! ownership, units). Every `extern "C"` entry contains panics (SWR_E_PANIC).
//!
//! Consolidates the SR0-B/SR0-D probes: foreground-executor wake/drain with a
//! non-reentrant guard (gpui-drain), display-driven frame ticks (frame-clock), text
//! measurement and retained runs (text-geometry), AccessKit with enqueue-only actions
//! (text-geometry, modal-loop, bridge-faults), IMM32 text-store bridging (ime-text-node).
#![cfg(windows)]

mod abi;
mod ax;
mod rt;
mod text;
mod tree;
mod view;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::Ordering::SeqCst;
use std::sync::Arc;

use abi::*;
use rt::*;

macro_rules! guard {
    ($body:expr) => {
        match catch_unwind(AssertUnwindSafe(|| -> Status { $body })) {
            Ok(v) => v,
            Err(_) => E_PANIC,
        }
    };
}

fn arch_bytes() -> [u8; 16] {
    let mut a = [0u8; 16];
    let n = b"x86_64";
    a[..n.len()].copy_from_slice(n);
    a
}

#[no_mangle]
pub extern "C" fn swr_bootstrap_query(out: *mut BootstrapInfo, caller_size: u32) -> Status {
    guard!({
        let need = std::mem::size_of::<BootstrapInfo>() as u32;
        if out.is_null() || caller_size < need {
            return E_BAD_ARG;
        }
        unsafe {
            *out = BootstrapInfo {
                struct_size: need,
                abi_major: ABI_MAJOR,
                abi_minor: ABI_MINOR,
                pointer_width: (std::mem::size_of::<usize>() * 8) as u32,
                arch: arch_bytes(),
                host_callbacks_size: std::mem::size_of::<HostCallbacks>() as u32,
                api_table_size: std::mem::size_of::<Api>() as u32,
                transaction_size: std::mem::size_of::<Transaction>() as u32,
                node_size: std::mem::size_of::<Node>() as u32,
                primitive_size: std::mem::size_of::<Primitive>() as u32,
                semantic_size: std::mem::size_of::<Semantic>() as u32,
                ax_text_run_size: std::mem::size_of::<AxTextRun>() as u32,
                event_size: std::mem::size_of::<Event>() as u32,
                measure_request_size: std::mem::size_of::<MeasureRequest>() as u32,
                measure_result_size: std::mem::size_of::<MeasureResult>() as u32,
                line_info_size: std::mem::size_of::<LineInfo>() as u32,
                char_cell_size: std::mem::size_of::<CharCell>() as u32,
                fn_count: API_FN_COUNT,
                stats_size: std::mem::size_of::<Stats>() as u32,
            };
        }
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_get_api(out: *mut Api, caller_size: u32) -> Status {
    guard!({
        if out.is_null() || (caller_size as usize) < std::mem::size_of::<Api>() {
            return E_ABI;
        }
        unsafe {
            *out = Api {
                struct_size: std::mem::size_of::<Api>() as u32,
                reserved: 0,
                run: swr_run,
                request_quit: swr_request_quit,
                window_request_close: swr_window_request_close,
                window_get_metrics: swr_window_get_metrics,
                commit: swr_commit,
                measure_text: swr_measure_text,
                text_run_cells: swr_text_run_cells,
                text_run_release: swr_text_run_release,
                event_pop: swr_event_pop,
                request_ticks: swr_request_ticks,
                request_modal: swr_request_modal,
                selftest_reentry: swr_selftest_reentry,
                get_stats: swr_get_stats,
                shutdown_complete: swr_shutdown_complete,
            };
        }
        SWR_OK
    })
}

/// Blocks on the calling thread: opens the window, runs the loop.
#[no_mangle]
pub extern "C" fn swr_run(opts: *const RunOptions, cb: *const HostCallbacks) -> Status {
    guard!({
        if opts.is_null() || cb.is_null() {
            return E_BAD_ARG;
        }
        let o = unsafe { &*opts };
        let c = unsafe { *cb };
        if (o.struct_size as usize) < std::mem::size_of::<RunOptions>()
            || (c.struct_size as usize) < std::mem::size_of::<HostCallbacks>()
            || c.drain.is_none()
            || o.host_wake_handle.is_null()
            || o.width_dip == 0
            || o.height_dip == 0
        {
            return E_BAD_ARG;
        }
        if SHUTDOWN.load(SeqCst) || RUN_STARTED.swap(true, SeqCst) {
            return E_STATE;
        }
        let title = if o.title.is_null() || o.title_len == 0 {
            String::from("SwiftRight")
        } else {
            let b = unsafe { std::slice::from_raw_parts(o.title as *const u8, o.title_len as usize) };
            match std::str::from_utf8(b) {
                Ok(s) => s.to_string(),
                Err(_) => return E_BAD_ARG,
            }
        };
        let host = Host::from_abi(&c);
        view::run(title, o.width_dip, o.height_dip, host, o.host_wake_handle as usize)
    })
}

#[no_mangle]
pub extern "C" fn swr_request_quit() -> Status {
    guard!({
        QUIT_REQUESTED.store(true, SeqCst);
        signal_notify();
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_window_request_close(window: u64) -> Status {
    guard!({
        let live = LIVE_WINDOW.load(SeqCst);
        if window == 0 || window != live {
            return E_STALE_HANDLE;
        }
        CLOSE_REQUESTED.store(true, SeqCst);
        signal_notify();
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_window_get_metrics(window: u64, out: *mut WindowMetrics) -> Status {
    guard!({
        if out.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if window == 0 || window != LIVE_WINDOW.load(SeqCst) {
            return E_STALE_HANDLE;
        }
        unsafe {
            *out = WindowMetrics {
                struct_size: std::mem::size_of::<WindowMetrics>() as u32,
                width_px: WIN_W.load(SeqCst),
                height_px: WIN_H.load(SeqCst),
                scale: f32::from_bits(WIN_SCALE_BITS.load(SeqCst)),
                active: WIN_ACTIVE.load(SeqCst) as u32,
                reserved: 0,
            };
        }
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_commit(t: *const Transaction) -> Status {
    guard!({
        if t.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        let t = unsafe { &*t };
        if (t.struct_size as usize) < std::mem::size_of::<Transaction>() {
            bump(S_COMMITS_REJ);
            return E_ABI;
        }
        if SHUTDOWN.load(SeqCst) {
            bump(S_COMMITS_REJ);
            return E_SHUTDOWN;
        }
        let live = LIVE_WINDOW.load(SeqCst);
        if live == 0 || t.window != live {
            bump(S_COMMITS_REJ);
            return E_STALE_HANDLE;
        }
        let r = view::with_ui(|ui| unsafe { tree::commit(&mut ui.tree, &ui.runs, t) });
        match r {
            Err(e) => {
                bump(S_COMMITS_REJ);
                e
            }
            Ok(Err(e)) => {
                bump(S_COMMITS_REJ);
                e
            }
            Ok(Ok(mut ax)) => {
                // Publish plain data for AccessKit, remember the IME / focus targets.
                let editable = view::with_ui(|ui| {
                    ui.tree
                        .nodes
                        .get(&t.focus)
                        .map(|n| n.flags & NODE_EDITABLE != 0)
                        .unwrap_or(false)
                })
                .unwrap_or(false);
                {
                    let mut shared = ax::lock_ax();
                    ax.title = shared.title.clone();
                    *shared = ax;
                }
                FOCUS_NODE.store(t.focus, SeqCst);
                IME_NODE.store(if editable { t.focus } else { 0 }, SeqCst);
                SNAPSHOT.store(t.version, SeqCst);
                bump(S_COMMITS_OK);
                if in_ime_callback() {
                    // Stored now, presented only after the native callback unwinds.
                    bump(S_COMMITS_DEFERRED);
                }
                PRESENT_PENDING.store(true, SeqCst);
                signal_notify();
                SWR_OK
            }
        }
    })
}

unsafe fn utf8<'a>(p: *const std::ffi::c_char, len: u32) -> Result<&'a str, Status> {
    if len == 0 {
        return Ok("");
    }
    if p.is_null() {
        return Err(E_BAD_ARG);
    }
    std::str::from_utf8(std::slice::from_raw_parts(p as *const u8, len as usize)).map_err(|_| E_BAD_ARG)
}

#[no_mangle]
pub extern "C" fn swr_measure_text(req: *const MeasureRequest, out: *mut MeasureResult) -> Status {
    guard!({
        if req.is_null() || out.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        let r = unsafe { &*req };
        if (r.struct_size as usize) < std::mem::size_of::<MeasureRequest>() {
            return E_ABI;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        if r.direction != 0 {
            return E_UNSUPPORTED;
        }
        if !(r.scale > 0.0 && r.font_size > 0.0 && r.line_height > 0.0) {
            return E_BAD_ARG;
        }
        let text = match unsafe { utf8(r.text, r.text_len) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        if text.contains('\n') || text.contains('\r') {
            return E_UNSUPPORTED;
        }
        let family = match unsafe { utf8(r.font_family, r.font_family_len) } {
            Ok(s) if !s.is_empty() => s,
            Ok(_) => "Segoe UI",
            Err(e) => return e,
        };
        let locale = match unsafe { utf8(r.locale, r.locale_len) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        let q = text::Request {
            text,
            family,
            locale,
            weight: if r.font_weight == 0 { 400 } else { r.font_weight },
            direction: r.direction,
            color: r.color,
            font_size: r.font_size,
            line_height: r.line_height,
            scale: r.scale,
            max_width: r.max_width,
        };
        bump(S_MEASURE);
        let key = text::cache_key(&q);
        let res = view::with_ui(|ui| -> Result<(Arc<text::Measured>, bool, u64), Status> {
            let (m, hit) = match ui.cache.get(key, text) {
                Some(m) => (m, true),
                None => {
                    let ts = ui.text_system.clone().ok_or(E_NOT_READY)?;
                    let m = Arc::new(text::shape(&ts, &q, key)?);
                    ui.cache.put(key, m.clone());
                    (m, false)
                }
            };
            let h = ui.runs.insert(m.clone())?;
            Ok((m, hit, h))
        });
        let (m, hit, handle) = match res {
            Err(e) | Ok(Err(e)) => return e,
            Ok(Ok(v)) => v,
        };
        if hit {
            bump(S_MEASURE_HITS);
        }
        unsafe {
            if !r.lines_out.is_null() {
                let n = (r.lines_cap as usize).min(m.lines.len());
                for i in 0..n {
                    *r.lines_out.add(i) = m.lines[i];
                }
            }
            *out = MeasureResult {
                struct_size: std::mem::size_of::<MeasureResult>() as u32,
                cache_hit: hit as u32,
                run: handle,
                width: m.width,
                height: m.height,
                first_baseline: m.first_baseline,
                last_baseline: m.last_baseline,
                line_count: m.lines.len() as u32,
                lines_written: if r.lines_out.is_null() {
                    0
                } else {
                    (r.lines_cap as usize).min(m.lines.len()) as u32
                },
                char_count: m.char_count,
                reserved: 0,
                cache_key: m.key,
            };
        }
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_text_run_cells(run: u64, cells: *mut CharCell, cap: u32, count: *mut u32) -> Status {
    guard!({
        if count.is_null() || (cells.is_null() && cap > 0) {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        let m = match view::with_ui(|ui| ui.runs.get(run)) {
            Ok(Some(m)) => m,
            Ok(None) => return E_STALE_HANDLE,
            Err(e) => return e,
        };
        unsafe {
            *count = m.cells.len() as u32;
            for (i, c) in m.cells.iter().take(cap as usize).enumerate() {
                *cells.add(i) = *c;
            }
        }
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_text_run_release(run: u64) -> Status {
    guard!({
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        match view::with_ui(|ui| ui.runs.release(run)) {
            Ok(s) => s,
            Err(e) => e,
        }
    })
}

#[no_mangle]
pub extern "C" fn swr_event_pop(out: *mut Event) -> Status {
    guard!({
        if out.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        match pop_event() {
            Some(ev) => {
                unsafe { *out = ev };
                SWR_OK
            }
            None => SWR_EMPTY,
        }
    })
}

#[no_mangle]
pub extern "C" fn swr_request_ticks(window: u64, on: i32) -> Status {
    guard!({
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if window == 0 || window != LIVE_WINDOW.load(SeqCst) {
            return E_STALE_HANDLE;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        let want = on != 0;
        let was = ANIMATING.swap(want, SeqCst);
        if want && !was {
            KICK.store(true, SeqCst);
            signal_notify();
        }
        SWR_OK
    })
}

#[no_mangle]
pub extern "C" fn swr_request_modal(window: u64, req: *const ModalRequest) -> Status {
    guard!({
        if req.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if window == 0 || window != LIVE_WINDOW.load(SeqCst) {
            return E_STALE_HANDLE;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        let r = unsafe { &*req };
        if (r.struct_size as usize) < std::mem::size_of::<ModalRequest>() {
            return E_ABI;
        }
        if r.kind != MODAL_MESSAGE || !(1..=3).contains(&r.buttons) {
            return E_BAD_ARG;
        }
        let title = match unsafe { utf8(r.title, r.title_len) } {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let message = match unsafe { utf8(r.message, r.message_len) } {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        view::queue_modal(r.request_id, r.buttons, title, message)
    })
}

#[no_mangle]
pub extern "C" fn swr_selftest_reentry() -> Status {
    guard!({ rt::selftest_reentry() })
}

#[no_mangle]
pub extern "C" fn swr_get_stats(out: *mut Stats) -> Status {
    guard!({
        if out.is_null() {
            return E_BAD_ARG;
        }
        unsafe {
            let mut s = Stats::default();
            fill_stats(&mut s);
            *out = s;
        }
        SWR_OK
    })
}

/// Ends the post-close pump (rev 0.5). UI thread only; valid once window_closed has been
/// entered. Idempotent. swr_run returns after the pump ends.
#[no_mangle]
pub extern "C" fn swr_shutdown_complete() -> Status {
    guard!({
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if !POST_CLOSE_ACTIVE.load(SeqCst) {
            return E_STATE;
        }
        SHUTDOWN_COMPLETE.store(true, SeqCst);
        signal_notify();
        SWR_OK
    })
}

// Keep the type referenced so a future unused-warning does not hide ABI drift.
#[allow(dead_code)]
fn _abi_anchor(_: *mut c_void) {}
