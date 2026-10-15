//! swiftright-render: ABI v0 (revision 0.6) renderer for SwiftRight on Windows.
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
mod dwr;
mod faces;
mod font;
mod pace;
mod rt;
mod text;
mod trace;
mod tree;
mod view;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::Ordering::SeqCst;
use std::sync::Arc;

use abi::*;
use rt::*;

/// Counts live bytes and allocations (trace.rs): the memory-growth work needs to tell the Rust heap from everything else.
#[global_allocator]
static GLOBAL: trace::CountingAlloc = trace::CountingAlloc;

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
                image_register: swr_image_register,
                image_release: swr_image_release,
            };
        }
        SWR_OK
    })
}

/// Rev 0.7 discovery (additive): the 0.6 fields exactly as `swr_bootstrap_query` reports them
/// except abi_minor 7, api_table_size 152 and fn_count 18, plus the two font size words. The
/// legacy export above is untouched, so a 0.6 host never sees any of this.
#[no_mangle]
pub extern "C" fn swr_bootstrap_query_v07(out: *mut BootstrapInfoV07, caller_size: u32) -> Status {
    guard!({
        let need = std::mem::size_of::<BootstrapInfoV07>() as u32;
        if out.is_null() || caller_size < need {
            return E_BAD_ARG;
        }
        let mut base = BootstrapInfo {
            struct_size: need,
            abi_major: ABI_MAJOR,
            abi_minor: ABI_MINOR_V07,
            pointer_width: (std::mem::size_of::<usize>() * 8) as u32,
            arch: arch_bytes(),
            host_callbacks_size: std::mem::size_of::<HostCallbacks>() as u32,
            api_table_size: std::mem::size_of::<ApiV07>() as u32,
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
            fn_count: API_V07_FN_COUNT,
            stats_size: std::mem::size_of::<Stats>() as u32,
        };
        base.struct_size = need;
        unsafe {
            *out = BootstrapInfoV07 {
                base,
                font_info_size: std::mem::size_of::<FontInfo>() as u32,
                font_resolution_size: std::mem::size_of::<FontResolution>() as u32,
            };
        }
        SWR_OK
    })
}

/// Rev 0.7 function table: the 16 legacy pointers (same functions) + font_register/font_resolve.
#[no_mangle]
pub extern "C" fn swr_get_api_v07(out: *mut ApiV07, caller_size: u32) -> Status {
    guard!({
        if out.is_null() || (caller_size as usize) < std::mem::size_of::<ApiV07>() {
            return E_ABI;
        }
        unsafe {
            *out = ApiV07 {
                struct_size: std::mem::size_of::<ApiV07>() as u32,
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
                image_register: swr_image_register,
                image_release: swr_image_release,
                font_register: swr_font_register,
                font_resolve: swr_font_resolve,
            };
        }
        SWR_OK
    })
}

/// Rev 0.7. Registers one TTF/OTF/TTC (borrowed bytes, copied and retained for the process:
/// GPUI 0.2.2 cannot remove a font) into GPUI's DirectWrite text system so `font(<family>)`
/// resolves to these bytes. UI thread, window must exist (call from `ready`).
#[no_mangle]
pub extern "C" fn swr_font_register(bytes: *const u8, len: u64, out: *mut FontInfo) -> Status {
    guard!({
        if bytes.is_null() || out.is_null() || len == 0 {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if unsafe { (*out).struct_size } < std::mem::size_of::<FontInfo>() as u32 {
            return E_ABI;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        if len > FONT_MAX_BYTES {
            return E_TOO_LARGE;
        }
        let data = unsafe { std::slice::from_raw_parts(bytes, len as usize) };
        let meta = match font::parse(data) {
            Ok(m) => m,
            Err(e) => return e,
        };
        let sha = font::sha256(data);
        let Ok(mut reg) = font::REGISTRY.lock() else { return E_STATE };
        if let Some(e) = reg.find_sha(&sha).cloned() {
            unsafe { font::fill_info(&mut *out, &e, FONT_DUPLICATE) };
            return SWR_OK;
        }
        let late = reg.was_shaped(&meta.family);
        // 'static, never freed: DirectWrite's in-memory file reference does not copy.
        let keep: &'static [u8] = Box::leak(data.to_vec().into_boxed_slice());
        let res = view::with_ui(|ui| -> Result<u32, Status> {
            let ts = ui.text_system.clone().ok_or(E_NOT_READY)?;
            let want = font::key(&meta.family);
            let listed = ts.all_font_names().iter().any(|n| font::key(n) == want);
            ts.add_fonts(vec![std::borrow::Cow::Borrowed(keep)]).map_err(|_| E_PLATFORM)?;
            ui.cache.clear();
            Ok(if listed { FONT_SYSTEM_FAMILY } else { 0 })
        });
        let sys = match res {
            Err(e) | Ok(Err(e)) => return e,
            Ok(Ok(f)) => f,
        };
        let mut e = reg.add(meta, sha);
        reg.attach_bytes(e.handle, keep);
        e.bytes = Some(keep);
        unsafe { font::fill_info(&mut *out, &e, FONT_NEW | sys | if late { FONT_LATE } else { 0 }) };
        SWR_OK
    })
}

/// Rev 0.7. Where would `family` be shaped from? Never shapes, never registers.
#[no_mangle]
pub extern "C" fn swr_font_resolve(family: *const u8, family_len: u32, out: *mut FontResolution) -> Status {
    guard!({
        if family.is_null() || out.is_null() || family_len == 0 {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if unsafe { (*out).struct_size } < std::mem::size_of::<FontResolution>() as u32 {
            return E_ABI;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        let name = match unsafe { utf8(family as *const std::ffi::c_char, family_len) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        let ts = match view::with_ui(|ui| ui.text_system.clone()) {
            Err(e) => return e,
            Ok(None) => return E_NOT_READY,
            Ok(Some(ts)) => ts,
        };
        let Ok(reg) = font::REGISTRY.lock() else { return E_STATE };
        let names: Vec<String> = ts.all_font_names().iter().map(|n| font::key(n)).collect();
        let (source, hit) = reg.resolve(name, |f| names.contains(&font::key(f)));
        unsafe {
            *out = FontResolution {
                struct_size: std::mem::size_of::<FontResolution>() as u32,
                source,
                font: hit.map_or(0, |e| e.handle),
                sha256: hit.map_or([0u8; 32], |e| e.sha256),
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
        let t_start = qpc_now();
        // Rev 0.9: a transaction of struct_size >= sizeof(TransactionV09) carries a range table (slider values).
        let ranges: &[RangeEntry] = if (t.struct_size as usize) >= std::mem::size_of::<TransactionV09>() {
            let t9 = unsafe { &*(t as *const Transaction as *const TransactionV09) };
            match unsafe { tree::slice_of(t9.ranges, t9.range_count) } {
                Ok(r) => r,
                Err(e) => {
                    bump(S_COMMITS_REJ);
                    return e;
                }
            }
        } else {
            &[]
        };
        let r = view::with_ui(|ui| unsafe { tree::commit_ranges(&mut ui.tree, &ui.runs, &ui.images, t, ranges) });
        PH_TREE.add(qpc_now() - t_start);
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
                // Rev 0.6: a disabled focus target (or one below a disabled node) is neither
                // the key-event nor the IME target: events carry node 0 (the window).
                let (editable, focus_disabled) = view::with_ui(|ui| {
                    let ed = ui
                        .tree
                        .nodes
                        .get(&t.focus)
                        .map(|n| n.flags & NODE_EDITABLE != 0)
                        .unwrap_or(false);
                    (ed, t.focus != 0 && ui.tree.is_disabled(t.focus))
                })
                .unwrap_or((false, false));
                let editable = editable && !focus_disabled;
                let event_focus = if focus_disabled { 0 } else { t.focus };
                {
                    let mut shared = ax::lock_ax();
                    ax.title = shared.title.clone();
                    *shared = ax;
                }
                FOCUS_NODE.store(event_focus, SeqCst);
                IME_NODE.store(if editable { t.focus } else { 0 }, SeqCst);
                SNAPSHOT.store(t.version, SeqCst);
                bump(S_COMMITS_OK);
                if in_ime_callback() {
                    // Stored now, presented only after the native callback unwinds.
                    bump(S_COMMITS_DEFERRED);
                }
                PRESENT_PENDING.store(true, SeqCst);
                signal_notify();
                PH_COMMIT.span(trace::K_COMMIT, t_start, qpc_now());
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
        measure_core(r, None, unsafe { &mut *out })
    })
}

/// The measurement shared by the 0.6 entry and the rev 0.8 entry. `ext` is None for a 0.6 request (unchanged behaviour).
fn measure_core(r: &MeasureRequest, ext: Option<&text::Ext>, out: &mut MeasureResult) -> Status {
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
    // Rev 0.6: '\n' separates paragraphs. '\r' is still unsupported.
    if text.contains('\r') {
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
        ext,
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
                if let Ok(mut reg) = font::REGISTRY.lock() {
                    reg.note_shaped(q.family);
                }
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
    SWR_OK
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
        let title = match unsafe { utf8(r.title, r.title_len) } {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let message = match unsafe { utf8(r.message, r.message_len) } {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let mut pending = view::ModalPending {
            id: r.request_id,
            kind: r.kind,
            buttons: 0,
            title,
            message,
            items: Vec::new(),
            x: 0.0,
            y: 0.0,
            default_item: 0,
        };
        match r.kind {
            MODAL_MESSAGE => {
                if !(1..=3).contains(&r.buttons) {
                    return E_BAD_ARG;
                }
                pending.buttons = r.buttons;
            }
            MODAL_MENU | MODAL_DIALOG => {
                let max = if r.kind == MODAL_MENU { MODAL_ITEMS_MAX_MENU } else { MODAL_ITEMS_MAX_DIALOG };
                if r.item_count == 0 {
                    return E_BAD_ARG;
                }
                if r.item_count > max {
                    return E_TOO_LARGE;
                }
                if r.items.is_null() || !r.x.is_finite() || !r.y.is_finite() {
                    return E_BAD_ARG;
                }
                if r.kind == MODAL_DIALOG && r.default_item >= r.item_count {
                    return E_BAD_ARG;
                }
                let raw = unsafe { std::slice::from_raw_parts(r.items, r.item_count as usize) };
                let mut seen = std::collections::HashSet::new();
                let mut any_selectable = false;
                for it in raw {
                    let sep = r.kind == MODAL_MENU && it.flags & MODAL_ITEM_SEPARATOR != 0;
                    let text = match unsafe { utf8(it.text, it.text_len) } {
                        Ok(s) => s.to_string(),
                        Err(e) => return e,
                    };
                    if !sep {
                        // Ids are non-zero and unique; a button needs a label.
                        if it.id == 0 || it.id > i32::MAX as u32 || !seen.insert(it.id) {
                            return E_BAD_ARG;
                        }
                        if r.kind == MODAL_DIALOG && text.is_empty() {
                            return E_BAD_ARG;
                        }
                        any_selectable = true;
                    }
                    pending.items.push(view::ModalItemOwned { id: it.id, text, flags: it.flags });
                }
                if !any_selectable {
                    return E_BAD_ARG;
                }
                pending.x = r.x;
                pending.y = r.y;
                pending.default_item = r.default_item;
            }
            _ => return E_BAD_ARG,
        }
        view::queue_modal(pending)
    })
}

/// Rev 0.6. UI thread only. Copies RGBA8 pixels into a retained, generation-tagged image.
#[no_mangle]
pub extern "C" fn swr_image_register(
    rgba: *const u8,
    width: u32,
    height: u32,
    stride: u32,
    out: *mut u64,
) -> Status {
    guard!({
        if rgba.is_null() || out.is_null() || width == 0 || height == 0 {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        if width > IMAGE_MAX_DIM || height > IMAGE_MAX_DIM {
            return E_TOO_LARGE;
        }
        let row = width as u64 * 4;
        let stride = if stride == 0 { row } else { stride as u64 };
        if stride < row {
            return E_BAD_ARG;
        }
        if row * height as u64 > IMAGE_MAX_BYTES {
            return E_TOO_LARGE;
        }
        // Copy row by row (the host buffer may carry row padding), swapping R and B: GPUI
        // sprites are BGRA (gpui platform.rs Image::to_image_data does the same swap).
        let mut px = Vec::with_capacity((row * height as u64) as usize);
        for y in 0..height as u64 {
            let line = unsafe { std::slice::from_raw_parts(rgba.add((y * stride) as usize), row as usize) };
            for p in line.chunks_exact(4) {
                px.extend_from_slice(&[p[2], p[1], p[0], p[3]]);
            }
        }
        let Some(buf) = image::RgbaImage::from_raw(width, height, px) else {
            return E_BAD_ARG;
        };
        let img = Arc::new(crate::text::TrackedImage::new(gpui::RenderImage::new(vec![image::Frame::new(buf)])));
        match view::with_ui(|ui| ui.images.insert(img)) {
            Err(e) | Ok(Err(e)) => e,
            Ok(Ok(h)) => {
                unsafe { *out = h };
                SWR_OK
            }
        }
    })
}

/// Rev 0.6. Owner frees; a stale or already released handle is SWR_E_STALE_HANDLE.
#[no_mangle]
pub extern "C" fn swr_image_release(image: u64) -> Status {
    guard!({
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        match view::with_ui(|ui| ui.images.take(image)) {
            Err(e) => e,
            Ok(None) => E_STALE_HANDLE,
            Ok(Some(img)) => {
                view::queue_image_drop(img.img.clone());
                SWR_OK
            }
        }
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

// ====================================================================================================================
// Rev 0.8 (additive): text extension, minimal form. Everything gpui 0.2.2 can do (tracking through paint_glyph, features,
// system fallbacks, a named-instance weight) goes through gpui; the DirectWrite face resolver (dwr.rs) answers what gpui does
// not expose (which real faces exist, which face a run used, face metrics). No own run pipeline (decision G17, F3b).
// ====================================================================================================================

fn bootstrap_v07_with(minor: u32, api_table_size: u32, fn_count: u32) -> BootstrapInfoV07 {
    let base = BootstrapInfo {
        struct_size: std::mem::size_of::<BootstrapInfoV08>() as u32,
        abi_major: ABI_MAJOR,
        abi_minor: minor,
        pointer_width: (std::mem::size_of::<usize>() * 8) as u32,
        arch: arch_bytes(),
        host_callbacks_size: std::mem::size_of::<HostCallbacks>() as u32,
        api_table_size,
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
        fn_count,
        stats_size: std::mem::size_of::<Stats>() as u32,
    };
    BootstrapInfoV07 {
        base,
        font_info_size: std::mem::size_of::<FontInfo>() as u32,
        font_resolution_size: std::mem::size_of::<FontResolution>() as u32,
    }
}

/// Rev 0.8 discovery: the 0.7 view at identical offsets (abi_minor 8, 184-byte table, 22 functions) + the 0.8 size words.
/// The legacy and `_v07` exports are untouched, so a 0.6 or 0.7 host never sees any of this.
#[no_mangle]
pub extern "C" fn swr_bootstrap_query_v08(out: *mut BootstrapInfoV08, caller_size: u32) -> Status {
    guard!({
        let need = std::mem::size_of::<BootstrapInfoV08>() as u32;
        if out.is_null() || caller_size < need {
            return E_BAD_ARG;
        }
        unsafe {
            *out = BootstrapInfoV08 {
                v07: bootstrap_v07_with(ABI_MINOR_V08, std::mem::size_of::<ApiV08>() as u32, API_V08_FN_COUNT),
                measure_request_v08_size: std::mem::size_of::<MeasureRequestV08>() as u32,
                measure_result_v08_size: std::mem::size_of::<MeasureResultV08>() as u32,
                run_face_size: std::mem::size_of::<RunFace>() as u32,
                face_metrics_size: std::mem::size_of::<FaceMetrics>() as u32,
                system_fonts_size: std::mem::size_of::<SystemFonts>() as u32,
                reserved: 0,
            };
        }
        SWR_OK
    })
}

/// Rev 0.9 discovery (additive): the 0.8 view at identical offsets (abi_minor 9; the 184-byte table and 22 functions are the 0.8 ones)
/// + the range entry and v09 transaction sizes. The legacy, `_v07` and `_v08` exports are untouched.
#[no_mangle]
pub extern "C" fn swr_bootstrap_query_v09(out: *mut BootstrapInfoV09, caller_size: u32) -> Status {
    guard!({
        let need = std::mem::size_of::<BootstrapInfoV09>() as u32;
        if out.is_null() || caller_size < need {
            return E_BAD_ARG;
        }
        let mut v08 = std::mem::MaybeUninit::<BootstrapInfoV08>::uninit();
        let rc = swr_bootstrap_query_v08(v08.as_mut_ptr(), std::mem::size_of::<BootstrapInfoV08>() as u32);
        if rc != SWR_OK {
            return rc;
        }
        let mut v08 = unsafe { v08.assume_init() };
        v08.v07.base.abi_minor = ABI_MINOR_V09;
        v08.v07.base.struct_size = need;
        unsafe {
            *out = BootstrapInfoV09 {
                v08,
                range_entry_size: std::mem::size_of::<RangeEntry>() as u32,
                transaction_v09_size: std::mem::size_of::<TransactionV09>() as u32,
            };
        }
        SWR_OK
    })
}

/// Rev 0.9 function table: identical to the 0.8 table (no new functions).
#[no_mangle]
pub extern "C" fn swr_get_api_v09(out: *mut ApiV08, caller_size: u32) -> Status {
    swr_get_api_v08(out, caller_size)
}

/// Rev 0.8 function table: the 18 legacy/0.7 pointers (same functions) + the four 0.8 entries.
#[no_mangle]
pub extern "C" fn swr_get_api_v08(out: *mut ApiV08, caller_size: u32) -> Status {
    guard!({
        if out.is_null() || (caller_size as usize) < std::mem::size_of::<ApiV08>() {
            return E_ABI;
        }
        unsafe {
            *out = ApiV08 {
                struct_size: std::mem::size_of::<ApiV08>() as u32,
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
                image_register: swr_image_register,
                image_release: swr_image_release,
                font_register: swr_font_register,
                font_resolve: swr_font_resolve,
                measure_text_v08: swr_measure_text_v08,
                text_run_faces: swr_text_run_faces,
                font_face_metrics: swr_font_face_metrics,
                system_font_info: swr_system_font_info,
            };
        }
        SWR_OK
    })
}

/// The real faces of a family and where they come from: registered bytes first (their sfnt weight class and italic flag), else
/// the installed family through DirectWrite. An unknown family is an empty list (the request passes through to gpui).
fn family_faces(family: &str) -> (u32, Vec<faces::FaceEntry>) {
    if let Ok(reg) = font::REGISTRY.lock() {
        let entries = reg.family_entries(family);
        if !entries.is_empty() {
            return (FONT_SRC_BUNDLED, entries.iter().map(|e| faces::FaceEntry { weight: e.meta.weight, italic: e.meta.italic }).collect());
        }
    }
    match dwr::system_faces(family) {
        Some(v) if !v.is_empty() => (FONT_SRC_SYSTEM, v),
        _ => (FONT_SRC_FALLBACK, Vec::new()),
    }
}

/// A validated, resolved rev 0.8 request.
struct Prepared {
    ext: text::Ext,
    applied: u32,
    ignored: u32,
    pick: faces::Pick,
}

fn finite(v: f32) -> bool {
    v.is_finite()
}

/// Validates the 0.8 fields (every limit is checked before anything is applied: the request is rejected whole), resolves the
/// face policy and decides what is applied and what is reported as ignored.
fn prepare(r: &MeasureRequestV08, family: &str) -> Result<Prepared, Status> {
    if r.feature_count as usize > FEATURES_MAX || r.fallback_count as usize > FALLBACKS_MAX {
        return Err(E_TOO_LARGE);
    }
    if (r.feature_count > 0 && r.features.is_null()) || (r.fallback_count > 0 && r.fallbacks.is_null()) {
        return Err(E_BAD_ARG);
    }
    let floats = [r.weight_f, r.width_axis, r.opsz, r.slant, r.tracking_dip, r.kerning_dip, r.baseline_offset_dip];
    if !floats.iter().all(|v| finite(*v)) || r.weight_f < 0.0 || r.weight_f > 1000.0 {
        return Err(E_BAD_ARG);
    }
    let raw_features: &[Feature] =
        if r.feature_count == 0 { &[] } else { unsafe { std::slice::from_raw_parts(r.features, r.feature_count as usize) } };
    let features = faces::features_from(raw_features)?;
    let mut fallback_names: Vec<String> = Vec::new();
    if r.fallback_count > 0 {
        for s in unsafe { std::slice::from_raw_parts(r.fallbacks, r.fallback_count as usize) } {
            let name = unsafe { utf8(s.ptr, s.len) }?;
            if name.is_empty() {
                return Err(E_BAD_ARG);
            }
            fallback_names.push(name.to_string());
        }
    }

    let mut applied = 0u32;
    let mut ignored = 0u32;
    // Axes gpui cannot honour are accepted and reported, never faked (G11).
    if r.width_axis != 0.0 && r.width_axis != 100.0 {
        ignored |= M08_IGN_WIDTH_AXIS;
    }
    if r.opsz != 0.0 {
        ignored |= M08_IGN_OPSZ;
    }
    if r.slant != 0.0 {
        ignored |= M08_IGN_SLANT;
    }
    // Fallbacks: system families only (gpui resolves them in the system collection and skips the rest, G13).
    let mut kept: Vec<String> = Vec::new();
    for name in fallback_names {
        let bundled = font::REGISTRY.lock().map(|g| !g.family_entries(&name).is_empty()).unwrap_or(false);
        if !bundled && dwr::family_present(&name) {
            kept.push(name);
        } else {
            ignored |= M08_IGN_FALLBACK_PRIVATE;
        }
    }
    if !kept.is_empty() {
        applied |= M08_APPLIED_FALLBACKS;
    }
    // Face policy: named instance, simulation clamp.
    let want_weight = if r.weight_f > 0.0 {
        r.weight_f.round() as u32
    } else if r.base.font_weight == 0 {
        400
    } else {
        r.base.font_weight
    };
    let (_, list) = family_faces(family);
    let pick = faces::pick_face(&list, want_weight, r.italic != 0, r.simulations & SIM_FORBID_BOLD != 0, r.simulations & SIM_FORBID_OBLIQUE != 0);
    ignored |= pick.ignored;
    if pick.found {
        applied |= M08_APPLIED_WEIGHT;
    }
    if r.italic != 0 {
        applied |= M08_APPLIED_ITALIC;
    }
    if !features.is_empty() {
        applied |= M08_APPLIED_FEATURES;
    }
    let track = r.tracking_dip + r.kerning_dip;
    if track != 0.0 {
        applied |= M08_APPLIED_TRACKING;
    }
    let baseline = (r.flags & M08_BASELINE_OFFSET != 0).then_some(r.baseline_offset_dip);
    if baseline.is_some() {
        applied |= M08_APPLIED_BASELINE;
    }
    Ok(Prepared {
        ext: text::Ext {
            weight: pick.weight_for_gpui,
            italic: pick.italic,
            sim: pick.sim,
            features,
            fallbacks: kept,
            track_dip: track,
            baseline_dip: baseline,
        },
        applied,
        ignored,
        pick,
    })
}

/// Rev 0.8. UI thread only. The 0.6 request plus weight, italic, tracking, kerning, OpenType features, a simulation policy,
/// system fallback families and a baseline offset. A request that breaks a limit is rejected whole.
#[no_mangle]
pub extern "C" fn swr_measure_text_v08(req: *const MeasureRequestV08, out: *mut MeasureResultV08) -> Status {
    guard!({
        if req.is_null() || out.is_null() {
            return E_BAD_ARG;
        }
        if !on_ui_thread() {
            return E_WRONG_THREAD;
        }
        let r = unsafe { &*req };
        if (r.struct_size as usize) < std::mem::size_of::<MeasureRequestV08>()
            || (r.base.struct_size as usize) < std::mem::size_of::<MeasureRequest>()
            || unsafe { (*out).struct_size } < std::mem::size_of::<MeasureResultV08>() as u32
        {
            return E_ABI;
        }
        if SHUTDOWN.load(SeqCst) {
            return E_SHUTDOWN;
        }
        let family = match unsafe { utf8(r.base.font_family, r.base.font_family_len) } {
            Ok(s) if !s.is_empty() => s,
            Ok(_) => "Segoe UI",
            Err(e) => return e,
        };
        let p = match prepare(r, family) {
            Ok(p) => p,
            Err(e) => return e,
        };
        let mut base: MeasureResult = unsafe { std::mem::zeroed() };
        let rc = measure_core(&r.base, Some(&p.ext), &mut base);
        if rc != SWR_OK {
            return rc;
        }
        unsafe {
            *out = MeasureResultV08 {
                struct_size: std::mem::size_of::<MeasureResultV08>() as u32,
                reserved0: 0,
                base,
                applied: p.applied,
                ignored: p.ignored,
                resolved_weight: p.pick.weight as f32,
                resolved_italic: p.pick.italic as u32,
                simulations: p.pick.sim,
                reserved: 0,
            };
        }
        SWR_OK
    })
}

/// System families a fallback face is matched against when gpui reports a face other than the requested one (G18).
const FALLBACK_CANDIDATES: [&str; 13] = [
    "Segoe UI",
    "Segoe UI Emoji",
    "Segoe UI Symbol",
    "Yu Gothic UI",
    "Microsoft YaHei UI",
    "Microsoft JhengHei UI",
    "Malgun Gothic",
    "Nirmala UI",
    "Segoe UI Historic",
    "MS Gothic",
    "Times New Roman",
    "Arial",
    "Cambria Math",
];

fn fill_system_face(f: &mut RunFace, d: &dwr::FaceDesc) {
    faces::fill_cstr(&mut f.family, &d.family);
    faces::fill_cstr(&mut f.ps_name, &d.ps_name);
    faces::fill_cstr(&mut f.version, &d.version);
    faces::fill_cstr(&mut f.file_name, &d.file_name);
    f.weight = d.weight;
}

/// One `RunFace` per shaped sub-run. The primary face is named exactly (a bundled family reports the registered bytes'
/// SHA-256); a fallback face is matched by glyph id against system candidates and is UNRESOLVED when none matches.
fn build_run_faces(m: &text::Measured) -> Vec<RunFace> {
    let face = &m.ext.face;
    let want_weight = face.weight.round().max(1.0) as u32;
    enum Primary {
        Bundled(font::Entry),
        System(dwr::FaceDesc),
        Unknown,
    }
    let bundled = font::REGISTRY.lock().map(|g| g.family_entries(&face.family)).unwrap_or_default();
    let primary = if !bundled.is_empty() {
        let list: Vec<faces::FaceEntry> = bundled.iter().map(|e| faces::FaceEntry { weight: e.meta.weight, italic: e.meta.italic }).collect();
        let p = faces::pick_face(&list, want_weight, face.italic, true, true);
        let hit = bundled.iter().find(|e| e.meta.weight == p.weight && e.meta.italic == p.italic).unwrap_or(&bundled[0]);
        Primary::Bundled(hit.clone())
    } else {
        match dwr::system_faces(&face.family) {
            Some(list) if !list.is_empty() => {
                let p = faces::pick_face(&list, want_weight, face.italic, true, true);
                dwr::describe(&face.family, p.weight, p.italic).map_or(Primary::Unknown, Primary::System)
            }
            _ => Primary::Unknown,
        }
    };
    let mut candidates: Vec<String> = Vec::new();
    if bundled.is_empty() {
        candidates.push(face.family.clone());
    }
    candidates.extend(face.fallbacks.iter().cloned());
    candidates.extend(FALLBACK_CANDIDATES.iter().map(|s| s.to_string()));
    m.ext
        .runs
        .iter()
        .map(|rec| {
            let mut f = RunFace::zeroed();
            f.utf8_start = rec.utf8_start;
            f.utf8_len = rec.utf8_len;
            f.glyph_count = rec.glyphs;
            f.notdef_count = rec.notdef;
            f.ascent = rec.ascent_px;
            f.descent = rec.descent_px;
            f.advance = rec.advance_px;
            if rec.emoji {
                f.flags |= RUNFACE_COLOR;
            }
            if rec.primary {
                f.flags |= RUNFACE_PRIMARY;
                if face.sim & SIMFLAG_BOLD != 0 {
                    f.flags |= RUNFACE_SIM_BOLD;
                }
                if face.sim & SIMFLAG_OBLIQUE != 0 {
                    f.flags |= RUNFACE_SIM_OBLIQUE;
                }
                match &primary {
                    Primary::Bundled(e) => {
                        f.flags |= RUNFACE_BUNDLED;
                        f.sha256 = e.sha256;
                        f.weight = e.meta.weight;
                        faces::fill_cstr(&mut f.family, &e.meta.family);
                        faces::fill_cstr(&mut f.ps_name, &e.meta.ps_name);
                        faces::fill_cstr(&mut f.version, &e.meta.version);
                    }
                    Primary::System(d) => {
                        f.flags |= RUNFACE_SYSTEM;
                        fill_system_face(&mut f, d);
                    }
                    Primary::Unknown => f.flags |= RUNFACE_UNRESOLVED,
                }
            } else {
                f.flags |= RUNFACE_FALLBACK;
                match dwr::identify(&candidates, rec.first_char, rec.first_gid) {
                    Some(d) => {
                        f.flags |= RUNFACE_SYSTEM;
                        fill_system_face(&mut f, &d);
                    }
                    None => f.flags |= RUNFACE_UNRESOLVED,
                }
            }
            f
        })
        .collect()
}

/// Rev 0.8. The faces of a retained run, per shaped sub-run. `*count` is always the total; `cap` entries are written.
#[no_mangle]
pub extern "C" fn swr_text_run_faces(run: u64, out: *mut RunFace, cap: u32, count: *mut u32) -> Status {
    guard!({
        if count.is_null() || (out.is_null() && cap > 0) {
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
        let list = build_run_faces(&m);
        unsafe {
            *count = list.len() as u32;
            for (i, f) in list.iter().take(cap as usize).enumerate() {
                *out.add(i) = *f;
            }
        }
        SWR_OK
    })
}

fn fill_metrics(out: &mut FaceMetrics, m: &faces::RawMetrics) {
    out.units_per_em = m.units_per_em;
    out.hhea_ascent = m.hhea_ascent;
    out.hhea_descent = m.hhea_descent;
    out.hhea_line_gap = m.hhea_line_gap;
    out.typo_ascent = m.typo_ascent;
    out.typo_descent = m.typo_descent;
    out.typo_line_gap = m.typo_line_gap;
    out.win_ascent = m.win_ascent;
    out.win_descent = m.win_descent;
    out.cap_height = m.cap_height;
    out.x_height = m.x_height;
}

/// Rev 0.8. The face a request resolves to. Bundled families answer from the registered bytes, installed ones from
/// DirectWrite. No window and no UI thread needed (it never touches gpui). An unknown family is SWR_OK with FACE_FOUND clear.
#[no_mangle]
pub extern "C" fn swr_font_face_metrics(family: *const u8, family_len: u32, weight: u32, _width_pct: u32, italic: u32, out: *mut FaceMetrics) -> Status {
    guard!({
        if family.is_null() || out.is_null() || family_len == 0 {
            return E_BAD_ARG;
        }
        if unsafe { (*out).struct_size } < std::mem::size_of::<FaceMetrics>() as u32 {
            return E_ABI;
        }
        let name = match unsafe { utf8(family as *const std::ffi::c_char, family_len) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        let mut m: FaceMetrics = unsafe { std::mem::zeroed() };
        m.struct_size = std::mem::size_of::<FaceMetrics>() as u32;
        m.source = FONT_SRC_FALLBACK;
        let want = if weight == 0 { 400 } else { weight };
        let bundled = font::REGISTRY.lock().map(|g| g.family_entries(name)).unwrap_or_default();
        if !bundled.is_empty() {
            let list: Vec<faces::FaceEntry> = bundled.iter().map(|e| faces::FaceEntry { weight: e.meta.weight, italic: e.meta.italic }).collect();
            let p = faces::pick_face(&list, want, italic != 0, false, false);
            let hit = bundled.iter().find(|e| e.meta.weight == p.weight && e.meta.italic == (p.italic && list.iter().any(|f| f.italic))).unwrap_or(&bundled[0]);
            m.flags = FACE_FOUND | FACE_BUNDLED;
            m.source = FONT_SRC_BUNDLED;
            m.weight = hit.meta.weight;
            m.style = if hit.meta.italic { STYLE_ITALIC } else { STYLE_NORMAL };
            m.simulations = p.sim;
            m.sha256 = hit.sha256;
            faces::fill_cstr(&mut m.family, &hit.meta.family);
            faces::fill_cstr(&mut m.ps_name, &hit.meta.ps_name);
            faces::fill_cstr(&mut m.version, &hit.meta.version);
            if let Some(raw) = hit.bytes.and_then(faces::file_metrics) {
                fill_metrics(&mut m, &raw);
            }
        } else if let Some(list) = dwr::system_faces(name).filter(|l| !l.is_empty()) {
            let p = faces::pick_face(&list, want, italic != 0, false, false);
            let Some(d) = dwr::describe(name, p.weight, p.italic) else { return E_PLATFORM };
            m.flags = FACE_FOUND | if d.variable { FACE_VARIABLE } else { 0 };
            m.source = FONT_SRC_SYSTEM;
            m.weight = d.weight;
            m.style = d.style;
            m.simulations = p.sim;
            faces::fill_cstr(&mut m.family, &d.family);
            faces::fill_cstr(&mut m.ps_name, &d.ps_name);
            faces::fill_cstr(&mut m.version, &d.version);
            faces::fill_cstr(&mut m.file_name, &d.file_name);
            if let Some(raw) = d.metrics {
                fill_metrics(&mut m, &raw);
                if m.cap_height == 0 {
                    m.cap_height = d.cap_height_dw;
                }
                if m.x_height == 0 {
                    m.x_height = d.x_height_dw;
                }
            }
            m.axis_count = d.axes.len().min(FACE_AXES_MAX) as u32;
            for (i, a) in d.axes.iter().take(FACE_AXES_MAX).enumerate() {
                m.axes[i] = *a;
            }
        }
        unsafe { *out = m };
        SWR_OK
    })
}

/// Fills `swr_system_fonts` from the system font set (shared by the export and the unit test).
fn system_fonts() -> Result<SystemFonts, Status> {
    let (family_count, entries) = dwr::system_summary().ok_or(E_PLATFORM)?;
    let mut s: SystemFonts = unsafe { std::mem::zeroed() };
    s.struct_size = std::mem::size_of::<SystemFonts>() as u32;
    s.family_count = family_count;
    let mut present = [false; SYSFONT_ENTRIES];
    for (i, e) in entries.iter().take(SYSFONT_ENTRIES).enumerate() {
        faces::fill_cstr(&mut s.entries[i].name, e.name);
        faces::fill_cstr(&mut s.entries[i].version, &e.version);
        s.entries[i].present = (e.faces > 0) as u32;
        s.entries[i].face_count = e.faces;
        present[i] = e.faces > 0;
    }
    if present[0] {
        s.flags |= SYSFONT_SEGOE_UI;
    }
    if present[1] && present[2] && present[3] {
        s.flags |= SYSFONT_SEGOE_VARIABLE;
    }
    if present[4] {
        s.flags |= SYSFONT_CASCADIA_MONO;
    }
    if present[5] {
        s.flags |= SYSFONT_SITKA;
    }
    if present[6] {
        s.flags |= SYSFONT_SEGOE_EMOJI;
    }
    if present[7] {
        s.flags |= SYSFONT_SEGOE_FLUENT_ICONS;
    }
    Ok(s)
}

/// Rev 0.8. Which of the families the host's font mapping asks about are installed, with versions. No window needed.
#[no_mangle]
pub extern "C" fn swr_system_font_info(out: *mut SystemFonts) -> Status {
    guard!({
        if out.is_null() {
            return E_BAD_ARG;
        }
        if unsafe { (*out).struct_size } < std::mem::size_of::<SystemFonts>() as u32 {
            return E_ABI;
        }
        match system_fonts() {
            Ok(s) => {
                unsafe { *out = s };
                SWR_OK
            }
            Err(e) => e,
        }
    })
}

#[cfg(test)]
mod v08_tests {
    use super::*;

    const TINOS: &[u8] = include_bytes!("../testdata/fonts/Tinos-Regular.ttf");

    fn req() -> MeasureRequestV08 {
        let mut r: MeasureRequestV08 = unsafe { std::mem::zeroed() };
        r.struct_size = std::mem::size_of::<MeasureRequestV08>() as u32;
        r.base.struct_size = std::mem::size_of::<MeasureRequest>() as u32;
        r
    }

    /// Registers the pinned Tinos Regular in the process registry (once; tests share it).
    fn ensure_tinos() -> font::Entry {
        let mut reg = font::REGISTRY.lock().unwrap();
        let sha = font::sha256(TINOS);
        if let Some(e) = reg.find_sha(&sha) {
            return e.clone();
        }
        let keep: &'static [u8] = Box::leak(TINOS.to_vec().into_boxed_slice());
        let mut e = reg.add(font::parse(TINOS).unwrap(), sha);
        reg.attach_bytes(e.handle, keep);
        e.bytes = Some(keep);
        e
    }

    #[test]
    fn kern_one_reaches_the_gpui_font_on_the_v08_path() {
        // G15: gpui/DirectWrite leave kerning off; the host sends kern=1 on every Windows run and the renderer must pass it on.
        let kern = [Feature { tag: tag(b'k', b'e', b'r', b'n'), value: 1 }];
        let mut r = req();
        r.feature_count = 1;
        r.features = kern.as_ptr();
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_eq!(p.ext.features, vec![("kern".to_string(), 1)]);
        assert_ne!(p.applied & M08_APPLIED_FEATURES, 0);
        let q = text::Request {
            ext: Some(&p.ext),
            text: "AVAWAY",
            family: "Segoe UI",
            locale: "en-US",
            weight: 400,
            direction: 0,
            color: 0,
            font_size: 14.0,
            line_height: 20.0,
            scale: 1.0,
            max_width: 0.0,
        };
        let f = text::build_font(&q);
        assert_eq!(f.features.tag_value_list(), &[("kern".to_string(), 1u32)]);
        // The 0.6 path is untouched: no features, no fallbacks, no italic.
        let legacy = text::build_font(&text::Request { ext: None, ..q });
        assert!(legacy.features.tag_value_list().is_empty());
        assert!(legacy.fallbacks.is_none());
        assert_eq!(legacy.weight.0, 400.0);
    }

    fn base<'a>(ext: Option<&'a text::Ext>) -> text::Request<'a> {
        text::Request {
            ext,
            text: "x",
            family: "Segoe UI",
            locale: "en-US",
            weight: 400,
            direction: 0,
            color: 0,
            font_size: 14.0,
            line_height: 20.0,
            scale: 1.0,
            max_width: 0.0,
        }
    }

    #[test]
    fn cache_key_separates_an_extension_and_keeps_the_06_key() {
        let plain = text::cache_key(&base(None));
        let kern = text::Ext { weight: 400.0, features: vec![("kern".into(), 1)], ..Default::default() };
        let track = text::Ext { weight: 400.0, track_dip: 1.0, ..Default::default() };
        let (a, b) = (text::cache_key(&base(Some(&kern))), text::cache_key(&base(Some(&track))));
        assert_ne!(plain, a);
        assert_ne!(a, b);
        assert_eq!(plain, text::cache_key(&base(None)));
    }

    #[test]
    fn limits_are_rejected_whole() {
        let many: Vec<Feature> = (0..17).map(|_| Feature { tag: tag(b'k', b'e', b'r', b'n'), value: 1 }).collect();
        let mut r = req();
        r.feature_count = 17;
        r.features = many.as_ptr();
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_TOO_LARGE));
        r.feature_count = 16;
        assert!(prepare(&r, "Segoe UI").is_ok());
        let mut r = req();
        r.fallback_count = 9;
        let s = [Str { ptr: b"Segoe UI".as_ptr() as *const _, len: 8, reserved: 0 }; 9];
        r.fallbacks = s.as_ptr();
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_TOO_LARGE));
        let mut r = req();
        r.feature_count = 1; // pointer left null
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_BAD_ARG));
        let bad = [Feature { tag: 0x0102_0304, value: 1 }];
        let mut r = req();
        r.feature_count = 1;
        r.features = bad.as_ptr();
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_BAD_ARG));
        let mut r = req();
        r.tracking_dip = f32::NAN;
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_BAD_ARG));
        let mut r = req();
        r.weight_f = 1001.0;
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_BAD_ARG));
        let empty = [Str { ptr: std::ptr::null(), len: 0, reserved: 0 }];
        let mut r = req();
        r.fallback_count = 1;
        r.fallbacks = empty.as_ptr();
        assert_eq!(prepare(&r, "Segoe UI").err(), Some(E_BAD_ARG));
    }

    #[test]
    fn unsupported_axes_are_ignored_and_reported_never_faked() {
        let mut r = req();
        r.width_axis = 87.5;
        r.opsz = 20.0;
        r.slant = 8.0;
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_eq!(p.ignored & (M08_IGN_WIDTH_AXIS | M08_IGN_OPSZ | M08_IGN_SLANT), M08_IGN_WIDTH_AXIS | M08_IGN_OPSZ | M08_IGN_SLANT);
        // wdth 100 and 0 are the default width: nothing to report.
        let mut r = req();
        r.width_axis = 100.0;
        assert_eq!(prepare(&r, "Segoe UI").unwrap().ignored & M08_IGN_WIDTH_AXIS, 0);
    }

    #[test]
    fn exact_weight_snaps_to_a_real_named_instance_of_an_installed_family() {
        // Static Segoe UI has Semibold 600 and Regular 400 (F0): a request for 500 resolves to a real instance and says so.
        let mut r = req();
        r.weight_f = 500.0;
        let p = prepare(&r, "Segoe UI").unwrap();
        assert!(p.pick.found);
        assert_eq!(p.pick.weight, 600);
        assert_eq!(p.ext.weight, 600.0);
        assert_ne!(p.ignored & M08_IGN_WEIGHT_SNAPPED, 0);
        assert_eq!(p.pick.sim, 0);
    }

    #[test]
    fn bundled_tinos_bold_is_simulated_unless_forbidden() {
        ensure_tinos();
        let mut r = req();
        r.weight_f = 700.0;
        let allow = prepare(&r, "Tinos").unwrap();
        assert_eq!(allow.pick.sim, SIMFLAG_BOLD);
        assert_eq!(allow.ext.weight, 700.0);
        r.simulations = SIM_FORBID_BOLD;
        let forbid = prepare(&r, "Tinos").unwrap();
        assert_eq!(forbid.pick.sim, 0);
        assert_eq!(forbid.ext.weight, 400.0);
        assert_ne!(forbid.ignored & M08_IGN_SIM_BOLD_DROPPED, 0);
        let mut r = req();
        r.italic = 1;
        r.simulations = SIM_FORBID_OBLIQUE;
        let up = prepare(&r, "Tinos").unwrap();
        assert!(!up.ext.italic);
        assert_ne!(up.ignored & M08_IGN_SIM_OBLIQUE_DROPPED, 0);
    }

    #[test]
    fn private_fallback_is_reported_and_system_fallback_is_kept() {
        ensure_tinos();
        let names = [Str { ptr: b"Tinos".as_ptr() as *const _, len: 5, reserved: 0 }, Str { ptr: b"Segoe UI".as_ptr() as *const _, len: 8, reserved: 0 }];
        let mut r = req();
        r.fallback_count = 2;
        r.fallbacks = names.as_ptr();
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_ne!(p.ignored & M08_IGN_FALLBACK_PRIVATE, 0, "a bundled family cannot be a fallback in gpui (G13)");
        assert_eq!(p.ext.fallbacks, vec!["Segoe UI".to_string()]);
        // A family that is not installed is reported the same way (gpui would log and skip it).
        let ghost = [Str { ptr: b"No Such Family SRProbe".as_ptr() as *const _, len: 22, reserved: 0 }];
        let mut r = req();
        r.fallback_count = 1;
        r.fallbacks = ghost.as_ptr();
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_ne!(p.ignored & M08_IGN_FALLBACK_PRIVATE, 0);
        assert!(p.ext.fallbacks.is_empty());
    }

    #[test]
    fn baseline_flag_and_tracking_sum() {
        let mut r = req();
        r.tracking_dip = 1.5;
        r.kerning_dip = 0.5;
        r.baseline_offset_dip = 0.0;
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_eq!(p.ext.track_dip, 2.0);
        assert_eq!(p.ext.baseline_dip, None, "0 is a legal offset only with the flag set");
        r.flags = M08_BASELINE_OFFSET;
        let p = prepare(&r, "Segoe UI").unwrap();
        assert_eq!(p.ext.baseline_dip, Some(0.0));
        assert_ne!(p.applied & M08_APPLIED_BASELINE, 0);
    }

    fn rec(primary: bool, notdef: u32, gid: u32) -> text::RunRec {
        text::RunRec { font_id: if primary { 1 } else { 2 }, primary, req_family: primary.then(|| "Tinos".to_string()), utf8_start: 0, utf8_len: 3, glyphs: 3, notdef, first_char: 'A' as u32, first_gid: gid, ..Default::default() }
    }

    fn measured(family: &str, runs: Vec<text::RunRec>) -> text::Measured {
        text::Measured {
            text: "abc".into(),
            wrapped: vec![],
            cells: vec![],
            lines: vec![],
            width: 0.0,
            height: 0.0,
            first_baseline: 0.0,
            last_baseline: 0.0,
            line_height_dip: 20.0,
            scale: 1.0,
            char_count: 3,
            key: 1,
            ext: text::MeasuredExt {
                runs,
                face: text::FaceReq { family: family.into(), weight: 400.0, italic: false, sim: 0, fallbacks: vec![] },
                ..Default::default()
            },
        }
    }

    #[test]
    fn run_faces_name_the_registered_hash_for_bundled_tinos() {
        let tinos = ensure_tinos();
        let faces = build_run_faces(&measured("Tinos", vec![rec(true, 0, 36)]));
        assert_eq!(faces.len(), 1);
        let f = &faces[0];
        assert_eq!(f.flags & (RUNFACE_PRIMARY | RUNFACE_BUNDLED), RUNFACE_PRIMARY | RUNFACE_BUNDLED);
        assert_eq!(f.sha256, tinos.sha256, "the per-run face hash equals the registered file's SHA-256");
        assert_eq!(f.sha256, font::sha256(TINOS));
        assert_eq!(&f.family[..5], b"Tinos");
        assert_eq!(&f.ps_name[..13], b"Tinos-Regular");
        assert_eq!(f.weight, 400);
        assert_eq!(f.notdef_count, 0);
        assert_eq!(f.flags & RUNFACE_FALLBACK, 0);
    }

    #[test]
    fn run_faces_report_notdef_for_an_unmapped_code_point() {
        // Negative control (F0: U+0378 in a Latin-only font gives glyph id 0): the .notdef count is passed through, and a fallback
        // run that no system candidate maps is UNRESOLVED with no sha256 and an empty family, never a guessed name.
        ensure_tinos();
        let faces = build_run_faces(&measured("Tinos", vec![rec(true, 1, 0), rec(false, 2, 0)]));
        assert_eq!(faces.len(), 2);
        assert_eq!(faces[0].notdef_count, 1);
        assert_eq!(faces[1].notdef_count, 2);
        assert_ne!(faces[1].flags & RUNFACE_FALLBACK, 0);
        assert_ne!(faces[1].flags & RUNFACE_UNRESOLVED, 0);
        assert_eq!(faces[1].sha256, [0u8; 32]);
        assert_eq!(faces[1].family[0], 0);
    }

    #[test]
    fn run_faces_of_an_installed_family_carry_file_and_version() {
        let faces = build_run_faces(&measured("Segoe UI", vec![rec(true, 0, 36)]));
        let f = &faces[0];
        assert_ne!(f.flags & RUNFACE_SYSTEM, 0);
        assert_eq!(f.flags & RUNFACE_BUNDLED, 0);
        assert_ne!(f.version[0], 0);
        assert_ne!(f.ps_name[0], 0);
        assert_eq!(f.sha256, [0u8; 32], "installed faces have no registered hash");
    }

    #[test]
    fn face_metrics_of_bundled_tinos_come_from_the_registered_bytes() {
        let tinos = ensure_tinos();
        let mut out: FaceMetrics = unsafe { std::mem::zeroed() };
        out.struct_size = std::mem::size_of::<FaceMetrics>() as u32;
        let rc = swr_font_face_metrics(b"tinos".as_ptr(), 5, 400, 0, 0, &mut out);
        assert_eq!(rc, SWR_OK);
        assert_eq!(out.flags, FACE_FOUND | FACE_BUNDLED);
        assert_eq!(out.source, FONT_SRC_BUNDLED);
        assert_eq!((out.units_per_em, out.hhea_ascent, out.hhea_descent, out.hhea_line_gap), (2048, 1825, -443, 87));
        assert_eq!(out.sha256, tinos.sha256);
        assert_eq!(out.simulations, 0);
        // A bold request on Regular-only Tinos reports the simulation DirectWrite would apply.
        let rc = swr_font_face_metrics(b"Tinos".as_ptr(), 5, 700, 0, 0, &mut out);
        assert_eq!((rc, out.simulations), (SWR_OK, SIMFLAG_BOLD));
        // Too small a struct is refused whole.
        let mut small: FaceMetrics = unsafe { std::mem::zeroed() };
        small.struct_size = 8;
        assert_eq!(swr_font_face_metrics(b"Tinos".as_ptr(), 5, 400, 0, 0, &mut small), E_ABI);
    }

    #[test]
    fn face_metrics_of_an_unknown_family_say_not_found() {
        let mut out: FaceMetrics = unsafe { std::mem::zeroed() };
        out.struct_size = std::mem::size_of::<FaceMetrics>() as u32;
        let name = b"No Such Family SRProbe";
        assert_eq!(swr_font_face_metrics(name.as_ptr(), name.len() as u32, 400, 0, 0, &mut out), SWR_OK);
        assert_eq!(out.flags, 0);
        assert_eq!(out.source, FONT_SRC_FALLBACK);
    }

    #[test]
    fn face_metrics_of_segoe_ui_come_from_directwrite() {
        let mut out: FaceMetrics = unsafe { std::mem::zeroed() };
        out.struct_size = std::mem::size_of::<FaceMetrics>() as u32;
        let name = b"Segoe UI";
        assert_eq!(swr_font_face_metrics(name.as_ptr(), name.len() as u32, 400, 0, 0, &mut out), SWR_OK);
        assert_eq!(out.flags & FACE_FOUND, FACE_FOUND);
        assert_eq!(out.source, FONT_SRC_SYSTEM);
        assert_eq!(out.units_per_em, 2048);
        assert!(out.hhea_ascent > 0 && out.hhea_descent < 0);
        assert_ne!(out.ps_name[0], 0);
        assert_ne!(out.file_name[0], 0);
        assert_eq!(out.sha256, [0u8; 32]);
    }

    #[test]
    fn system_info_flags_follow_the_entries() {
        let s = system_fonts().unwrap();
        assert_eq!(s.struct_size, 720);
        assert_eq!(&s.entries[0].name[..8], b"Segoe UI");
        assert_eq!(s.flags & SYSFONT_SEGOE_UI != 0, s.entries[0].present != 0);
        assert_eq!(s.flags & SYSFONT_SITKA != 0, s.entries[5].present != 0);
        assert_eq!(s.flags & SYSFONT_SEGOE_VARIABLE != 0, s.entries[1].present != 0 && s.entries[2].present != 0 && s.entries[3].present != 0);
        assert!(s.family_count > 10);
    }

    #[test]
    fn discovery_exports_describe_the_08_view_and_leave_the_07_view_alone() {
        let mut b: BootstrapInfoV08 = unsafe { std::mem::zeroed() };
        assert_eq!(swr_bootstrap_query_v08(&mut b, 119), E_BAD_ARG, "a caller smaller than the view gets nothing");
        assert_eq!(swr_bootstrap_query_v08(&mut b, 120), SWR_OK);
        assert_eq!(b.v07.base.abi_minor, 8);
        assert_eq!(b.v07.base.api_table_size, 184);
        assert_eq!(b.v07.base.fn_count, 22);
        assert_eq!(b.measure_request_v08_size, 160);
        assert_eq!(b.measure_result_v08_size, 88);
        assert_eq!((b.run_face_size, b.face_metrics_size, b.system_fonts_size), (296, 456, 720));
        // The 0.7 and 0.6 views are exactly what they were.
        let mut v7: BootstrapInfoV07 = unsafe { std::mem::zeroed() };
        assert_eq!(swr_bootstrap_query_v07(&mut v7, 96), SWR_OK);
        assert_eq!((v7.base.abi_minor, v7.base.api_table_size, v7.base.fn_count), (7, 152, 18));
        let mut v6: BootstrapInfo = unsafe { std::mem::zeroed() };
        assert_eq!(swr_bootstrap_query(&mut v6, 88), SWR_OK);
        assert_eq!((v6.abi_minor, v6.api_table_size, v6.fn_count), (6, 136, 16));
        // The 0.8 table is the 0.7 table's functions at the same offsets plus four more.
        let mut t8: std::mem::MaybeUninit<ApiV08> = std::mem::MaybeUninit::uninit();
        assert_eq!(swr_get_api_v08(t8.as_mut_ptr(), 183), E_ABI);
        assert_eq!(swr_get_api_v08(t8.as_mut_ptr(), 184), SWR_OK);
        let t8 = unsafe { t8.assume_init() };
        let mut t7: std::mem::MaybeUninit<ApiV07> = std::mem::MaybeUninit::uninit();
        assert_eq!(swr_get_api_v07(t7.as_mut_ptr(), 152), SWR_OK);
        let t7 = unsafe { t7.assume_init() };
        assert_eq!(t8.commit as usize, t7.commit as usize);
        assert_eq!(t8.font_register as usize, t7.font_register as usize);
        assert_eq!(t8.measure_text as usize, t7.measure_text as usize);
        assert_eq!(t8.struct_size, 184);
    }
}

// Keep the type referenced so a future unused-warning does not hide ABI drift.
#[allow(dead_code)]
fn _abi_anchor(_: *mut c_void) {}
