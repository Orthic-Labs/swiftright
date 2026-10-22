//! The GPUI side: window, paint of the committed snapshot, input -> events, IME text
//! store bridging (IMM32 path through GPUI's InputHandler), the display-driven frame
//! clock and the foreground-executor drain task. UI thread only.
//!
//! Borrow discipline: nothing here calls the host while GPUI app/window borrows are
//! held, EXCEPT the ime_* callbacks, which GPUI invokes inside its own input handling.
//! Those go through the same non-reentrant guard and only touch Rust-owned state.

use std::cell::RefCell;
use std::ffi::c_void;
use std::ops::Range;
use std::sync::atomic::{AtomicI32, AtomicI64, AtomicU32, AtomicU64, Ordering::SeqCst};
use std::sync::{Arc, Mutex};

use accesskit_windows::{SubclassingAdapter, HWND as AkHWND};
use gpui::{
    canvas, div, fill, point, prelude::*, px, rgba, size, App, AsyncApp, Application, Bounds,
    ContentMask, Context, Corners, ElementInputHandler, Entity, EntityInputHandler, FocusHandle,
    IntoElement, KeyDownEvent, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, Pixels, Render,
    RenderImage, TextAlign, TitlebarOptions, UTF16Selection, Window, WindowBackgroundAppearance,
    WindowBounds, WindowHandle, WindowOptions, WindowTextSystem,
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::abi::*;
use crate::ax::{Actions, Activation};
use crate::pace;
use crate::paths::{Cap, Join, PathData, Seg};
use crate::rt::*;
use crate::scale;
use crate::text::{RunSlab, Slab, TextCache, TrackedImage, MAX_RUNS};
use crate::trace;
use crate::tree::{Prim, Tree};
use crate::tsf;

#[link(name = "user32")]
extern "system" {
    fn MessageBoxW(hwnd: *mut c_void, text: *const u16, caption: *const u16, utype: u32) -> i32;
    fn GetWindowLongPtrW(hwnd: *mut c_void, index: i32) -> isize;
    fn GetClientRect(hwnd: *mut c_void, rect: *mut [i32; 4]) -> i32;
    fn GetDpiForWindow(hwnd: *mut c_void) -> u32;
    fn SetProcessDpiAwarenessContext(context: isize) -> i32;
    // Rev 0.6 popup menu.
    fn CreatePopupMenu() -> *mut c_void;
    fn AppendMenuW(menu: *mut c_void, flags: u32, id: usize, text: *const u16) -> i32;
    fn TrackPopupMenu(
        menu: *mut c_void,
        flags: u32,
        x: i32,
        y: i32,
        reserved: i32,
        hwnd: *mut c_void,
        rect: *const c_void,
    ) -> i32;
    fn DestroyMenu(menu: *mut c_void) -> i32;
    fn ClientToScreen(hwnd: *mut c_void, pt: *mut [i32; 2]) -> i32;
    fn GetCursorPos(pt: *mut [i32; 2]) -> i32;
    fn SetForegroundWindow(hwnd: *mut c_void) -> i32;
    fn PostMessageW(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> i32;
    // Rev 0.10: the primary monitor's DPI, to size the window before it exists when an explicit render scale is set.
    fn MonitorFromPoint(pt: WinPoint, flags: u32) -> *mut c_void;
}

#[repr(C)]
#[derive(Clone, Copy)]
struct WinPoint {
    x: i32,
    y: i32,
}

#[link(name = "shcore")]
extern "system" {
    fn GetDpiForMonitor(monitor: *mut c_void, dpi_type: i32, dpi_x: *mut u32, dpi_y: *mut u32) -> i32;
}

/// The primary monitor's effective DPI over 96 (GPUI opens the window on the primary display), or 1.0 when it cannot be read.
fn primary_monitor_scale() -> f32 {
    const MONITOR_DEFAULTTOPRIMARY: u32 = 1;
    const MDT_EFFECTIVE_DPI: i32 = 0;
    let mon = unsafe { MonitorFromPoint(WinPoint { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY) };
    if mon.is_null() {
        return 1.0;
    }
    let (mut x, mut y) = (0u32, 0u32);
    let hr = unsafe { GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &mut x, &mut y) };
    if hr != 0 || x == 0 {
        1.0
    } else {
        x as f32 / 96.0
    }
}

type TaskDialogCallback = unsafe extern "system" fn(*mut c_void, u32, usize, isize, isize) -> i32;

// commctrl.h declares TASKDIALOGCONFIG and TASKDIALOG_BUTTON under #include <pshpack1.h>
// (windows-0.61.3 Controls/mod.rs: `#[repr(C, packed(1))]`). Natural alignment moves
// hwndParent from offset 4 to 8 and TaskDialogIndirect returns E_INVALIDARG (found and fixed
// in probes/sr0-b/modal-loop, RESULT.md). cbSize is size_of::<Self>() of the packed layout.
#[repr(C, packed(1))]
struct TaskDialogConfig {
    cb_size: u32,
    hwnd_parent: *mut c_void,
    h_instance: *mut c_void,
    flags: u32,
    common_buttons: u32,
    window_title: *const u16,
    main_icon: *const u16,
    main_instruction: *const u16,
    content: *const u16,
    buttons_count: u32,
    buttons: *const TaskDialogButton,
    default_button: i32,
    radio_count: u32,
    radios: *const c_void,
    default_radio: i32,
    verification_text: *const u16,
    expanded_info: *const u16,
    expanded_control: *const u16,
    collapsed_control: *const u16,
    footer_icon: *const u16,
    footer: *const u16,
    callback: Option<TaskDialogCallback>,
    callback_data: isize,
    width: u32,
}

#[repr(C, packed(1))]
struct TaskDialogButton {
    id: i32,
    text: *const u16,
}

// Both packed structs must stay the commctrl.h x64 sizes (cbSize 160 / 12 bytes).
const _: () = assert!(std::mem::size_of::<TaskDialogConfig>() == 160);
const _: () = assert!(std::mem::size_of::<TaskDialogButton>() == 12);

#[link(name = "comctl32")]
extern "system" {
    fn TaskDialogIndirect(
        cfg: *const TaskDialogConfig,
        button: *mut i32,
        radio: *mut i32,
        verified: *mut i32,
    ) -> i32;
}

const MF_GRAYED: u32 = 0x1;
const MF_CHECKED: u32 = 0x8;
const MF_SEPARATOR: u32 = 0x800;
const TPM_RIGHTBUTTON: u32 = 0x2;
const TPM_NONOTIFY: u32 = 0x80;
const TPM_RETURNCMD: u32 = 0x100;
const TDF_ALLOW_DIALOG_CANCELLATION: u32 = 0x8;
const TDF_POSITION_RELATIVE_TO_WINDOW: u32 = 0x1000;
const WM_NULL: u32 = 0;
/// TaskDialog custom button ids are TD_BUTTON_BASE + item index (clear of IDOK/IDCANCEL...).
const TD_BUTTON_BASE: i32 = 100;

// ------------------------------------------------------------ UI-thread state

pub struct Ui {
    pub text_system: Option<Arc<WindowTextSystem>>,
    pub runs: RunSlab,
    /// Rev 0.6: registered swr_image handles (RGBA8 copied into GPUI RenderImages, BGRA).
    pub images: Slab<TrackedImage>,
    pub cache: TextCache,
    pub tree: Tree,
}

thread_local! {
    static UI: RefCell<Ui> = RefCell::new(Ui {
        text_system: None,
        runs: Slab::new(&LIVE_RUNS, MAX_RUNS),
        images: Slab::new(&IMAGE_HANDLES, IMAGE_MAX_LIVE),
        cache: TextCache::new(),
        tree: Tree::default(),
    });
}

/// Runs `f` on the UI-thread state. Never panics on a nested borrow: returns E_BUSY.
pub fn with_ui<R>(f: impl FnOnce(&mut Ui) -> R) -> Result<R, Status> {
    UI.with(|u| match u.try_borrow_mut() {
        Ok(mut g) => Ok(f(&mut g)),
        Err(_) => Err(E_BUSY),
    })
}

static PAINTS_INACTIVE: AtomicU64 = AtomicU64::new(0);
static OPEN_FAILED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub struct ModalItemOwned {
    pub id: u32,
    pub text: String,
    pub flags: u32,
}

pub struct ModalPending {
    pub id: u64,
    pub kind: u32,
    pub buttons: u32,
    pub title: String,
    pub message: String,
    pub items: Vec<ModalItemOwned>,
    pub x: f32,
    pub y: f32,
    pub default_item: u32,
}
static MODAL: Mutex<Option<ModalPending>> = Mutex::new(None);

/// WM_APP + 0x5A2 (WM_SWR_PAINT in pace.rs is + 0x5A1): posted to the main window by the drain task when a modal request is
/// pending. The subclass handler runs the modal from the thread's top-level DispatchMessage, outside every GPUI foreground drain.
pub const WM_SWR_MODAL: u32 = 0x8000 + 0x5A2;
/// A WM_SWR_MODAL is in flight (posted, handler not yet entered): at most one is posted per pending request.
static MODAL_POSTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// QPC at the post, for the `queued_ms` field of the modal log line.
static MODAL_POSTED_QPC: AtomicI64 = AtomicI64::new(0);
static MODAL_LEGACY_SPAWN: std::sync::OnceLock<bool> = std::sync::OnceLock::new();

/// Diagnostic toggle (environment, read once): `SWR_MODAL_LEGACY_SPAWN=1` starts modals the old way, as a GPUI foreground runnable
/// (`cx.spawn(run_modal)`), so the lost-wake stall can be reproduced for an A/B proof. Default: the posted-message path.
fn modal_legacy_spawn() -> bool {
    *MODAL_LEGACY_SPAWN.get_or_init(|| {
        let v = std::env::var("SWR_MODAL_LEGACY_SPAWN").map(|v| v.trim() == "1").unwrap_or(false);
        eprintln!("[swiftright-render] modal start path: {}", if v { "spawn (SWR_MODAL_LEGACY_SPAWN=1, diagnostic)" } else { "posted (WM_SWR_MODAL)" });
        v
    })
}

/// Posts WM_SWR_MODAL to the main window, once per pending request. True when a start message is in flight (posted now or
/// earlier); false when it could not be posted (the caller then starts the modal the legacy way so the request is not lost).
fn post_modal_start() -> bool {
    if MODAL_POSTED.swap(true, SeqCst) {
        return true;
    }
    MODAL_POSTED_QPC.store(qpc_now(), SeqCst);
    let hwnd = MAIN_HWND.load(SeqCst) as *mut c_void;
    let posted = !hwnd.is_null() && unsafe { PostMessageW(hwnd, WM_SWR_MODAL, 0, 0) } != 0;
    if !posted {
        MODAL_POSTED.store(false, SeqCst);
    }
    posted
}

/// WM_SWR_MODAL handler (main window subclass, UI thread, top-level dispatch): takes the pending request and runs it.
/// A request that arrives after shutdown began is dropped, as the drain task always did.
fn on_modal_message() {
    MODAL_POSTED.store(false, SeqCst);
    let queued = MODAL_POSTED_QPC.load(SeqCst);
    let pending = MODAL.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(req) = pending {
        if !SHUTDOWN.load(SeqCst) {
            // A panic must not unwind out of the window procedure.
            if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_modal(req, "posted", queued))).is_err() {
                eprintln!("[swiftright-render] modal panicked (path=posted)");
            }
        }
    }
}

/// Images released by the host: their GPUI sprite-atlas entries are removed at the start of
/// the next paint (Window::drop_image needs the window).
static DROPPED_IMAGES: Mutex<Vec<Arc<RenderImage>>> = Mutex::new(Vec::new());

pub fn queue_image_drop(img: Arc<RenderImage>) {
    DROPPED_IMAGES.lock().unwrap_or_else(|e| e.into_inner()).push(img);
}

pub fn queue_modal(p: ModalPending) -> Status {
    let mut m = MODAL.lock().unwrap_or_else(|e| e.into_inner());
    if m.is_some() {
        return E_QUEUE_FULL;
    }
    *m = Some(p);
    drop(m);
    signal_notify();
    SWR_OK
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Result of a MENU / DIALOG: (item id, item index); (0, -1) = dismissed, (0, -2) = failed.
type ItemResult = (i32, i32);

/// TrackPopupMenu at the client-px anchor. Command ids are index + 1 (0 = dismissed).
fn run_menu(req: &ModalPending) -> ItemResult {
    let owner = MAIN_HWND.load(SeqCst) as *mut c_void;
    if owner.is_null() {
        return (0, -2);
    }
    unsafe {
        let menu = CreatePopupMenu();
        if menu.is_null() {
            return (0, -2);
        }
        for (i, it) in req.items.iter().enumerate() {
            if it.flags & MODAL_ITEM_SEPARATOR != 0 {
                AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
                continue;
            }
            let mut f = 0u32; // MF_STRING
            if it.flags & MODAL_ITEM_DISABLED != 0 {
                f |= MF_GRAYED;
            }
            if it.flags & MODAL_ITEM_CHECKED != 0 {
                f |= MF_CHECKED;
            }
            let t = wide(&it.text);
            AppendMenuW(menu, f, i + 1, t.as_ptr());
        }
        let mut pt = [req.x as i32, req.y as i32];
        if req.x < 0.0 && req.y < 0.0 {
            GetCursorPos(&mut pt);
        } else {
            ClientToScreen(owner, &mut pt);
        }
        // The owner must be foreground or the menu does not dismiss on an outside click.
        SetForegroundWindow(owner);
        let cmd = TrackPopupMenu(
            menu,
            TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
            pt[0],
            pt[1],
            0,
            owner,
            std::ptr::null(),
        );
        PostMessageW(owner, WM_NULL, 0, 0);
        DestroyMenu(menu);
        if cmd >= 1 && (cmd as usize) <= req.items.len() {
            let idx = cmd as usize - 1;
            (req.items[idx].id as i32, idx as i32)
        } else {
            (0, -1)
        }
    }
}

/// TaskDialogIndirect with custom buttons (ids TD_BUTTON_BASE + index).
fn run_dialog(req: &ModalPending) -> ItemResult {
    let owner = MAIN_HWND.load(SeqCst) as *mut c_void;
    let title = wide(&req.title);
    let content = wide(&req.message);
    let texts: Vec<Vec<u16>> = req.items.iter().map(|i| wide(&i.text)).collect();
    let buttons: Vec<TaskDialogButton> = texts
        .iter()
        .enumerate()
        .map(|(i, t)| TaskDialogButton { id: TD_BUTTON_BASE + i as i32, text: t.as_ptr() })
        .collect();
    let cfg = TaskDialogConfig {
        cb_size: std::mem::size_of::<TaskDialogConfig>() as u32,
        hwnd_parent: owner,
        h_instance: std::ptr::null_mut(),
        flags: TDF_ALLOW_DIALOG_CANCELLATION
            | if owner.is_null() { 0 } else { TDF_POSITION_RELATIVE_TO_WINDOW },
        common_buttons: 0,
        window_title: title.as_ptr(),
        main_icon: std::ptr::null(),
        main_instruction: std::ptr::null(),
        content: content.as_ptr(),
        buttons_count: buttons.len() as u32,
        buttons: buttons.as_ptr(),
        default_button: TD_BUTTON_BASE + req.default_item as i32,
        radio_count: 0,
        radios: std::ptr::null(),
        default_radio: 0,
        verification_text: std::ptr::null(),
        expanded_info: std::ptr::null(),
        expanded_control: std::ptr::null(),
        collapsed_control: std::ptr::null(),
        footer_icon: std::ptr::null(),
        footer: std::ptr::null(),
        callback: None,
        callback_data: 0,
        width: 0,
    };
    let mut pressed = 0i32;
    let hr = unsafe {
        TaskDialogIndirect(&cfg, &mut pressed, std::ptr::null_mut(), std::ptr::null_mut())
    };
    if hr < 0 {
        eprintln!("[swiftright-render] TaskDialogIndirect hr={:#x}", hr as u32);
        return (0, -2);
    }
    let idx = pressed - TD_BUTTON_BASE;
    if idx >= 0 && (idx as usize) < req.items.len() {
        (req.items[idx as usize].id as i32, idx)
    } else {
        (0, -1)
    }
}

/// Runs one modal (TrackPopupMenu / TaskDialogIndirect / MessageBoxW); it blocks in the OS modal loop until dismissed.
/// `path`: "posted" = the WM_SWR_MODAL handler (top-level DispatchMessage: no GPUI drain is on the stack, so a drain-task wake
/// runnable can still run while the modal pumps), "spawn" = the legacy GPUI foreground runnable (the modal then runs INSIDE a
/// drain of the foreground queue; a wake runnable queued behind it in the same drain snapshot cannot run until the modal returns).
/// `queued_qpc`: when the start was posted or spawned. No App/Window borrow and no host callback is active here.
/// Logs one line per modal: `waker_none` is the drain task's waker slot at entry (true = a wake already took it, or the drain task
/// is being polled), `wakes_during` / `drain_calls_during` are the host-wake and host-drain counter deltas across the modal
/// (`drain_calls_during=0` with `wakes_during>0` is the stall).
fn run_modal(req: ModalPending, path: &'static str, queued_qpc: i64) {
    let t_enter = qpc_now();
    let waker_none = signal_waker_is_none();
    let wakes0 = stat(S_WAKES);
    let drains0 = stat(S_DRAIN_CALLS);
    let mut ev = Event::new(EV_MODAL_RESULT, 0);
    ev.arg = req.id;
    match req.kind {
        MODAL_MENU => {
            let (id, idx) = run_menu(&req);
            ev.action = MODAL_MENU;
            ev.i0 = id;
            ev.i1 = idx;
        }
        MODAL_DIALOG => {
            let (id, idx) = run_dialog(&req);
            ev.action = MODAL_DIALOG;
            ev.i0 = id;
            ev.i1 = idx;
        }
        _ => {
            let utype = match req.buttons {
                2 => 1u32, // MB_OKCANCEL
                3 => 4u32, // MB_YESNO
                _ => 0u32, // MB_OK
            };
            let t = wide(&req.title);
            let m = wide(&req.message);
            let owner = MAIN_HWND.load(SeqCst) as *mut c_void;
            ev.i0 = unsafe { MessageBoxW(owner, m.as_ptr(), t.as_ptr(), utype) };
        }
    }
    let t_exit = qpc_now();
    eprintln!(
        "[swiftright-render] modal id={} kind={} path={} waker_none={} queued_ms={:.2} elapsed_ms={:.2} wakes_during={} drain_calls_during={} i0={} i1={}",
        req.id,
        match req.kind {
            MODAL_MENU => "menu",
            MODAL_DIALOG => "dialog",
            _ => "message",
        },
        path,
        waker_none,
        qpc_to_ns(t_enter - queued_qpc) as f64 / 1e6,
        qpc_to_ns(t_exit - t_enter) as f64 / 1e6,
        stat(S_WAKES) - wakes0,
        stat(S_DRAIN_CALLS) - drains0,
        ev.i0,
        ev.i1
    );
    push_event(ev);
}

// ------------------------------------------------------------------ the view

pub struct RootView {
    focus: FocusHandle,
    adapter: Option<SubclassingAdapter>,
}

/// AccessKit publication policy (environment, read once). `SWR_AX_OFF=1`: never publish (diagnostics: tells whether the AX / UIA side is
/// what grows the process). `SWR_AX_MIN_MS=<n>`: publish at most every n milliseconds; the newest snapshot is always published after the
/// interval (a trailing publish), so a client sees every state within n ms. Default `DEFAULT_AX_MIN_MS`; 0 = every committed snapshot.
/// R10 (Dell): with a UIA client attached an AX publication costs 1.2 ms of UI thread and ~400 allocations per node-batch, 87 times a second
/// (a tenth of the UI thread, a third of the process heap churn, ~1 MB/min of private-bytes growth); at 100 ms the cost is 0.14 ms/commit.
const DEFAULT_AX_MIN_MS: f64 = 100.0;

struct AxPolicy {
    off: bool,
    min_ticks: i64,
}

static AX_POLICY: std::sync::OnceLock<AxPolicy> = std::sync::OnceLock::new();
static AX_LAST_PUBLISH: AtomicI64 = AtomicI64::new(0);
static AX_TRAILING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub static AX_PUBLISHES: AtomicU64 = AtomicU64::new(0);
pub static AX_THROTTLED: AtomicU64 = AtomicU64::new(0);
/// Trailing-publish wakes that were throttled again (the timer fired before the interval was over) and re-armed.
pub static AX_RETHROTTLED: AtomicU64 = AtomicU64::new(0);

/// Throttle decision (pure: no clock, no statics). `Some(ticks)` = the interval since the last publish is not over yet and `ticks` remain.
fn ax_throttle_rest(now: i64, last: i64, min_ticks: i64) -> Option<i64> {
    if min_ticks > 0 && last != 0 && now - last < min_ticks {
        Some(min_ticks - (now - last))
    } else {
        None
    }
}

/// Floor on a trailing wait: a timer that fires early must not turn the retry into a busy loop.
fn ax_retry_wait(rest_ns: u64) -> std::time::Duration {
    std::time::Duration::from_nanos(rest_ns.max(1_000_000))
}

fn ax_policy() -> &'static AxPolicy {
    AX_POLICY.get_or_init(|| {
        let off = std::env::var("SWR_AX_OFF").map(|v| v.trim() == "1").unwrap_or(false);
        let ms = std::env::var("SWR_AX_MIN_MS").ok().and_then(|v| v.trim().parse::<f64>().ok()).unwrap_or(DEFAULT_AX_MIN_MS).max(0.0);
        let min_ticks = (ms * qpc_freq() as f64 / 1000.0) as i64;
        if off || min_ticks > 0 {
            eprintln!("[swiftright-render] ax publication policy: off={off} min_interval_ms={ms}");
        }
        AxPolicy { off, min_ticks }
    })
}

impl RootView {
    /// One publication per committed snapshot (a repaint or a tick without a commit changes nothing for AccessKit), subject to the AX policy.
    /// Returns the time to wait before the throttled snapshot may be published (the caller schedules the trailing publish).
    fn publish_ax(&mut self) -> Option<std::time::Duration> {
        let version = SNAPSHOT.load(SeqCst);
        if AX_PUBLISHED.load(SeqCst) == version {
            return None;
        }
        let pol = ax_policy();
        if pol.off {
            AX_PUBLISHED.store(version, SeqCst);
            return None;
        }
        if pol.min_ticks > 0 {
            let now = qpc_now();
            let last = AX_LAST_PUBLISH.load(SeqCst);
            if let Some(rest) = ax_throttle_rest(now, last, pol.min_ticks) {
                AX_THROTTLED.fetch_add(1, SeqCst);
                return Some(ax_retry_wait(qpc_to_ns(rest)));
            }
            AX_LAST_PUBLISH.store(now, SeqCst);
        }
        AX_PUBLISHED.store(version, SeqCst);
        AX_PUBLISHES.fetch_add(1, SeqCst);
        if let Some(a) = self.adapter.as_mut() {
            if let Some(events) = a.update_if_active(crate::ax::build_tree) {
                events.raise();
            }
        }
        None
    }
}

fn mods(m: &gpui::Modifiers) -> u32 {
    (m.control as u32 * MOD_CTRL)
        | (m.alt as u32 * MOD_ALT)
        | (m.shift as u32 * MOD_SHIFT)
        | (m.platform as u32 * MOD_PLATFORM)
}

fn on_key_down(ev: &KeyDownEvent) {
    let win = LIVE_WINDOW.load(SeqCst);
    if win == 0 {
        return;
    }
    let ks = &ev.keystroke;
    let key = ks.key.as_bytes();
    let kc = ks.key_char.as_deref().unwrap_or("").as_bytes();
    let mut e = Event::new(EV_KEY, KEY_DOWN);
    e.window = win;
    e.node = FOCUS_NODE.load(SeqCst);
    e.snapshot = SNAPSHOT.load(SeqCst);
    e.modifiers = mods(&ks.modifiers);
    let kn = copy_text(&mut e.text, 0, &key[..key.len().min(31)]);
    let cn = copy_text(&mut e.text, kn, &kc[..kc.len().min(EVENT_TEXT_CAP - kn)]);
    e.i1 = kn as i32;
    e.i0 = cn as i32;
    e.text_len = (kn + cn) as u32;
    push_event(e);
}

fn on_pointer(action: u32, p: gpui::Point<Pixels>, m: &gpui::Modifiers, clicks: usize, scale: f32) {
    let win = LIVE_WINDOW.load(SeqCst);
    if win == 0 {
        return;
    }
    let x = f32::from(p.x) * scale;
    let y = f32::from(p.y) * scale;
    let node = with_ui(|ui| ui.tree.hit(x, y)).unwrap_or(0);
    let mut e = Event::new(EV_POINTER, action);
    e.window = win;
    e.node = node;
    e.snapshot = SNAPSHOT.load(SeqCst);
    e.x = x;
    e.y = y;
    e.i0 = 0;
    e.i1 = clicks as i32;
    e.modifiers = mods(m);
    push_event(e);
}

/// Rev 0.9: a pointer move (hover, drag) for a host that asked for them. The hit node is the one under the pointer; `left_down`
/// says the primary button is held. Identical consecutive positions are dropped.
static LAST_MOVE: std::sync::Mutex<(i64, i64, bool)> = std::sync::Mutex::new((i64::MIN, i64::MIN, false));

fn on_pointer_move(p: gpui::Point<Pixels>, left_down: bool, m: &gpui::Modifiers, scale: f32) {
    if !POINTER_MOVES.load(SeqCst) {
        return;
    }
    let win = LIVE_WINDOW.load(SeqCst);
    if win == 0 {
        return;
    }
    let x = f32::from(p.x) * scale;
    let y = f32::from(p.y) * scale;
    if let Ok(mut last) = LAST_MOVE.lock() {
        let key = (x.round() as i64, y.round() as i64, left_down);
        if *last == key {
            return;
        }
        *last = key;
    }
    let node = with_ui(|ui| ui.tree.hit(x, y)).unwrap_or(0);
    let mut e = Event::new(EV_POINTER, PTR_MOVE);
    e.window = win;
    e.node = node;
    e.snapshot = SNAPSHOT.load(SeqCst);
    e.x = x;
    e.y = y;
    e.i0 = if left_down { PTR_I0_LEFT_DOWN } else { 0 };
    e.modifiers = mods(m);
    push_event(e);
}

/// The fields of a WM_MOUSEWHEEL / WM_MOUSEHWHEEL message, before any window access: the signed WHEEL_DELTA units
/// (`GET_WHEEL_DELTA_WPARAM`: the high word of wParam as i16), the key-state word (`GET_KEYSTATE_WPARAM`: the low word) and the
/// SCREEN position (`GET_X_LPARAM` / `GET_Y_LPARAM`: signed 16 bit words, negative on a monitor left of or above the primary).
pub(crate) fn wheel_message_fields(w: usize, l: isize) -> (i32, u32, i32, i32) {
    let delta = ((w >> 16) & 0xFFFF) as u16 as i16 as i32;
    let keys = (w & 0xFFFF) as u32;
    let sx = (l & 0xFFFF) as u16 as i16 as i32;
    let sy = ((l >> 16) & 0xFFFF) as u16 as i16 as i32;
    (delta, keys, sx, sy)
}

/// Modifier bits for a wheel event: MK_SHIFT (0x4) and MK_CONTROL (0x8) from the message, Alt from the key state (the message
/// has no Alt bit), SWR_MOD_PRECISE when a delta is not a whole number of notches.
pub(crate) fn wheel_modifiers(keys: u32, alt: bool, d0: i32, d1: i32) -> u32 {
    (if keys & 0x8 != 0 { MOD_CTRL } else { 0 })
        | (if keys & 0x4 != 0 { MOD_SHIFT } else { 0 })
        | (if alt { MOD_ALT } else { 0 })
        | (if d0 % WHEEL_DELTA != 0 || d1 % WHEEL_DELTA != 0 { MOD_PRECISE } else { 0 })
}

/// Rev 0.11: WM_MOUSEWHEEL (vertical, `i0`) / WM_MOUSEHWHEEL (horizontal, `i1`) for a host that asked for them. The position is
/// converted from screen coordinates to physical px of the client. True = the message is consumed (the host owns it); false = no
/// live window, so the default handling stays.
fn on_wheel(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> bool {
    let win = LIVE_WINDOW.load(SeqCst);
    if win == 0 {
        return false;
    }
    let (delta, keys, sx, sy) = wheel_message_fields(w, l);
    let mut pt = [sx, sy];
    if unsafe { ScreenToClient(hwnd, &mut pt) } == 0 {
        return false;
    }
    let (x, y) = (pt[0] as f32, pt[1] as f32);
    let (d0, d1) = if msg == WM_MOUSEHWHEEL { (0, delta) } else { (delta, 0) };
    let alt = unsafe { GetKeyState(0x12) } < 0; // VK_MENU
    let node = with_ui(|ui| ui.tree.hit(x, y)).unwrap_or(0);
    let mut e = Event::new(EV_POINTER, PTR_WHEEL);
    e.window = win;
    e.node = node;
    e.snapshot = SNAPSHOT.load(SeqCst);
    e.x = x;
    e.y = y;
    e.i0 = d0;
    e.i1 = d1;
    e.modifiers = wheel_modifiers(keys, alt, d0, d1);
    push_event(e);
    true
}

/// Rev 0.9: the pointer left the window.
fn on_pointer_left() {
    if !POINTER_MOVES.load(SeqCst) {
        return;
    }
    if let Ok(mut last) = LAST_MOVE.lock() {
        *last = (i64::MIN, i64::MIN, false);
    }
    let win = LIVE_WINDOW.load(SeqCst);
    if win == 0 {
        return;
    }
    let mut e = Event::new(EV_POINTER, PTR_MOVE);
    e.window = win;
    e.node = 0;
    e.snapshot = SNAPSHOT.load(SeqCst);
    e.x = -1.0;
    e.y = -1.0;
    e.i0 = PTR_I0_LEFT_WINDOW;
    push_event(e);
}

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focus = self.focus.clone();
        let focus_paint = self.focus.clone();
        let view = cx.entity();
        div()
            .id("swr-root")
            .size_full()
            .track_focus(&focus)
            .on_mouse_move(|ev: &MouseMoveEvent, w: &mut Window, _cx: &mut App| {
                on_pointer_move(ev.position, ev.pressed_button == Some(MouseButton::Left), &ev.modifiers, w.scale_factor())
            })
            .on_hover(|hovered: &bool, _w: &mut Window, _cx: &mut App| {
                if !*hovered {
                    on_pointer_left()
                }
            })
            .on_key_down(|ev: &KeyDownEvent, _w: &mut Window, _cx: &mut App| on_key_down(ev))
            .on_mouse_down(MouseButton::Left, |ev: &MouseDownEvent, w: &mut Window, _cx: &mut App| {
                on_pointer(PTR_DOWN, ev.position, &ev.modifiers, ev.click_count, w.scale_factor())
            })
            .on_mouse_up(MouseButton::Left, |ev: &MouseUpEvent, w: &mut Window, _cx: &mut App| {
                on_pointer(PTR_UP, ev.position, &ev.modifiers, ev.click_count, w.scale_factor())
            })
            .child(
                canvas(
                    |_bounds, _window, _cx| (),
                    move |bounds, _, window, cx| paint_root(bounds, window, cx, &focus_paint, &view),
                )
                .size_full(),
            )
    }
}

/// Paints one shaped paragraph glyph by glyph, `track_dip` further right per glyph cluster since the start of its visual
/// line. The positions are `WrappedLine::paint`'s own (gpui text_system/line.rs paint_line, left aligned, no decorations): the
/// first glyph of a wrapped line sits at the origin, the line moves down by `line_height`, and the baseline is half-leading +
/// ascent below the line top. Emoji go through `paint_emoji`, everything else through `paint_glyph`.
///
/// `line_offsets` (the Mac rule, G75b) gives every visual line's top below `origin` (snapped px, as reported); None advances by `line_height`.
fn paint_tracked(wl: &gpui::WrappedLine, origin: gpui::Point<Pixels>, line_height: Pixels, track_dip: f32, color: u32, line_offsets: Option<&[Pixels]>, window: &mut Window) {
    let layout = &wl.unwrapped_layout;
    let baseline_y = (line_height - layout.ascent - layout.descent) / 2. + layout.ascent;
    let c: gpui::Hsla = gpui::Rgba::from(gpui::rgba(color)).into();
    let lines = wl.wrap_boundaries.len() as f32 + 1.0;
    let bounds = Bounds::new(origin, size(layout.width, line_height * lines));
    window.paint_layer(bounds, |window| {
        let mut wraps = wl.wrap_boundaries.iter().peekable();
        let mut line_top = origin.y;
        let mut line_ix = 0usize;
        let mut line_start_x = px(0.0);
        let mut ordinal = 0usize;
        let mut prev_index: Option<usize> = None;
        for (run_ix, run) in layout.runs.iter().enumerate() {
            for (glyph_ix, g) in run.glyphs.iter().enumerate() {
                if wraps.peek().map_or(false, |b| b.run_ix == run_ix && b.glyph_ix == glyph_ix) {
                    wraps.next();
                    line_ix += 1;
                    line_top = match line_offsets.and_then(|o| o.get(line_ix)) {
                        Some(off) => origin.y + *off,
                        None => line_top + line_height,
                    };
                    line_start_x = g.position.x;
                    ordinal = 0;
                    prev_index = None;
                }
                // A cluster (several glyphs for one index) counts once.
                if let Some(p) = prev_index {
                    if p != g.index {
                        ordinal += 1;
                    }
                }
                prev_index = Some(g.index);
                let o = point(origin.x + (g.position.x - line_start_x) + px(track_dip * ordinal as f32), line_top + baseline_y);
                if g.is_emoji {
                    let _ = window.paint_emoji(o, run.font_id, g.id, layout.font_size);
                } else {
                    let _ = window.paint_glyph(o, run.font_id, g.id, layout.font_size, c);
                }
            }
        }
    });
}

/// One level of the per-node clip stack. `cover` is set for a rev 0.12 path clip: the row-band rectangles (window dips) whose union
/// is the clip, already intersected with every clip below it. GPUI 0.2.2 clips by rectangle only (no path or alpha content mask,
/// no offscreen layer reachable from Window), so a primitive under a path clip is painted once per rectangle.
#[derive(Clone)]
struct ClipEntry {
    b: Bounds<Pixels>,
    cover: Option<Arc<Vec<Bounds<Pixels>>>>,
}

/// Runs `f` under the clip. `hint` (the primitive's own bounds) skips cover rectangles it cannot touch.
fn masked(window: &mut Window, clip: Option<Bounds<Pixels>>, cover: Option<&[Bounds<Pixels>]>, hint: Option<Bounds<Pixels>>, mut f: impl FnMut(&mut Window)) {
    match (clip, cover) {
        (Some(b), Some(rects)) => {
            for r in rects {
                if hint.as_ref().map_or(true, |h| h.intersects(r)) {
                    window.with_content_mask(Some(ContentMask { bounds: b.intersect(r) }), |w| f(w));
                }
            }
        }
        (Some(b), None) => window.with_content_mask(Some(ContentMask { bounds: b }), |w| f(w)),
        _ => f(window),
    }
}

/// A rev 0.12 path as a GPUI path in window dips (`inv` = 1 / scale), for fill (`stroke_w` None) or stroke.
fn gpui_path(
    path: &PathData,
    origin: gpui::Point<Pixels>,
    tx: (f32, f32),
    inv: f32,
    stroke_w: Option<f32>,
) -> Option<gpui::Path<Pixels>> {
    use gpui::{FillOptions, FillRule, PathBuilder, PathStyle, StrokeOptions};
    use lyon_tessellation::{LineCap, LineJoin};
    let tol = (0.1 * inv).max(0.005);
    let style = match stroke_w {
        None => PathStyle::Fill(
            FillOptions::default()
                .with_tolerance(tol)
                .with_fill_rule(if path.even_odd { FillRule::EvenOdd } else { FillRule::NonZero }),
        ),
        Some(w) => PathStyle::Stroke(
            StrokeOptions::default()
                .with_tolerance(tol)
                .with_line_width(w * inv)
                .with_miter_limit(path.miter)
                .with_line_cap(match path.cap {
                    Cap::Butt => LineCap::Butt,
                    Cap::Round => LineCap::Round,
                    Cap::Square => LineCap::Square,
                })
                .with_line_join(match path.join {
                    Join::Miter => LineJoin::Miter,
                    Join::Round => LineJoin::Round,
                    Join::Bevel => LineJoin::Bevel,
                }),
        ),
    };
    let pt = |p: &[f32; 2]| point(origin.x + px((p[0] + tx.0) * inv), origin.y + px((p[1] + tx.1) * inv));
    let mut b = PathBuilder::fill().with_style(style);
    for s in &path.segs {
        match s {
            Seg::Move(p) => b.move_to(pt(p)),
            Seg::Line(p) => b.line_to(pt(p)),
            Seg::Quad(c, p) => b.curve_to(pt(p), pt(c)),
            Seg::Cubic(c1, c2, p) => b.cubic_bezier_to(pt(p), pt(c1), pt(c2)),
            Seg::Close => b.close(),
        }
    }
    b.build().ok()
}

/// True when `b` can put a pixel inside the window and inside the active clip. A primitive outside both is not
/// handed to GPUI: with a long scrolling list most rows are off screen, and each skipped text run saves a
/// glyph lookup, a sprite and its GPU work for every frame.
#[inline]
fn visible(b: &Bounds<Pixels>, view: &Bounds<Pixels>, clip: Option<&Bounds<Pixels>>) -> bool {
    b.intersects(view) && clip.map_or(true, |c| b.intersects(c))
}

fn paint_tree(
    tree: &Tree,
    origin: gpui::Point<Pixels>,
    view: Bounds<Pixels>,
    scale: f32,
    window: &mut Window,
    cx: &mut App,
) {
    let inv = 1.0 / scale;
    for id in tree.order.iter() {
        let Some(node) = tree.nodes.get(id) else { continue };
        let mut clips: Vec<ClipEntry> = Vec::new();
        let mut tx = (0.0f32, 0.0f32);
        let mut tx_stack: Vec<(f32, f32)> = Vec::new();
        for p in &node.prims {
            let clip = clips.last().map(|e| e.b);
            let cover = clips.last().and_then(|e| e.cover.clone());
            let cover = cover.as_deref().map(|v| v.as_slice());
            match p {
                Prim::Rect { r, color, border_color, border_w, radius } => {
                    let b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    if !visible(&b, &view, clip.as_ref()) {
                        continue;
                    }
                    let mut q = fill(b, rgba(*color));
                    if *radius > 0.0 {
                        q = q.corner_radii(px(radius * inv));
                    }
                    if *border_w > 0.0 {
                        q = q.border_widths(px(border_w * inv)).border_color(rgba(*border_color));
                    }
                    masked(window, clip, cover, Some(b), |w| w.paint_quad(q.clone()));
                }
                Prim::Text { x, y, run } => {
                    // The whole run (every paragraph), padded by 2 DIP for glyph overhang.
                    let pad = 2.0 * scale;
                    let rb = Bounds::new(
                        point(origin.x + px((*x + tx.0 - pad) * inv), origin.y + px((*y + tx.1 - pad) * inv)),
                        size(px((run.width + 2.0 * pad) * inv), px((run.height + 2.0 * pad) * inv)),
                    );
                    if !visible(&rb, &view, clip.as_ref()) {
                        continue;
                    }
                    // Rev 0.6: one GPUI WrappedLine per paragraph, stacked by `top` (run-local px).
                    let lh = px(run.line_height_dip * run.gpui_ratio);
                    let mut line_base = 0usize;
                    let tops: Vec<f32> = run.lines.iter().map(|l| l.top).collect();
                    for (wl, top) in run.wrapped.iter() {
                        let n_vis = wl.wrap_boundaries.len() + 1;
                        let offs: Option<Vec<Pixels>> = if run.ext.mac_lines {
                            Some(crate::text::paragraph_line_offsets(&tops, line_base, n_vis, run.line_height_dip * run.scale).into_iter().map(|d| px(d * inv)).collect())
                        } else {
                            None
                        };
                        line_base += n_vis;
                        let o = point(
                            origin.x + px((*x + tx.0) * inv),
                            origin.y + px((*y + *top + tx.1) * inv),
                        );
                        if run.ext.track_dip != 0.0 || offs.is_some() {
                            // Rev 0.8 tracking: shape with gpui, paint every glyph at its layout position plus the tracking
                            // (G14: Window::paint_glyph is public). Tracking 0 keeps the unchanged path above.
                            masked(window, clip, cover, Some(rb), |w| paint_tracked(wl, o, lh, run.ext.track_dip * run.gpui_ratio, run.ext.color, offs.as_deref(), w));
                        } else {
                            masked(window, clip, cover, Some(rb), |w| {
                                let _ = wl.paint(o, lh, TextAlign::Left, None, w, cx);
                            });
                        }
                    }
                }
                Prim::Image { r, radius, img } => {
                    if r[2] > 0.0 && r[3] > 0.0 {
                        let b = Bounds::new(
                            point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                            size(px(r[2] * inv), px(r[3] * inv)),
                        );
                        if !visible(&b, &view, clip.as_ref()) {
                            continue;
                        }
                        let corners = Corners::all(px(*radius * inv));
                        let img = img.img.clone();
                        masked(window, clip, cover, Some(b), |w| {
                            let _ = w.paint_image(b, corners, img.clone(), 0, false);
                        });
                    }
                }
                Prim::Underline { r, color } => {
                    // SWR_PRIM_UNDERLINE (rev 0.5): solid bar, painted as a quad in v0.
                    let b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    if !visible(&b, &view, clip.as_ref()) {
                        continue;
                    }
                    masked(window, clip, cover, Some(b), |w| w.paint_quad(fill(b, rgba(*color))));
                }
                Prim::ClipPush(r) => {
                    let mut b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    let mut cover_below = None;
                    if let Some(prev) = clips.last() {
                        b = b.intersect(&prev.b);
                        cover_below = prev.cover.clone();
                    }
                    clips.push(ClipEntry { b, cover: cover_below });
                }
                Prim::ClipPath { r, path } => {
                    // Rev 0.12 path clip: row bands of the path inside the clip rect (and the clip below), in window dips.
                    let mut b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    let mut below = None;
                    if let Some(prev) = clips.last() {
                        b = b.intersect(&prev.b);
                        below = prev.cover.clone();
                    }
                    // Region in path space (physical px, before tx): the clip rect, bounded by the window.
                    let region = [r[0], r[1], r[2], r[3]];
                    let mut rects: Vec<Bounds<Pixels>> = Vec::new();
                    for q in path.cover_rects(region, 1.0) {
                        let rb = Bounds::new(
                            point(origin.x + px((q[0] + tx.0) * inv), origin.y + px((q[1] + tx.1) * inv)),
                            size(px(q[2] * inv), px(q[3] * inv)),
                        );
                        if !rb.intersects(&b) {
                            continue;
                        }
                        match &below {
                            None => rects.push(rb.intersect(&b)),
                            Some(prev) => {
                                for pr in prev.iter() {
                                    if rb.intersects(pr) {
                                        rects.push(rb.intersect(pr).intersect(&b));
                                    }
                                }
                            }
                        }
                    }
                    clips.push(ClipEntry { b, cover: Some(Arc::new(rects)) });
                }
                Prim::Path { path, fill: fill_c, stroke, stroke_w } => {
                    let pad = *stroke_w * 0.5 * path.miter.max(1.5);
                    let hull = Bounds::new(
                        point(origin.x + px((path.bounds[0] + tx.0 - pad) * inv), origin.y + px((path.bounds[1] + tx.1 - pad) * inv)),
                        size(px((path.bounds[2] + 2.0 * pad) * inv), px((path.bounds[3] + 2.0 * pad) * inv)),
                    );
                    if !visible(&hull, &view, clip.as_ref()) {
                        continue;
                    }
                    // Fill, then stroke over it (SwiftUI's fill then stroke). GPUI tessellates with lyon and the DirectX
                    // renderer rasterises paths with 4x MSAA into an intermediate texture, so the edge is anti-aliased.
                    if fill_c & 0xFF != 0 {
                        if let Some(gp) = gpui_path(path, origin, tx, inv, None) {
                            let col = rgba(*fill_c);
                            masked(window, clip, cover, Some(hull), |w| w.paint_path(gp.clone(), col));
                        }
                    }
                    if *stroke_w > 0.0 && stroke & 0xFF != 0 {
                        if let Some(gp) = gpui_path(path, origin, tx, inv, Some(*stroke_w)) {
                            let col = rgba(*stroke);
                            masked(window, clip, cover, Some(hull), |w| w.paint_path(gp.clone(), col));
                        }
                    }
                }
                Prim::ClipPop => {
                    clips.pop();
                }
                Prim::TranslatePush(dx, dy) => {
                    tx_stack.push(tx);
                    tx = (tx.0 + dx, tx.1 + dy);
                }
                Prim::TranslatePop => {
                    tx = tx_stack.pop().unwrap_or((0.0, 0.0));
                }
            }
        }
    }
}

fn paint_root(
    bounds: Bounds<Pixels>,
    window: &mut Window,
    cx: &mut App,
    focus: &FocusHandle,
    view: &Entity<RootView>,
) {
    let paint_start = qpc_now();
    let edge = pace::latest_edge();
    if edge != 0 && paint_start >= edge {
        PH_PHASE.add(paint_start - edge);
    }
    bump(S_PAINTS);
    if !window.is_window_active() {
        PAINTS_INACTIVE.fetch_add(1, SeqCst);
    }
    let scale = window.scale_factor();

    // Opaque background every frame: no alpha-0 client area (click-through).
    window.paint_quad(fill(bounds, rgba(0xFFFFFFFF)));

    // Window metrics -> event when changed.
    let vs = window.viewport_size();
    let (w, h) = (
        (f32::from(vs.width) * scale).round() as u32,
        (f32::from(vs.height) * scale).round() as u32,
    );
    // Rev 0.10: the scale the host sees is the explicit one when set, else GPUI's own (unchanged). GPUI's scale (G) stays the unit
    // for converting GPUI logical px to device px.
    let ovr = scale::override_scale();
    let host_scale = scale::effective_scale(ovr, 0, scale);
    let metrics_changed = publish_window_metrics(w, h, host_scale);
    if scale::note_gpui_scale(scale) && ovr.is_some() {
        // WM_DPICHANGED under an explicit render scale (H17): the host-visible scale stays fixed. What changed is G, so shaped
        // text (which baked in k = S / G) is dropped from the cache and the host gets a metrics event to re-measure on, even
        // though no host-visible number moved.
        let _ = with_ui(|ui| ui.cache.clear());
        if !metrics_changed {
            push_window_metrics_event(w, h, host_scale);
        }
    }
    WIN_ACTIVE.store(window.is_window_active(), SeqCst);

    // Released images leave the sprite atlas before this frame draws (a still-committed one
    // is simply re-inserted by paint_image).
    let dropped: Vec<Arc<RenderImage>> =
        std::mem::take(&mut *DROPPED_IMAGES.lock().unwrap_or_else(|e| e.into_inner()));
    for d in dropped {
        let _ = window.drop_image(d);
    }

    UI.with(|u| {
        if let Ok(ui) = u.try_borrow() {
            paint_tree(&ui.tree, bounds.origin, bounds, scale, window, cx);
        }
    });

    if IME_NODE.load(SeqCst) != 0 {
        window.handle_input(focus, ElementInputHandler::new(bounds, view.clone()), cx);
    }

    if ANIMATING.load(SeqCst) {
        window.request_animation_frame();
        TICK_TARGET.store(qpc_now() as u64, SeqCst);
        bump(S_TICKS_REQ);
        if !TICK_PENDING.swap(true, SeqCst) {
            signal_notify();
        }
    }

    ime_replace_on_layout(MAIN_HWND.load(SeqCst) as *mut c_void);
    let paint_end = qpc_now();
    PH_PAINT.span(trace::K_PAINT, paint_start, paint_end);
}

// -------------------------------------------------- IME text store (InputHandler)

fn with_ime<R>(f: impl FnOnce(&Host, u64, u64) -> R) -> Option<R> {
    bump(S_IME_CALLS);
    let node = IME_NODE.load(SeqCst);
    let win = LIVE_WINDOW.load(SeqCst);
    if node == 0 || win == 0 {
        return None;
    }
    let host = host()?;
    if !on_ui_thread() {
        bump(S_THREAD_VIOL);
        return None;
    }
    let Some(_guard) = enter_host() else {
        bump(S_IME_BUSY);
        return None;
    };
    IN_IME.with(|c| c.set(c.get() + 1));
    let t0 = qpc_now();
    let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f(&host, win, node)));
    PH_IME.span(trace::K_IME, t0, qpc_now());
    IN_IME.with(|c| c.set(c.get() - 1));
    match r {
        Ok(v) => Some(v),
        Err(_) => {
            bump(S_HOST_PANICS);
            None
        }
    }
}

fn r16(r: &Range<usize>) -> Utf16Range {
    Utf16Range { start: r.start as u32, end: r.end as u32 }
}

fn ime_notice(action: u32) {
    let win = LIVE_WINDOW.load(SeqCst);
    let mut e = Event::new(EV_IME, action);
    e.window = win;
    e.node = IME_NODE.load(SeqCst);
    e.snapshot = SNAPSHOT.load(SeqCst);
    push_event(e);
}

impl EntityInputHandler for RootView {
    fn text_for_range(
        &mut self,
        range: Range<usize>,
        adjusted: &mut Option<Range<usize>>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<String> {
        let (text, adj) = with_ime(|h, win, node| {
            let f = h.ime_copy_text?;
            let mut buf = vec![0u16; 4096];
            let mut len = 0u32;
            let mut adj = Utf16Range::default();
            let rc = f(h.ctx_ptr(), win, node, r16(&range), buf.as_mut_ptr(), buf.len() as u32, &mut len, &mut adj);
            if rc != SWR_OK {
                return None;
            }
            let n = (len as usize).min(buf.len());
            Some((String::from_utf16_lossy(&buf[..n]), adj))
        })??;
        *adjusted = Some(adj.start as usize..adj.end as usize);
        Some(text)
    }

    fn selected_text_range(
        &mut self,
        _ignore_disabled_input: bool,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        with_ime(|h, win, node| {
            let f = h.ime_get_selection?;
            let mut s = Utf16Selection::default();
            if f(h.ctx_ptr(), win, node, &mut s) != SWR_OK {
                return None;
            }
            Some(UTF16Selection {
                range: s.range.start as usize..s.range.end as usize,
                reversed: s.reversed != 0,
            })
        })?
    }

    fn marked_text_range(&self, _window: &mut Window, _cx: &mut Context<Self>) -> Option<Range<usize>> {
        with_ime(|h, win, node| {
            let f = h.ime_get_marked?;
            let mut r = Utf16Range::default();
            let mut has = 0i32;
            if f(h.ctx_ptr(), win, node, &mut r, &mut has) != SWR_OK || has == 0 {
                return None;
            }
            Some(r.start as usize..r.end as usize)
        })?
    }

    fn unmark_text(&mut self, _window: &mut Window, _cx: &mut Context<Self>) {
        let ok = with_ime(|h, win, node| match h.ime_unmark {
            Some(f) => f(h.ctx_ptr(), win, node) == SWR_OK,
            None => false,
        });
        if ok == Some(true) {
            ime_notice(IME_UNMARK);
        }
    }

    fn replace_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) {
        let u: Vec<u16> = text.encode_utf16().collect();
        let ok = with_ime(|h, win, node| {
            let Some(f) = h.ime_replace else { return false };
            let r = range.as_ref().map(r16);
            let rp = r.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
            f(h.ctx_ptr(), win, node, rp, u.as_ptr(), u.len() as u32) == SWR_OK
        });
        if ok == Some(true) {
            ime_notice(IME_COMMIT);
        }
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        new_text: &str,
        new_selected: Option<Range<usize>>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) {
        let u: Vec<u16> = new_text.encode_utf16().collect();
        let ok = with_ime(|h, win, node| {
            let Some(f) = h.ime_replace_and_mark else { return false };
            let r = range.as_ref().map(r16);
            let rp = r.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
            let s = new_selected.as_ref().map(r16);
            let sp = s.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
            f(h.ctx_ptr(), win, node, rp, u.as_ptr(), u.len() as u32, sp) == SWR_OK
        });
        if ok == Some(true) {
            ime_notice(IME_MARK);
        }
    }

    fn bounds_for_range(
        &mut self,
        range: Range<usize>,
        _element_bounds: Bounds<Pixels>,
        window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        let scale = window.scale_factor();
        let r = with_ime(|h, win, node| {
            let f = h.ime_caret_bounds?;
            let mut out = Rect::default();
            if f(h.ctx_ptr(), win, node, r16(&range), &mut out) != SWR_OK {
                return None;
            }
            Some(out)
        })??;
        Some(Bounds::new(
            point(px(r.x / scale), px(r.y / scale)),
            size(px(r.w / scale), px(r.h / scale)),
        ))
    }

    fn character_index_for_point(
        &mut self,
        _point: gpui::Point<Pixels>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<usize> {
        None
    }
}

// ------------------------------------------------ TSF host bridge (#33 Stage 2)
// The text store in tsf.rs reaches the host only through these functions; each goes through with_ime (UI thread, non-reentrant guard).
// A successful edit raises the same EV_IME notice as the GPUI InputHandler path above.

pub(crate) fn tsf_host_selection() -> Option<(u32, u32, bool)> {
    with_ime(|h, win, node| {
        let f = h.ime_get_selection?;
        let mut s = Utf16Selection::default();
        if f(h.ctx_ptr(), win, node, &mut s) != SWR_OK {
            return None;
        }
        Some((s.range.start, s.range.end, s.reversed != 0))
    })
    .flatten()
}

pub(crate) fn tsf_host_marked() -> Option<(u32, u32)> {
    with_ime(|h, win, node| {
        let f = h.ime_get_marked?;
        let mut r = Utf16Range::default();
        let mut has = 0i32;
        if f(h.ctx_ptr(), win, node, &mut r, &mut has) != SWR_OK || has == 0 {
            return None;
        }
        Some((r.start, r.end))
    })
    .flatten()
}

/// Text of the UTF-16 range [start, end) (end = u32::MAX: to the end of the field) and the range the host actually returned.
pub(crate) fn tsf_host_text(start: u32, end: u32) -> Option<(Vec<u16>, u32, u32)> {
    let mut cap = 4096usize;
    for _ in 0..2 {
        let (mut buf, len, adj) = with_ime(|h, win, node| {
            let f = h.ime_copy_text?;
            let mut buf = vec![0u16; cap];
            let mut len = 0u32;
            let mut adj = Utf16Range::default();
            let rc = f(h.ctx_ptr(), win, node, Utf16Range { start, end }, buf.as_mut_ptr(), buf.len() as u32, &mut len, &mut adj);
            if rc != SWR_OK {
                return None;
            }
            Some((buf, len, adj))
        })
        .flatten()?;
        if len as usize > cap && len < (1 << 22) {
            cap = len as usize;
            continue;
        }
        buf.truncate((len as usize).min(buf.len()));
        return Some((buf, adj.start, adj.end));
    }
    None
}

pub(crate) fn tsf_host_replace(range: Option<(u32, u32)>, text: &[u16]) -> bool {
    let ok = with_ime(|h, win, node| {
        let Some(f) = h.ime_replace else { return false };
        let r = range.map(|(s, e)| Utf16Range { start: s, end: e });
        let rp = r.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
        f(h.ctx_ptr(), win, node, rp, text.as_ptr(), text.len() as u32) == SWR_OK
    });
    if ok == Some(true) {
        ime_notice(IME_COMMIT);
        true
    } else {
        false
    }
}

/// `sel` is relative to the start of `text` (same convention as the GPUI path).
pub(crate) fn tsf_host_replace_and_mark(range: Option<(u32, u32)>, text: &[u16], sel: Option<(u32, u32)>) -> bool {
    let ok = with_ime(|h, win, node| {
        let Some(f) = h.ime_replace_and_mark else { return false };
        let r = range.map(|(s, e)| Utf16Range { start: s, end: e });
        let rp = r.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
        let s = sel.map(|(s, e)| Utf16Range { start: s, end: e });
        let sp = s.as_ref().map_or(std::ptr::null(), |x| x as *const Utf16Range);
        f(h.ctx_ptr(), win, node, rp, text.as_ptr(), text.len() as u32, sp) == SWR_OK
    });
    if ok == Some(true) {
        ime_notice(IME_MARK);
        tsf_caret_place();
        true
    } else {
        false
    }
}

pub(crate) fn tsf_host_unmark() -> bool {
    let ok = with_ime(|h, win, node| match h.ime_unmark {
        Some(f) => f(h.ctx_ptr(), win, node) == SWR_OK,
        None => false,
    });
    if ok == Some(true) {
        ime_notice(IME_UNMARK);
        true
    } else {
        false
    }
}

/// Client physical px rect of the UTF-16 range [start, end): the union of the caret rects at both ends.
pub(crate) fn tsf_host_bounds(start: u32, end: u32) -> Option<Rect> {
    with_ime(|h, win, node| {
        let f = h.ime_caret_bounds?;
        let mut a = Rect::default();
        if f(h.ctx_ptr(), win, node, Utf16Range { start, end: start }, &mut a) != SWR_OK {
            return None;
        }
        if end <= start {
            return Some(a);
        }
        let mut b = Rect::default();
        if f(h.ctx_ptr(), win, node, Utf16Range { start: end, end }, &mut b) != SWR_OK {
            return Some(a);
        }
        let l = a.x.min(b.x);
        let t = a.y.min(b.y);
        let r = (a.x + a.w).max(b.x + b.w);
        let bt = (a.y + a.h).max(b.y + b.h);
        Some(Rect { x: l, y: t, w: r - l, h: bt - t })
    })
    .flatten()
}

/// #45: system caret (SWIFTRIGHT_IME_SYSTEM_CARET=1) in the TSF path: placed at the composition caret while the store has a composition
/// (the IMM path places it from place_ime_windows, which is skipped while the store owns input), destroyed when the composition ends.
pub(crate) fn tsf_caret_place() {
    if !sys_caret_enabled() || !tsf::composing() {
        return;
    }
    let hwnd = MAIN_HWND.load(SeqCst) as *mut c_void;
    if hwnd.is_null() {
        return;
    }
    if let Some(r) = ime_caret_rect(hwnd) {
        sys_caret_place(hwnd, r.x as i32, r.y as i32, (r.h as i32).max(1));
    }
}

pub(crate) fn tsf_caret_destroy() {
    sys_caret_destroy();
}

// ---------------------------------------------------------- IME window placement (subclass)
// GPUI 0.2.2 (not vendored) calls ImmSetComposition/CandidateWindow once, at WM_IME_STARTCOMPOSITION,
// and forwards WM_IME_SETCONTEXT / WM_IME_NOTIFY to DefWindowProc. Microsoft IME positions its candidate
// list from the candidate form it last read, so we re-assert it (CFS_EXCLUDE around the composition start,
// client physical px) after every composition update and candidate notification.
#[repr(C)]
struct CompositionForm { style: u32, pt: [i32; 2], rc: [i32; 4] }
#[repr(C)]
struct CandidateForm { index: u32, style: u32, pt: [i32; 2], rc: [i32; 4] }
#[link(name = "imm32")]
extern "system" {
    fn ImmGetContext(hwnd: *mut c_void) -> *mut c_void;
    fn ImmReleaseContext(hwnd: *mut c_void, himc: *mut c_void) -> i32;
    fn ImmSetCandidateWindow(himc: *mut c_void, f: *const CandidateForm) -> i32;
    fn ImmSetCompositionWindow(himc: *mut c_void, f: *const CompositionForm) -> i32;
    fn ImmGetCandidateWindow(himc: *mut c_void, index: u32, f: *mut CandidateForm) -> i32;
    fn ImmGetDefaultIMEWnd(hwnd: *mut c_void) -> *mut c_void;
    fn ImmGetCompositionStringW(himc: *mut c_void, index: u32, buf: *mut c_void, len: u32) -> i32;
}
#[link(name = "user32")]
extern "system" {
    fn EnumWindows(cb: unsafe extern "system" fn(*mut c_void, isize) -> i32, l: isize) -> i32;
    fn GetClassNameW(hwnd: *mut c_void, buf: *mut u16, max: i32) -> i32;
    fn IsWindowVisible(hwnd: *mut c_void) -> i32;
    fn GetWindowRect(hwnd: *mut c_void, rect: *mut [i32; 4]) -> i32;
    fn GetWindowThreadProcessId(hwnd: *mut c_void, pid: *mut u32) -> u32;
    fn GetCurrentProcessId() -> u32;
    fn ScreenToClient(hwnd: *mut c_void, pt: *mut [i32; 2]) -> i32;
    fn GetKeyState(vk: i32) -> i16;
    fn CreateCaret(hwnd: *mut c_void, bitmap: *mut c_void, w: i32, h: i32) -> i32;
    fn SetCaretPos(x: i32, y: i32) -> i32;
    fn ShowCaret(hwnd: *mut c_void) -> i32;
    fn DestroyCaret() -> i32;
    fn NotifyWinEvent(event: u32, hwnd: *mut c_void, id_object: i32, id_child: i32);
    }
#[link(name = "kernel32")]
extern "system" {
    fn GetCurrentThreadId() -> u32;
}
#[link(name = "gdi32")]
extern "system" {
    fn CreateBitmap(w: i32, h: i32, planes: u32, bits_per_pel: u32, bits: *const c_void) -> *mut c_void;
    fn DeleteObject(obj: *mut c_void) -> i32;
}
#[link(name = "comctl32")]
extern "system" {
    fn SetWindowSubclass(
        hwnd: *mut c_void,
        cb: unsafe extern "system" fn(*mut c_void, u32, usize, isize, usize, usize) -> isize,
        id: usize,
        data: usize,
    ) -> i32;
    fn DefSubclassProc(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> isize;
}
const WM_PAINT: u32 = 0x000F;
const WM_DESTROY: u32 = 0x0002;
const WM_MOUSEWHEEL: u32 = 0x020A;
const WM_MOUSEHWHEEL: u32 = 0x020E;
const WM_IME_SETCONTEXT: u32 = 0x0281;
const WM_IME_NOTIFY: u32 = 0x0282;
const WM_IME_STARTCOMPOSITION: u32 = 0x010D;
const WM_IME_ENDCOMPOSITION: u32 = 0x010E;
const WM_IME_COMPOSITION: u32 = 0x010F;
static IME_MSG_LOGS: AtomicU32 = AtomicU32::new(0);

fn ime_caret_rect(_hwnd: *mut c_void) -> Option<Rect> {
    with_ime(|h, win, node| {
        let mut sel = Utf16Selection::default();
        let mut mr = Utf16Range::default();
        let mut has = 0i32;
        let range = match (h.ime_get_marked, h.ime_get_selection) {
            (Some(fm), _) if fm(h.ctx_ptr(), win, node, &mut mr, &mut has) == SWR_OK && has != 0 => mr,
            (_, Some(fs)) if fs(h.ctx_ptr(), win, node, &mut sel) == SWR_OK => sel.range,
            _ => return None,
        };
        let f = h.ime_caret_bounds?;
        let mut out = Rect::default();
        if f(h.ctx_ptr(), win, node, Utf16Range { start: range.start, end: range.start }, &mut out) != SWR_OK {
            return None;
        }
        Some(out)
    })
    .flatten()
}

struct WinScan { pid: u32, ime: *mut c_void, out: Vec<String> }

unsafe extern "system" fn scan_windows(h: *mut c_void, l: isize) -> i32 {
    let sc = &mut *(l as *mut WinScan);
    if IsWindowVisible(h) == 0 {
        return 1;
    }
    let mut buf = [0u16; 128];
    let n = GetClassNameW(h, buf.as_mut_ptr(), 128).max(0) as usize;
    let cls = String::from_utf16_lossy(&buf[..n]);
    let lc = cls.to_ascii_lowercase();
    let mut pid = 0u32;
    GetWindowThreadProcessId(h, &mut pid);
    if pid == sc.pid || h == sc.ime || lc.contains("ime") || lc.contains("candidate") {
        let mut r = [0i32; 4];
        GetWindowRect(h, &mut r);
        if sc.out.len() < 24 {
            sc.out.push(format!("{cls}@{},{},{},{}", r[0], r[1], r[2], r[3]));
        }
    }
    1
}

/// Evidence line for IMN_OPENCANDIDATE / IMN_CHANGECANDIDATE: the candidate form the IME holds, the visible IME / our windows, our caret.
pub(crate) fn log_candidate_ui(hwnd: *mut c_void, event: &str) {
    unsafe {
        let mut form = CandidateForm { index: 0, style: 0, pt: [0, 0], rc: [0; 4] };
        let himc = ImmGetContext(hwnd);
        let got = if himc.is_null() { 0 } else { ImmGetCandidateWindow(himc, 0, &mut form) };
        if !himc.is_null() {
            ImmReleaseContext(hwnd, himc);
        }
        let mut sc = WinScan { pid: GetCurrentProcessId(), ime: ImmGetDefaultIMEWnd(hwnd), out: Vec::new() };
        EnumWindows(scan_windows, &mut sc as *mut WinScan as isize);
        let mut o = [0i32, 0];
        ClientToScreen(hwnd, &mut o);
        let caret = match ime_caret_rect(hwnd) {
            Some(r) => format!("{},{},{},{}", o[0] + r.x as i32, o[1] + r.y as i32, r.w as i32, r.h as i32),
            None => "none".to_string(),
        };
        eprintln!(
            "[swiftright-render] ime_cand event={event} got={got} form_style={} form_pt={},{} form_rc={},{},{},{} cand_windows=[{}] caret={caret}",
            form.style, form.pt[0], form.pt[1], form.rc[0], form.rc[1], form.rc[2], form.rc[3], sc.out.join(";")
        );
    }
}

static IME_LAST_RECT: [AtomicI32; 4] = [AtomicI32::new(i32::MIN), AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0)];

fn ime_remember(x: i32, y: i32, w: i32, h: i32) {
    for (a, v) in IME_LAST_RECT.iter().zip([x, y, w, h]) {
        a.store(v, SeqCst);
    }
}

/// Layout moved the composing field while the IME composition is active: re-place the
/// composition/candidate windows at the new caret. Runs from paint (UI thread); only when
/// the caret rect actually changed. Host access goes through with_ime (no re-entrancy).
fn ime_replace_on_layout(hwnd: *mut c_void) {
    // #33 Stage 2 / #45 (opt-in SWIFTRIGHT_IME_TSF=1): the TSF text store follows the focused composing field.
    if tsf::enabled() && !hwnd.is_null() {
        let node = if LIVE_WINDOW.load(SeqCst) == 0 { 0 } else { IME_NODE.load(SeqCst) };
        tsf::sync(hwnd, node);
    }
    if IME_NODE.load(SeqCst) == 0 || hwnd.is_null() {
        return;
    }
    // While the store owns the window's input, IMM has no composition (TSF owns it), so the composition state comes from the store.
    let active = if tsf::associated() {
        tsf::composing()
    } else {
        unsafe {
            let himc = ImmGetContext(hwnd);
            if himc.is_null() {
                false
            } else {
                let n = ImmGetCompositionStringW(himc, 0x0008, std::ptr::null_mut(), 0);
                ImmReleaseContext(hwnd, himc);
                n > 0
            }
        }
    };
    if !active {
        ime_remember(i32::MIN, 0, 0, 0);
        return;
    }
    let Some(r) = ime_caret_rect(hwnd) else { return };
    let new = (r.x as i32, r.y as i32, (r.w as i32).max(1), (r.h as i32).max(1));
    let old = (
        IME_LAST_RECT[0].load(SeqCst),
        IME_LAST_RECT[1].load(SeqCst),
        IME_LAST_RECT[2].load(SeqCst),
        IME_LAST_RECT[3].load(SeqCst),
    );
    if old == new {
        return;
    }
    if old.0 != i32::MIN {
        eprintln!("[swiftright-render] ime_replace reason=layout old={},{},{},{} new={},{},{},{}", old.0, old.1, old.2, old.3, new.0, new.1, new.2, new.3);
        eprintln!("[swiftright-render] ime_replace_timing qpc={} tid={}", qpc_now(), unsafe { GetCurrentThreadId() });
        place_ime_windows(hwnd);
        tsf::layout_changed();
    } else {
        ime_remember(new.0, new.1, new.2, new.3);
    }
}

// #45: an invisible system caret at the composition caret. Chromium keeps one in step with its caret (ax_system_caret_win.cc: EVENT_OBJECT_LOCATIONCHANGE on
// OBJID_CARET) and the Microsoft IME's open list follows a layout move there (measured 22 Oct 2026, Dell, Edge), while ours stays where it opened with IMM32
// candidate forms and with a TSF store (TS_LC_CHANGE + a fresh GetTextExt rect). The caret is a Win32 caret drawn with an all-zero XOR bitmap, so it changes no
// pixel; SetCaretPos makes user32 raise the location event, and it is raised explicitly as well. Opt-in (SWIFTRIGHT_IME_SYSTEM_CARET=1) until a desktop run proves it.
static SYS_CARET: AtomicI32 = AtomicI32::new(0); // 0 none, 1 created
static SYS_CARET_BMP: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
static SYS_CARET_HEIGHT: AtomicI32 = AtomicI32::new(0);

fn sys_caret_enabled() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var("SWIFTRIGHT_IME_SYSTEM_CARET").map_or(false, |v| v == "1"))
}

/// #45: the caret is moved from a posted message, outside paint (measured 22 Oct: SetCaretPos/NotifyWinEvent made inside the paint path reached no WinEvent
/// client, while the same calls during typing did). The latest position wins.
pub const WM_SWR_CARET: u32 = 0x8000 + 0x5A4;
static SYS_CARET_PENDING: [AtomicI32; 3] = [AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(0)];

fn sys_caret_place(hwnd: *mut c_void, x: i32, y: i32, h: i32) {
    if !sys_caret_enabled() {
        return;
    }
    for (a, v) in SYS_CARET_PENDING.iter().zip([x, y, h]) {
        a.store(v, SeqCst);
    }
    unsafe { PostMessageW(hwnd, WM_SWR_CARET, 0, 0) };
}

fn sys_caret_apply(hwnd: *mut c_void) {
    let (x, y, h) = (SYS_CARET_PENDING[0].load(SeqCst), SYS_CARET_PENDING[1].load(SeqCst), SYS_CARET_PENDING[2].load(SeqCst));
    unsafe {
        if SYS_CARET.load(SeqCst) == 0 || SYS_CARET_HEIGHT.load(SeqCst) != h {
            if SYS_CARET.load(SeqCst) != 0 {
                DestroyCaret();
            }
            let old = SYS_CARET_BMP.swap(0, SeqCst);
            if old != 0 {
                DeleteObject(old as *mut c_void);
            }
            // 1 x h monochrome bitmap of zeros: XOR-ing it changes nothing on screen. Rows are WORD-aligned (2 bytes per row).
            let zeros = vec![0u8; (h.max(1) as usize) * 2];
            let bmp = CreateBitmap(1, h.max(1), 1, 1, zeros.as_ptr() as *const c_void);
            SYS_CARET_BMP.store(bmp as usize, SeqCst);
            let ok = CreateCaret(hwnd, bmp, 1, h.max(1));
            SYS_CARET.store(if ok != 0 { 1 } else { 0 }, SeqCst);
            SYS_CARET_HEIGHT.store(h, SeqCst);
            if ok != 0 {
                ShowCaret(hwnd);
            }
            eprintln!("[swiftright-render] ime_sys_caret create ok={ok} h={h}");
        }
        if SYS_CARET.load(SeqCst) != 0 {
            let rc = SetCaretPos(x, y);
            NotifyWinEvent(0x800B, hwnd, -8, 0); // EVENT_OBJECT_LOCATIONCHANGE, OBJID_CARET, CHILDID_SELF
            // qpc = raw QueryPerformanceCounter ticks, comparable with the harness event log (#45); tid = calling thread, win_tid = the window's thread
            let mut pid = 0u32;
            let win_tid = GetWindowThreadProcessId(hwnd, &mut pid);
            eprintln!("[swiftright-render] ime_sys_caret pos={x},{y} h={h} set_rc={rc} qpc={} tid={} win_tid={win_tid}", qpc_now(), GetCurrentThreadId());
        }
    }
}

fn sys_caret_destroy() {
    if SYS_CARET.swap(0, SeqCst) != 0 {
        unsafe {
            DestroyCaret();
            let old = SYS_CARET_BMP.swap(0, SeqCst);
            if old != 0 {
                DeleteObject(old as *mut c_void);
            }
        }
        eprintln!("[swiftright-render] ime_sys_caret destroy");
    }
}

fn place_ime_windows(hwnd: *mut c_void) {
    let r = ime_caret_rect(hwnd);
    let Some(r) = r else { return };
    let (x, y, w, h) = (r.x as i32, r.y as i32, (r.w as i32).max(1), (r.h as i32).max(1));
    ime_remember(x, y, w, h);
    sys_caret_place(hwnd, x, y, h);
    // #33 Stage 2: while the TSF store owns input, the IME reads positions through GetTextExt; setting IMM composition or candidate
    // forms then ends the TSF composition at every caret move (Dell F7live ime33-tsf2).
    if tsf::associated() {
        return;
    }
    unsafe {
        let himc = ImmGetContext(hwnd);
        if himc.is_null() {
            return;
        }
        let cf = CompositionForm { style: 0x0002, pt: [x, y], rc: [x, y, x + w, y + h] }; // CFS_POINT
        let cand = CandidateForm { index: 0, style: 0x0080, pt: [x, y + h], rc: [x, y, x + w, y + h] }; // CFS_EXCLUDE
        ImmSetCompositionWindow(himc, &cf);
        ImmSetCandidateWindow(himc, &cand);
        ImmReleaseContext(hwnd, himc);
    }
}

unsafe extern "system" fn ime_subclass_proc(hwnd: *mut c_void, msg: u32, w: usize, l: isize, _id: usize, _data: usize) -> isize {
    // Paint pacing (pace.rs): GPUI's vblank WM_PAINT is swallowed; the paced WM_SWR_PAINT paints at a fixed phase of the period.
    if msg == WM_PAINT {
        if pace::defer_paint(hwnd) {
            return 0;
        }
        let t0 = qpc_now();
        let out = DefSubclassProc(hwnd, msg, w, l);
        let t1 = qpc_now();
        PH_FRAME.span(trace::K_FRAME, t0, t1);
        return out;
    }
    if msg == pace::WM_SWR_PAINT {
        pace::run_deferred_paint(hwnd);
        return 0;
    }
    if msg == WM_SWR_MODAL {
        on_modal_message();
        return 0;
    }
    if msg == WM_SWR_CARET {
        sys_caret_apply(hwnd);
        return 0;
    }
    if tsf::enabled() {
        if msg == tsf::WM_SWR_TSF {
            tsf::on_lock_message();
            return 0;
        }
        if msg == WM_DESTROY {
            tsf::teardown(hwnd);
        }
    }
    // Rev 0.11 (issue #31): a host that asked for SWR_PTR_WHEEL gets the wheel and GPUI does not also handle it. Any other host
    // (flags without RUN_POINTER_WHEEL) leaves the message to GPUI exactly as before.
    if (msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL) && POINTER_WHEEL.load(SeqCst) && on_wheel(hwnd, msg, w, l) {
        return 0;
    }
    // #33 Stage 2: while the TSF store owns input, IMM composition messages must not reach GPUI (it would insert the text a second time).
    if tsf::associated() && matches!(msg, WM_IME_STARTCOMPOSITION | WM_IME_ENDCOMPOSITION | WM_IME_COMPOSITION) {
        if IME_MSG_LOGS.fetch_add(1, SeqCst) < 400 {
            eprintln!("[swiftright-render] tsf_imm_msg_dropped msg=0x{msg:04X}");
        }
        return 0;
    }
    let out = DefSubclassProc(hwnd, msg, w, l);
    // Rev 0.9 (decision H3): the pointer left the window (WM_MOUSELEAVE: GPUI's own tracking, or one posted by a driver) ends every hover. GPUI's element hover state does not
    // always follow a leave that arrives without a move, so the host is told directly (only when it asked for pointer moves).
    if msg == 0x02A3 {
        on_pointer_left();
    }
    match msg {
        WM_IME_SETCONTEXT | WM_IME_NOTIFY | WM_IME_STARTCOMPOSITION | WM_IME_ENDCOMPOSITION | WM_IME_COMPOSITION => {
            // Evidence for the next desktop run: which IME messages arrive, and what they carry.
            if IME_MSG_LOGS.fetch_add(1, SeqCst) < 400 {
                eprintln!("[swiftright-render] ime_msg msg=0x{msg:04X} wparam=0x{w:X} lparam=0x{:X}", l as usize);
            }
            if msg == WM_IME_ENDCOMPOSITION {
                ime_remember(i32::MIN, 0, 0, 0);
                sys_caret_destroy();
            }
            if msg == WM_IME_COMPOSITION || msg == WM_IME_STARTCOMPOSITION || (msg == WM_IME_NOTIFY && matches!(w, 3 | 4 | 5 | 6 | 7)) {
                place_ime_windows(hwnd);
            }
            if msg == WM_IME_NOTIFY && (w == 5 || w == 3) {
                log_candidate_ui(hwnd, if w == 5 { "open" } else { "change" });
            }
        }
        _ => {}
    }
    out
}

fn install_ime_subclass(hwnd: *mut c_void) {
    if tsf::enabled() {
        // reads SWIFTRIGHT_IME_TSF once, at window creation; nothing is printed when it is unset
        eprintln!("[swiftright-render] tsf_enabled env=SWIFTRIGHT_IME_TSF");
    }
    let ok = unsafe { SetWindowSubclass(hwnd, ime_subclass_proc, 0x5352_494D, 0) };
    eprintln!("[swiftright-render] ime_subclass installed={ok}");
}

// ------------------------------------------------------------- launch / loop

fn hwnd_of(window: &Window) -> *mut c_void {
    let handle = HasWindowHandle::window_handle(window).expect("no native window handle");
    match handle.as_raw() {
        RawWindowHandle::Win32(h) => h.hwnd.get() as *mut c_void,
        other => panic!("expected Win32 handle, got {other:?}"),
    }
}

fn deliver_tick(host: &Host, win: u64) {
    let target = TICK_TARGET.load(SeqCst);
    if let Some(f) = host.tick {
        let ctx = host.ctx_ptr();
        let ts = qpc_to_ns(target as i64);
        let t0 = qpc_now();
        let delivered = call_host(|| f(ctx, win, ts));
        PH_TICK.span(trace::K_TICK, t0, qpc_now());
        if delivered {
            bump(S_TICKS_DEL);
        }
    }
}

/// Marks the window dirty after a commit (and publishes the new AX snapshot, subject to the AX policy). The frame itself is painted from a
/// WM_PAINT: GPUI's own at the vblank, or the paced one (pace.rs).
fn present(cx: &mut AsyncApp, handle: WindowHandle<RootView>) {
    let t0 = qpc_now();
    let wait = cx
        .update(|cx| {
            handle
                .update(cx, |view, window, cx| {
                    let wait = view.publish_ax();
                    window.refresh();
                    cx.notify();
                    wait
                })
                .ok()
                .flatten()
        })
        .ok()
        .flatten();
    PH_PRESENT.span(trace::K_PRESENT, t0, qpc_now());
    if let Some(wait) = wait {
        // Throttled: publish the newest snapshot when the interval is over (one task, however many commits arrive meanwhile).
        // The task re-arms itself while publish_ax still reports a wait (a timer that fires before the interval is over, or a
        // publish by a newer commit that restarted the interval) and clears AX_TRAILING only once nothing is pending. It runs on the
        // UI thread like present(), and no await sits between the final publish_ax() and the clear, so a commit cannot slip in
        // between: it either arrived during a wait (publish_ax reads the newest SNAPSHOT) or comes after the clear (and spawns anew).
        if !AX_TRAILING.swap(true, SeqCst) {
            cx.spawn(async move |cx: &mut AsyncApp| {
                let mut wait = wait;
                loop {
                    cx.background_executor().timer(wait).await;
                    if SHUTDOWN.load(SeqCst) || WINDOW_CLOSED.load(SeqCst) {
                        break;
                    }
                    let next = cx
                        .update(|cx| handle.update(cx, |view, _window, _cx| view.publish_ax()).ok().flatten())
                        .ok()
                        .flatten();
                    let Some(next) = next else { break };
                    // Throttled again: the newest snapshot is still unpublished. Log the first 64, then every 64th.
                    let n = AX_RETHROTTLED.fetch_add(1, SeqCst) + 1;
                    if n <= 64 || n % 64 == 0 {
                        eprintln!(
                            "[swiftright-render] ax trailing re-throttled snapshot={} published={} retry_ns={} n={}",
                            SNAPSHOT.load(SeqCst),
                            AX_PUBLISHED.load(SeqCst),
                            next.as_nanos(),
                            n
                        );
                    }
                    wait = next;
                }
                AX_TRAILING.store(false, SeqCst);
            })
            .detach();
        }
    }
}

/// Client rect `[left, top, right, bottom]` -> (width, height) in physical px, clamped at 0.
fn client_size_px(rc: [i32; 4]) -> (u32, u32) {
    ((rc[2] - rc[0]).max(0) as u32, (rc[3] - rc[1]).max(0) as u32)
}

/// The one place the cached window metrics (WIN_W/WIN_H/WIN_SCALE_BITS, read by `swr_window_get_metrics`) change.
/// Stores all three, then, if any differed, pushes EV_WINDOW_METRICS carrying exactly the stored values. The getter and
/// the event therefore cannot disagree: the cache is updated before the event is queued, and the event payload is the
/// cache. All three swaps always run (no `||` short-circuit: a changed width must not leave height or scale stale).
/// Returns true when the metrics changed (an event was pushed if a window is live).
fn publish_window_metrics(w: u32, h: u32, scale: f32) -> bool {
    let bits = scale.to_bits();
    let cw = WIN_W.swap(w, SeqCst) != w;
    let ch = WIN_H.swap(h, SeqCst) != h;
    let cs = WIN_SCALE_BITS.swap(bits, SeqCst) != bits;
    let changed = cw | ch | cs;
    if changed {
        push_window_metrics_event(w, h, scale);
    }
    changed
}

/// Queues EV_WINDOW_METRICS for the live window (nothing before the window exists).
fn push_window_metrics_event(w: u32, h: u32, scale: f32) {
    let win = LIVE_WINDOW.load(SeqCst);
    if win != 0 {
        let mut e = Event::new(EV_WINDOW_METRICS, 0);
        e.window = win;
        e.snapshot = SNAPSHOT.load(SeqCst);
        e.i0 = w as i32;
        e.i1 = h as i32;
        e.x = scale;
        push_event(e);
    }
}

/// Reads the live window's client rect and per-window DPI from Win32 (the authority: the GPUI viewport is 0x0 at scale 1
/// while hidden). Returns (width px, height px, scale); `None` when there is no window yet.
fn read_client_metrics() -> Option<(u32, u32, f32)> {
    let hwnd = MAIN_HWND.load(SeqCst) as *mut c_void;
    if hwnd.is_null() {
        return None;
    }
    let mut rc = [0i32; 4];
    unsafe { GetClientRect(hwnd, &mut rc) };
    let (w, h) = client_size_px(rc);
    let dpi = unsafe { GetDpiForWindow(hwnd) };
    if dpi != 0 {
        scale::note_gpui_scale(dpi as f32 / 96.0);
    }
    // An explicit render scale replaces the DPI-derived one; without it this is the previous expression.
    let s = scale::effective_scale(scale::override_scale(), dpi, f32::from_bits(WIN_SCALE_BITS.load(SeqCst)));
    Some((w, h, s))
}

/// Called just before the ready callback: metrics read by the host inside it are the settled client size. If they differ
/// from the early sample, the metrics event is queued now, ahead of any paint, so it precedes or accompanies ready.
fn settle_client_metrics(req_w_dip: u32, req_h_dip: u32) {
    let Some((w, h, s)) = read_client_metrics() else { return };
    let changed = publish_window_metrics(w, h, s);
    eprintln!(
        "[swiftright-render] ready metrics requested={}x{}dip ready-client={}x{}px scale={} changed_since_initial={}",
        req_w_dip, req_h_dip, w, h, s, changed
    );
    if let Some(o) = scale::override_scale() {
        let (ew, eh) = (scale::physical_px(req_w_dip, o), scale::physical_px(req_h_dip, o));
        eprintln!("[swiftright-render] render-scale ready: client {}x{}px expected {}x{}px matches={}", w, h, ew, eh, (w, h) == (ew, eh));
    }
}

fn launch(cx: &mut App, title: String, width: u32, height: u32, host: Host) {
    // Rev 0.10: with an explicit render scale S the client area must be `dip * S` physical px. GPUI converts the logical size it is
    // given with the display's scale G, so ask for `dip * S / G`. Without an override the request is exactly `dip` (unchanged).
    let ovr = scale::override_scale();
    let g0 = if ovr.is_some() { primary_monitor_scale() } else { 1.0 };
    let bounds = Bounds::centered(
        None,
        size(px(scale::requested_logical_size(width, ovr, g0)), px(scale::requested_logical_size(height, ovr, g0))),
        cx,
    );
    let handle: WindowHandle<RootView> = match cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some(title.clone().into()),
                ..Default::default()
            }),
            // The AccessKit adapter must exist before the window is shown.
            show: false,
            // Opaque client area: a transparent one lets clicks fall through.
            window_background: WindowBackgroundAppearance::Opaque,
            ..Default::default()
        },
        |_, cx| {
            cx.new(|cx| RootView {
                focus: cx.focus_handle(),
                adapter: None,
            })
        },
    ) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("[swiftright-render] open_window failed: {e:?}");
            OPEN_FAILED.store(true, SeqCst);
            cx.quit();
            return;
        }
    };

    let win_handle = new_window_handle();
    let ok = handle.update(cx, |view, window, _cx| {
        let hwnd = hwnd_of(window);
        MAIN_HWND.store(hwnd as usize, SeqCst);
        install_ime_subclass(hwnd);
        pace::init(hwnd);
        view.adapter = Some(SubclassingAdapter::new(AkHWND(hwnd), Activation, Actions));
        window.focus(&view.focus);
        window.activate_window();
        if let Ok(()) = with_ui(|ui| ui.text_system = Some(window.text_system().clone())) {}
        // GPUI reports a 0x0 viewport at scale 1 while the window is still hidden, so the
        // initial metrics come straight from Win32 (client rect + per-window DPI).
        let mut rc = [0i32; 4];
        unsafe { GetClientRect(hwnd, &mut rc) };
        let dpi = unsafe { GetDpiForWindow(hwnd) };
        let g = if dpi == 0 { window.scale_factor() } else { dpi as f32 / 96.0 };
        scale::note_gpui_scale(g);
        let s = scale::effective_scale(ovr, dpi, window.scale_factor());
        let (cw, ch) = client_size_px(rc);
        WIN_W.store(cw, SeqCst);
        WIN_H.store(ch, SeqCst);
        eprintln!(
            "[swiftright-render] requested={}x{}dip expected={}x{}px initial-client={}x{}px scale={}",
            width,
            height,
            (width as f32 * s).round() as u32,
            (height as f32 * s).round() as u32,
            cw,
            ch,
            s
        );
        if let Some(o) = ovr {
            // The client rect of a window that is still hidden is an early sample (it can read another size until the initial placement
            // applies); the settled check is logged at ready (`settle_client_metrics`).
            eprintln!("[swiftright-render] render-scale override={} display-scale={} (window requested for the display it opened on: {})", o, g, (g - g0).abs() < 1e-4);
        }
        WIN_SCALE_BITS.store(s.to_bits(), SeqCst);
        let style = unsafe { GetWindowLongPtrW(hwnd, -16) };
        let exstyle = unsafe { GetWindowLongPtrW(hwnd, -20) };
        eprintln!(
            "[swiftright-render] window hwnd={:#x} style={:#x} exstyle={:#x} (WS_EX_LAYERED={} WS_EX_TRANSPARENT={} WS_EX_NOREDIRECTIONBITMAP={}) scale={} client={}x{}px background=Opaque",
            hwnd as usize,
            style,
            exstyle,
            exstyle & 0x80000 != 0,
            exstyle & 0x20 != 0,
            exstyle & 0x200000 != 0,
            s,
            WIN_W.load(SeqCst),
            WIN_H.load(SeqCst)
        );
    });
    if ok.is_err() {
        OPEN_FAILED.store(true, SeqCst);
        cx.quit();
        return;
    }
    LIVE_WINDOW.store(win_handle, SeqCst);
    {
        let mut a = crate::ax::lock_ax();
        a.window = win_handle;
        a.title = title;
    }

    // Runs inside App's close path: only sets flags and wakes the drain task.
    let closed_sub = cx.on_window_closed(|_cx| {
        WINDOW_CLOSED.store(true, SeqCst);
        signal_notify();
    });

    let _ = modal_legacy_spawn(); // read the diagnostic toggle now so its log line precedes any modal

    // Drain task: its body runs as a GPUI foreground runnable, outside every App and
    // Window borrow. All host callbacks except ime_* are issued from here.
    cx.spawn(async move |cx: &mut AsyncApp| {
        let _keep_subscription_alive = closed_sub;
        if let Some(f) = host.loop_ready {
            // The hidden window's first client rect is sampled before the initial size settles (SR0 findings 12:
            // 800x1396 reported vs 800x600 actual at scale 2.5). Re-read the real client rect and DPI now, so
            // swr_window_get_metrics inside loop_ready returns the settled physical size; push the metrics event if
            // it differs from the early sample (the paint path will not re-fire it for an equal value).
            settle_client_metrics(width, height);
            let ctx = host.ctx_ptr();
            call_host(|| f(ctx, win_handle));
        }
        let mut close_issued = false;
        loop {
            WaitSignal.await;

            if POST_CLOSE_ACTIVE.load(SeqCst) {
                // Post-close pump (rev 0.5): see post_close_step.
                if post_close_step(&host) {
                    break;
                }
                continue;
            }

            if let Some(f) = host.drain {
                bump(S_DRAIN_CALLS);
                let ctx = host.ctx_ptr();
                let t0 = qpc_now();
                call_host(|| f(ctx));
                PH_DRAIN.span(trace::K_DRAIN, t0, qpc_now());
            }
            if events_pending() {
                if let Some(f) = host.events_available {
                    let ctx = host.ctx_ptr();
                    if !call_host(|| f(ctx)) {
                        signal_notify();
                    }
                }
            }
            if TICK_PENDING.swap(false, SeqCst) {
                deliver_tick(&host, win_handle);
            }
            if PRESENT_PENDING.swap(false, SeqCst) | KICK.swap(false, SeqCst) {
                present(cx, handle);
            }

            if (QUIT_REQUESTED.load(SeqCst) || CLOSE_REQUESTED.load(SeqCst)) && !close_issued {
                close_issued = true;
                SHUTDOWN.store(true, SeqCst);
                ANIMATING.store(false, SeqCst);
                let _ = cx.update(|cx| {
                    let _ = handle.update(cx, |_, window, _| window.remove_window());
                });
            }

            // Modal start. Default: a posted WM_SWR_MODAL, so the modal runs from the top-level DispatchMessage and not as a
            // foreground runnable (a runnable runs inside a drain snapshot of the foreground queue; the wake runnable of this
            // task, queued behind it in the same snapshot, would then wait for the whole modal: the Modal06 stall).
            // SWR_MODAL_LEGACY_SPAWN=1 keeps the old spawn for the A/B proof; a failed post falls back to it.
            let modal_waiting = MODAL.lock().unwrap_or_else(|e| e.into_inner()).is_some();
            if modal_legacy_spawn() || (modal_waiting && !close_issued && !post_modal_start()) {
                let pending = MODAL.lock().unwrap_or_else(|e| e.into_inner()).take();
                if let Some(req) = pending {
                    if !close_issued {
                        let queued = qpc_now();
                        cx.spawn(async move |_cx: &mut AsyncApp| run_modal(req, "spawn", queued)).detach();
                    }
                }
            } else if close_issued {
                // Closing: a request that is still pending is dropped (as before).
                drop(MODAL.lock().unwrap_or_else(|e| e.into_inner()).take());
            }

            if WINDOW_CLOSED.load(SeqCst) {
                SHUTDOWN.store(true, SeqCst);
                ANIMATING.store(false, SeqCst);
                LIVE_WINDOW.store(0, SeqCst);
                crate::ax::lock_ax().window = 0;
                // The post-close flag goes up before the host sees the close, so the host can
                // end the phase from inside window_closed; the timer bounds the phase.
                POST_CLOSE_ACTIVE.store(true, SeqCst);
                arm_post_close_timer();
                if let Some(f) = host.window_closed {
                    let ctx = host.ctx_ptr();
                    call_host(|| f(ctx, win_handle));
                }
                // Teardown is over: the closed window's tree, text runs and AccessKit
                // snapshot are released here, so the live-node gauge reads zero.
                let _ = with_ui(|ui| {
                    ui.tree.clear();
                    ui.runs.clear();
                    ui.images.clear();
                });
                DROPPED_IMAGES.lock().unwrap_or_else(|e| e.into_inner()).clear();
                {
                    let mut a = crate::ax::lock_ax();
                    a.nodes.clear();
                    a.focus = 0;
                }
                clear_events();
                continue;
            }
        }
        let _ = cx.update(|cx| cx.quit());
    })
    .detach();
}

/// Arms the post-close bound: after SWR_POST_CLOSE_TIMEOUT_MS the pump ends even if the
/// host never calls swr_shutdown_complete. A failed thread spawn ends it at once.
fn arm_post_close_timer() {
    let spawned = std::thread::Builder::new()
        .name("swr-post-close-timer".into())
        .spawn(|| {
            std::thread::sleep(std::time::Duration::from_millis(POST_CLOSE_TIMEOUT_MS));
            POST_CLOSE_EXPIRED.store(true, SeqCst);
            signal_notify();
        });
    if spawned.is_err() {
        POST_CLOSE_EXPIRED.store(true, SeqCst);
        signal_notify();
    }
}

/// One post-close pump iteration (rev 0.5): drain only. Returns true when the pump ends.
fn post_close_step(host: &Host) -> bool {
    let ended = post_close_step_inner(host);
    if ended {
        POST_CLOSE_ENDED.store(true, SeqCst);
    }
    ended
}

/// Set once the pump has ended (by either the drain task or finish_post_close), so the
/// UI-thread tail never parks after the drain task already finished the phase.
static POST_CLOSE_ENDED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn post_close_step_inner(host: &Host) -> bool {
    bump(S_POST_DRAINS);
    if let Some(f) = host.drain {
        bump(S_DRAIN_CALLS);
        let ctx = host.ctx_ptr();
        call_host(|| f(ctx));
    }
    if events_pending() {
        if let Some(f) = host.events_available {
            let ctx = host.ctx_ptr();
            if !call_host(|| f(ctx)) {
                signal_notify();
            }
        }
    }
    if SHUTDOWN_COMPLETE.load(SeqCst) {
        return true;
    }
    if POST_CLOSE_EXPIRED.load(SeqCst) {
        bump(S_POST_TIMEOUTS);
        return true;
    }
    false
}

struct ThreadWaker(std::thread::Thread);
impl std::task::Wake for ThreadWaker {
    fn wake(self: std::sync::Arc<Self>) {
        self.0.unpark();
    }
}

/// GPUI's Windows platform posts WM_QUIT when the last window closes (platform/windows/
/// platform.rs:718-720), so Application::run returns before the post-close phase is over.
/// Finish the phase here, on the UI thread.
fn finish_post_close(host: &Host) {
    use std::future::Future;
    // Skip when the window never closed, the drain task already ended the pump, or the host
    // already called swr_shutdown_complete before Application::run returned.
    if !POST_CLOSE_ACTIVE.load(SeqCst)
        || POST_CLOSE_ENDED.load(SeqCst)
        || SHUTDOWN_COMPLETE.load(SeqCst)
    {
        return;
    }
    let waker = std::task::Waker::from(std::sync::Arc::new(ThreadWaker(std::thread::current())));
    let mut tcx = std::task::Context::from_waker(&waker);
    loop {
        let mut w = WaitSignal;
        match std::pin::Pin::new(&mut w).poll(&mut tcx) {
            std::task::Poll::Ready(_) => {
                if post_close_step(host) {
                    return;
                }
            }
            std::task::Poll::Pending => std::thread::park(),
        }
    }
}

/// Blocks on the calling thread until the window closes and GPUI quits.
pub fn run(title: String, width: u32, height: u32, host: Host, wake: usize) -> Status {
    // Per-monitor-v2 DPI awareness BEFORE any window exists. A DPI-unaware process gets a
    // virtualised 96-dpi window that is bitmap-stretched (wrong hit-test/paint extents).
    // A host manifest should declare it too; this call is a no-op once the process has a context.
    let dpi_rc = unsafe { SetProcessDpiAwarenessContext(-4) };
    eprintln!("[swiftright-render] SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2) -> {dpi_rc}");
    set_host(Some(host));
    UI_THREAD.store(unsafe { GetCurrentThreadId() }, SeqCst);
    if std::thread::Builder::new()
        .name("swr-wake-waiter".into())
        .spawn(move || waiter_loop(wake))
        .is_err()
    {
        return E_PLATFORM;
    }
    Application::new().run(move |cx: &mut App| launch(cx, title, width, height, host));
    finish_post_close(&host);
    set_host(None);
    pace::stop();
    trace::dump();
    eprintln!(
        "[swiftright-render] shutdown paints={} paints_while_inactive={} drains={} ticks_delivered={} events_pushed={} reentry_refused={} post_close_drains={} post_close_timeouts={}",
        stat(S_PAINTS),
        PAINTS_INACTIVE.load(SeqCst),
        stat(S_DRAIN_CALLS),
        stat(S_TICKS_DEL),
        stat(S_EV_PUSHED),
        stat(S_REENTRY),
        stat(S_POST_DRAINS),
        stat(S_POST_TIMEOUTS),
    );
    eprintln!(
        "[swiftright-render] phases {} {} {} {} {} {} {} {} paint_start_after_edge{} pacing[phase_us={} period_us={} edges={} posted={} skipped_pending={} expired={} swallowed={} passed_stale={} no_wait_edges={}]",
        PH_COMMIT.line("commit"),
        PH_TREE.line("tree_commit"),
        PH_PAINT.line("paint_root"),
        PH_PRESENT.line("present"),
        PH_TICK.line("host_tick"),
        PH_DRAIN.line("host_drain"),
        PH_FRAME.line("frame"),
        PH_IME.line("ime_cb"),
        PH_PHASE.line(""),
        pace::phase_us(),
        pace::period_us(),
        pace::EDGES.load(SeqCst),
        pace::POSTED.load(SeqCst),
        pace::SKIPPED_PENDING.load(SeqCst),
        pace::EXPIRED.load(SeqCst),
        pace::SWALLOWED.load(SeqCst),
        pace::PASSED_STALE.load(SeqCst),
        pace::NO_WAIT_EDGES.load(SeqCst),
    );
    let (private, ws) = trace::process_memory();
    eprintln!(
        "[swiftright-render] memory rust_live_bytes={} rust_allocs={} private_bytes={} working_set={} ax_publishes={} ax_throttled={} ax_rethrottled={}",
        trace::rust_live_bytes(),
        trace::rust_allocs(),
        private,
        ws,
        AX_PUBLISHES.load(SeqCst),
        AX_THROTTLED.load(SeqCst),
        AX_RETHROTTLED.load(SeqCst)
    );
    if OPEN_FAILED.load(SeqCst) {
        E_PLATFORM
    } else {
        SWR_OK
    }
}

#[cfg(test)]
mod client_size_tests {
    use super::client_size_px;

    #[test]
    fn client_size_is_right_minus_left_and_bottom_minus_top() {
        assert_eq!(client_size_px([0, 0, 800, 600]), (800, 600));
        assert_eq!(client_size_px([10, 20, 810, 620]), (800, 600));
    }

    #[test]
    fn inverted_or_empty_rect_clamps_to_zero() {
        assert_eq!(client_size_px([0, 0, 0, 0]), (0, 0));
        assert_eq!(client_size_px([5, 5, 1, 1]), (0, 0));
    }
}

#[cfg(test)]
mod wheel_tests {
    use super::*;

    #[test]
    fn message_fields_are_signed_words() {
        // One notch away from the user (+120) at screen (100, 200), no keys.
        assert_eq!(wheel_message_fields((120usize << 16) | 0, (200isize << 16) | 100), (120, 0, 100, 200));
        // One notch toward the user (-120 = 0xFF88) with Ctrl (MK_CONTROL 0x8), on a monitor left of and above the primary.
        let w = (0xFF88usize << 16) | 0x8;
        let l = (((-50i16) as u16 as isize) << 16) | ((-300i16) as u16 as isize);
        assert_eq!(wheel_message_fields(w, l), (-120, 0x8, -300, -50));
    }

    #[test]
    fn modifiers_and_the_precise_bit() {
        assert_eq!(wheel_modifiers(0, false, 120, 0), 0);
        assert_eq!(wheel_modifiers(0, false, -240, 0), 0, "whole notches are not precise");
        assert_eq!(wheel_modifiers(0x4 | 0x8, true, 120, 0), MOD_SHIFT | MOD_CTRL | MOD_ALT);
        assert_eq!(wheel_modifiers(0, false, 30, 0), MOD_PRECISE);
        assert_eq!(wheel_modifiers(0, false, 0, -15), MOD_PRECISE);
    }
}

#[cfg(test)]
mod ax_throttle_tests {
    use super::*;
    use std::time::Duration;

    // Ticks are nanoseconds here (a QPC frequency of 1 GHz), so a rest in ticks is also the rest in ns.
    const MIN: i64 = 100_000_000;
    const MS: i64 = 1_000_000;
    const LAST: i64 = 5_000_000_000;

    #[test]
    fn rest_counts_down_inside_the_interval() {
        assert_eq!(ax_throttle_rest(LAST + 10 * MS, LAST, MIN), Some(90 * MS));
        assert_eq!(ax_throttle_rest(LAST + 99 * MS, LAST, MIN), Some(MS));
    }

    #[test]
    fn no_rest_after_the_interval_before_the_first_publish_or_unthrottled() {
        assert_eq!(ax_throttle_rest(LAST + MIN, LAST, MIN), None);
        assert_eq!(ax_throttle_rest(LAST + 250 * MS, LAST, MIN), None);
        assert_eq!(ax_throttle_rest(LAST + MS, 0, MIN), None, "nothing published yet");
        assert_eq!(ax_throttle_rest(LAST + MS, LAST, 0), None, "SWR_AX_MIN_MS=0 publishes every snapshot");
    }

    #[test]
    fn retry_wait_is_floored_at_one_millisecond() {
        assert_eq!(ax_retry_wait(90 * MS as u64), Duration::from_millis(90));
        assert_eq!(ax_retry_wait(1), Duration::from_millis(1));
        assert_eq!(ax_retry_wait(0), Duration::from_millis(1));
    }

    /// The textgeom07 run 05 defect: a selection-only commit (v9) is throttled, the trailing timer fires slightly early, the
    /// re-check is throttled again. The old task dropped that second answer (snapshot never published until the next commit);
    /// the loop in `present` keeps waiting until the answer is None.
    #[test]
    fn early_timer_is_healed_by_the_retry_loop_but_not_by_a_single_check() {
        // 5 percent early, like a coarse timer.
        let fire = |wait: Duration| (wait.as_nanos() as i64) * 95 / 100;
        let first_wait = ax_retry_wait(qpc_ns(ax_throttle_rest(LAST + 10 * MS, LAST, MIN).unwrap()));
        assert_eq!(first_wait, Duration::from_millis(90));

        // Old behaviour: one wake, one check, result discarded.
        let now = LAST + 10 * MS + fire(first_wait);
        assert!(ax_throttle_rest(now, LAST, MIN).is_some(), "the single check is throttled again: the publish would be lost");

        // New behaviour: loop while throttled.
        let mut now = LAST + 10 * MS;
        let mut wait = first_wait;
        let mut retries = 0;
        let published_at = loop {
            now += fire(wait);
            match ax_throttle_rest(now, LAST, MIN) {
                None => break now,
                Some(rest) => {
                    retries += 1;
                    assert!(retries < 20, "the retry loop must converge");
                    wait = ax_retry_wait(qpc_ns(rest));
                }
            }
        };
        assert!(retries >= 1, "the early wake was re-throttled and retried");
        assert!(published_at - LAST >= MIN, "published only after the interval, never inside it");
    }

    /// A newer commit publishing during the wait restarts the interval: the loop waits that out too, then publishes the newest snapshot.
    #[test]
    fn a_publish_during_the_wait_restarts_the_interval_and_the_loop_follows_it() {
        let mut last = LAST;
        let mut now = LAST + 10 * MS;
        let mut wait = ax_retry_wait(qpc_ns(ax_throttle_rest(now, last, MIN).unwrap()));
        // At LAST+100 ms the wait ends exactly while present() has just published a newer commit (last = now).
        now += wait.as_nanos() as i64;
        last = now - MS;
        let rest = ax_throttle_rest(now, last, MIN).expect("interval restarted by the other publish");
        assert_eq!(rest, MIN - MS);
        wait = ax_retry_wait(qpc_ns(rest));
        now += wait.as_nanos() as i64;
        assert_eq!(ax_throttle_rest(now, last, MIN), None, "the second wake publishes");
    }

    fn qpc_ns(ticks: i64) -> u64 {
        ticks.max(0) as u64
    }
}
