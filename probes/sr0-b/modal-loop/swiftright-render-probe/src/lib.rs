//! SR0-B modal-loop probe.
//!
//! `swr_run` blocks on the calling (initial) thread and runs GPUI 0.2.2's
//! Windows application. Every Swift callback (loop_ready, drain, tick,
//! window_closed) goes through `host_call`, which is non-reentrant: a callback
//! that arrives while another is active is deferred and counted, then run after
//! the active one unwinds.
//!
//! Wake path: a waiter thread blocks on Swift's main-queue wake HANDLE. Each
//! signal calls `signal_notify()`, which wakes the drain task on GPUI's
//! foreground executor. GPUI posts runnables woken from other threads to its
//! message-only window, and its size-move timer and window proc run them
//! inside modal loops (see gpui `platform/windows/events.rs`
//! `handle_size_move_loop`, `handle_timer_msg`, and `platform.rs`
//! `run_foreground_task`).
//!
//! AccessKit: one SubclassingAdapter per HWND, created before show. Its
//! ActionHandler only validates, pushes a record into a bounded queue, and
//! SetEvent()s the Swift wake handle. It never calls Swift or GPUI.
//!
//! Modal requests: `swr_request_modal` queues a request. The drain task spawns a
//! separate foreground task that opens the TaskDialog, so the modal loop never
//! runs inside the drain task's own poll and no GPUI borrow is held.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::future::Future;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering::SeqCst};
use std::sync::Mutex;
use std::task::{Context as TaskContext, Poll, Waker};
use std::time::Duration;

use accesskit::{
    Action, ActionHandler, ActionRequest, ActivationHandler, Node, NodeId, Rect, Role, TreeId,
    TreeInfo, TreeUpdate,
};
use accesskit_windows::{SubclassingAdapter, HWND as AkHWND};
use gpui::{
    div, prelude::*, px, size, App, AsyncApp, Application, Bounds, Context, IntoElement, Render,
    TitlebarOptions, Window, WindowBounds, WindowHandle, WindowOptions,
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

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

const KIND_DRAIN: usize = 0;
const KIND_TICK: usize = 1;
const KIND_LOOP_READY: usize = 2;
const KIND_WINDOW_CLOSED: usize = 3;

const MODAL_TASKDIALOG: u32 = 1;
const MODAL_POPUP: u32 = 2; // declared in ABI; not implemented in this probe

const UI_TAG_AX: u32 = 1;
const UI_TAG_MODAL_RESULT: u32 = 2;
const UI_CAPACITY: usize = 256;
const SNAPSHOT_CURRENT: u64 = 1;
const NODE_BUTTON: u64 = 2;
const ACTION_CLICK_CODE: u32 = 1;

const PHASE_SIZING: usize = 1;
const PHASE_MODAL: usize = 2;
const PHASE_OPENING: usize = 4;

const WM_CLOSE: u32 = 0x0010;
const WM_ENTERSIZEMOVE: u32 = 0x0231;
const WM_EXITSIZEMOVE: u32 = 0x0232;
const WM_NCLBUTTONDOWN: u32 = 0x00A1;
const TDN_CREATED: u32 = 0;
const TDM_CLICK_BUTTON: u32 = 0x0400 + 102;
const IDOK: i32 = 1;
const TDCBF_OK_BUTTON: u32 = 0x0001;

type HWND = *mut c_void;
type SubclassProc = unsafe extern "system" fn(HWND, u32, usize, isize, usize, usize) -> isize;
type TaskDialogCallback = unsafe extern "system" fn(HWND, u32, usize, isize, isize) -> i32;

// commctrl.h declares TASKDIALOGCONFIG under #include <pshpack1.h>; windows-0.61.3
// (Controls/mod.rs: `#[repr(C, packed(1))] pub struct TASKDIALOGCONFIG`) mirrors that.
// Natural alignment put hwndParent at offset 8 instead of 4 and made TaskDialogIndirect
// return E_INVALIDARG. cbSize is size_of::<Self>() of this packed layout.
#[repr(C, packed(1))]
struct TaskDialogConfig {
    cb_size: u32,
    hwnd_parent: HWND,
    h_instance: *mut c_void,
    flags: u32,
    common_buttons: u32,
    window_title: *const u16,
    main_icon: *const u16,
    main_instruction: *const u16,
    content: *const u16,
    buttons_count: u32,
    buttons: *const c_void,
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

#[allow(non_snake_case)]
extern "system" {
    fn GetCurrentThreadId() -> u32;
    fn WaitForSingleObject(handle: *mut c_void, millis: u32) -> u32;
    fn SetEvent(handle: *mut c_void) -> i32;
    fn PostMessageW(hwnd: HWND, msg: u32, w: usize, l: isize) -> i32;
    fn SetForegroundWindow(hwnd: HWND) -> i32;
}

#[link(name = "comctl32")]
#[allow(non_snake_case)]
extern "system" {
    fn SetWindowSubclass(hwnd: HWND, f: SubclassProc, id: usize, data: usize) -> i32;
    fn DefSubclassProc(hwnd: HWND, msg: u32, w: usize, l: isize) -> isize;
    fn TaskDialogIndirect(
        cfg: *const TaskDialogConfig,
        button: *mut i32,
        radio: *mut i32,
        verified: *mut i32,
    ) -> i32;
}

// ---- Shared state (no lock is held while calling into Swift) ----

static WAKE_HANDLE: AtomicUsize = AtomicUsize::new(0);
static RUNNING: AtomicBool = AtomicBool::new(false);
static UI_THREAD: AtomicU32 = AtomicU32::new(0);
static QUIT_REQUESTED: AtomicBool = AtomicBool::new(false);
static WINDOW_CLOSED: AtomicBool = AtomicBool::new(false);
static OPEN_FAILED: AtomicBool = AtomicBool::new(false);
static MAIN_HWND: AtomicUsize = AtomicUsize::new(0);

// Host callback guard.
static HOST_ACTIVE: AtomicBool = AtomicBool::new(false);
static DEFERRED: Mutex<VecDeque<usize>> = Mutex::new(VecDeque::new());
static CALLBACK_RUNS: [AtomicU64; 4] = [const { AtomicU64::new(0) }; 4];
static DEFERRED_TOTAL: AtomicU64 = AtomicU64::new(0);
static NESTED_EXECUTED: AtomicU64 = AtomicU64::new(0);
static DRAINS_BY_PHASE: [AtomicU64; 4] = [const { AtomicU64::new(0) }; 4];
static SELFTEST_DETECTED: AtomicU64 = AtomicU64::new(0);
static PANICS: AtomicU64 = AtomicU64::new(0);

// Phase tracking.
static SIZING: AtomicBool = AtomicBool::new(false);
static MODAL_ACTIVE: AtomicBool = AtomicBool::new(false);
// True from run_modal start until the first drain after TDN_CREATED: the one-off cost of
// TaskDialogIndirect building its window on the UI thread (~40 ms). Reported separately (bit 4).
static MODAL_OPENING: AtomicBool = AtomicBool::new(false);
static MODAL_CREATED: AtomicBool = AtomicBool::new(false);
static SIZE_ENTER: AtomicU64 = AtomicU64::new(0);
static SIZE_EXIT: AtomicU64 = AtomicU64::new(0);
static NC_LBUTTON_DOWN: AtomicU64 = AtomicU64::new(0);
static NC_LAST_HT: AtomicU64 = AtomicU64::new(0);

// Modal requests.
static MODAL_PENDING: Mutex<Option<u32>> = Mutex::new(None);
static MODAL_REQUESTS: AtomicU64 = AtomicU64::new(0);
static MODAL_OPENED: AtomicU64 = AtomicU64::new(0);
static MODAL_RESULTS: AtomicU64 = AtomicU64::new(0);
static MODAL_ERRORS: AtomicU64 = AtomicU64::new(0);

// Misc.
static DRAIN_CALLS_TOTAL: AtomicU64 = AtomicU64::new(0);
static TICK_CALLS: AtomicU64 = AtomicU64::new(0);
static WAKE_SIGNALS: AtomicU64 = AtomicU64::new(0);
static WAKE_WAIT_FAILURES: AtomicU64 = AtomicU64::new(0);
static FRAMES: AtomicU64 = AtomicU64::new(0);
static QUIT_REQUESTS: AtomicU64 = AtomicU64::new(0);

// AccessKit counters.
static AX_ATTEMPTS: AtomicU64 = AtomicU64::new(0);
static AX_ENQUEUED: AtomicU64 = AtomicU64::new(0);
static AX_FULL: AtomicU64 = AtomicU64::new(0);
static AX_REJECTED_POST: AtomicU64 = AtomicU64::new(0);
static AX_POPPED_APPLIED: AtomicU64 = AtomicU64::new(0);
static AX_POPPED_STALE: AtomicU64 = AtomicU64::new(0);
static AX_ENQ_WHILE_CLOSED: AtomicU64 = AtomicU64::new(0);
static AX_APPLIED_AFTER_CLOSE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Default)]
#[repr(C)]
pub struct SwrUiRecord {
    pub tag: u32,
    pub action: u32,
    pub value: i32,
    pub _pad: u32,
    pub window_gen: u64,
    pub node_id: u64,
    pub snapshot_version: u64,
}

/// Bounded queue shared by AccessKit action handlers, the modal task and the
/// Swift drain. `live_gen` is 1 while the window is open and 0 after close.
/// Both enqueue and close take this lock, so no record is enqueued after close.
struct UiQueue {
    live_gen: u64,
    buf: VecDeque<SwrUiRecord>,
}

static UI: Mutex<UiQueue> = Mutex::new(UiQueue {
    live_gen: 0,
    buf: VecDeque::new(),
});

fn lock_ui() -> std::sync::MutexGuard<'static, UiQueue> {
    UI.lock().unwrap_or_else(|e| e.into_inner())
}

fn wake_swift() {
    let h = WAKE_HANDLE.load(SeqCst);
    if h != 0 {
        unsafe { SetEvent(h as *mut c_void) };
    }
}

#[derive(Clone, Copy)]
struct HostRef {
    ctx: usize,
    loop_ready: Option<extern "C" fn(*mut c_void)>,
    drain: Option<extern "C" fn(*mut c_void)>,
    tick: Option<extern "C" fn(*mut c_void)>,
    window_closed: Option<extern "C" fn(*mut c_void)>,
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

/// Resolves once per batch of signals; pending wakes coalesce.
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

fn current_phase() -> usize {
    let mut p = 0;
    if SIZING.load(SeqCst) {
        p |= PHASE_SIZING;
    }
    if MODAL_OPENING.load(SeqCst) {
        p |= PHASE_OPENING;
    } else if MODAL_ACTIVE.load(SeqCst) {
        p |= PHASE_MODAL;
    }
    p
}

fn run_callback(kind: usize) {
    let host = match *HOST.lock().unwrap_or_else(|e| e.into_inner()) {
        Some(h) => h,
        None => return,
    };
    let f = match kind {
        KIND_DRAIN => host.drain,
        KIND_TICK => host.tick,
        KIND_LOOP_READY => host.loop_ready,
        _ => host.window_closed,
    };
    CALLBACK_RUNS[kind].fetch_add(1, SeqCst);
    if kind == KIND_DRAIN {
        DRAINS_BY_PHASE[current_phase() & 3].fetch_add(1, SeqCst);
    }
    if let Some(f) = f {
        let ctx = host.ctx as *mut c_void;
        let _ = catch_unwind(AssertUnwindSafe(|| f(ctx)));
    }
    if kind == KIND_DRAIN && MODAL_CREATED.swap(false, SeqCst) {
        MODAL_OPENING.store(false, SeqCst);
    }
}

/// Non-reentrant entry for every host callback. A call that arrives while
/// another callback is active is deferred, counted, and run after the active
/// callback unwinds. Nested execution is structurally impossible here, and
/// NESTED_EXECUTED stays 0 as a checked invariant.
fn host_call(kind: usize) {
    if HOST_ACTIVE.swap(true, SeqCst) {
        DEFERRED_TOTAL.fetch_add(1, SeqCst);
        DEFERRED
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push_back(kind);
        return;
    }
    run_callback(kind);
    loop {
        let next = DEFERRED.lock().unwrap_or_else(|e| e.into_inner()).pop_front();
        match next {
            Some(k) => run_callback(k),
            None => break,
        }
    }
    HOST_ACTIVE.store(false, SeqCst);
}

/// Pops the bounded queue and rejects records addressed to a closed window or
/// an old snapshot. Returns true when a record was written to `out`.
fn pop_record(out: &mut SwrUiRecord) -> bool {
    let mut q = lock_ui();
    while let Some(rec) = q.buf.pop_front() {
        if rec.tag == UI_TAG_AX {
            if q.live_gen == 0 || rec.window_gen != q.live_gen || rec.snapshot_version != SNAPSHOT_CURRENT {
                AX_POPPED_STALE.fetch_add(1, SeqCst);
                continue;
            }
            if q.live_gen == 0 {
                AX_APPLIED_AFTER_CLOSE.fetch_add(1, SeqCst);
            }
            AX_POPPED_APPLIED.fetch_add(1, SeqCst);
        }
        *out = rec;
        return true;
    }
    false
}

fn push_ui(rec: SwrUiRecord) -> bool {
    let mut q = lock_ui();
    if q.buf.len() >= UI_CAPACITY {
        return false;
    }
    q.buf.push_back(rec);
    true
}

// ---- AccessKit ----

struct Activation;

impl ActivationHandler for Activation {
    fn request_initial_tree(&mut self) -> Option<TreeUpdate> {
        Some(build_tree())
    }
}

/// Must be Send. Only validates, enqueues and wakes Swift.
struct Actions;

impl ActionHandler for Actions {
    fn do_action(&mut self, request: ActionRequest) {
        AX_ATTEMPTS.fetch_add(1, SeqCst);
        let mut q = lock_ui();
        if q.live_gen == 0 {
            AX_REJECTED_POST.fetch_add(1, SeqCst);
            return;
        }
        if q.buf.len() >= UI_CAPACITY {
            AX_FULL.fetch_add(1, SeqCst);
            return;
        }
        let action = if request.action == Action::Click {
            ACTION_CLICK_CODE
        } else {
            0
        };
        let live = q.live_gen;
        q.buf.push_back(SwrUiRecord {
            tag: UI_TAG_AX,
            action,
            value: 0,
            _pad: 0,
            window_gen: live,
            node_id: request.target_node.0,
            snapshot_version: SNAPSHOT_CURRENT,
        });
        AX_ENQUEUED.fetch_add(1, SeqCst);
        drop(q);
        wake_swift();
    }
}

fn build_tree() -> TreeUpdate {
    const ROOT_ID: NodeId = NodeId(1);
    const BUTTON_ID: NodeId = NodeId(2);
    const LABEL_ID: NodeId = NodeId(3);

    let mut root = Node::new(Role::Window);
    root.set_label("SR0-B modal");
    root.set_children([BUTTON_ID, LABEL_ID]);

    let mut button = Node::new(Role::Button);
    button.set_label("Probe action");
    button.add_action(Action::Click);
    button.add_action(Action::Focus);
    button.set_bounds(Rect { x0: 20.0, y0: 20.0, x1: 160.0, y1: 60.0 });

    let mut label = Node::new(Role::Label);
    label.set_label("Status");
    label.set_bounds(Rect { x0: 20.0, y0: 80.0, x1: 320.0, y1: 110.0 });

    TreeUpdate {
        nodes: vec![(ROOT_ID, root), (BUTTON_ID, button), (LABEL_ID, label)],
        tree: Some(TreeInfo::new(ROOT_ID)),
        tree_id: TreeId::ROOT,
        focus: ROOT_ID,
    }
}

/// gpui 0.2.2 uses windows 0.61 and accesskit_windows uses 0.62, so bridge the
/// HWND through its raw pointer value.
fn hwnd_of(window: &Window) -> HWND {
    let handle = HasWindowHandle::window_handle(window).expect("no native window handle");
    match handle.as_raw() {
        RawWindowHandle::Win32(h) => h.hwnd.get() as HWND,
        other => panic!("expected Win32 handle, got {other:?}"),
    }
}

struct ProbeView {
    adapter: Option<SubclassingAdapter>,
}

impl Render for ProbeView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let frame = FRAMES.fetch_add(1, SeqCst) + 1;
        div()
            .size_full()
            .child(format!("SR0-B modal probe, frame {frame}"))
    }
}

// ---- Size-loop and modal observation (our own subclass, outermost) ----

static EV_COUNT: AtomicU64 = AtomicU64::new(0);
static EV_T0: Mutex<Option<std::time::Instant>> = Mutex::new(None);

/// Diagnostic event log to stderr (bounded to 1500 lines): size/move related window messages.
fn ev(tag: &str, a: u64, b: u64, c: u64, d: u64) {
    if EV_COUNT.fetch_add(1, SeqCst) >= 1500 {
        return;
    }
    let mut g = EV_T0.lock().unwrap_or_else(|e| e.into_inner());
    let t0 = *g.get_or_insert_with(std::time::Instant::now);
    eprintln!("[sr0-b ev t={:.0}ms] {tag} {a:#x} {b:#x} {c} {d}", t0.elapsed().as_secs_f64() * 1000.0);
}

unsafe extern "system" fn observe_proc(
    hwnd: HWND,
    msg: u32,
    w: usize,
    l: isize,
    _id: usize,
    _data: usize,
) -> isize {
    const WM_NCHITTEST: u32 = 0x0084;
    const WM_SYSCOMMAND: u32 = 0x0112;
    const WM_SIZING: u32 = 0x0214;
    const WM_SIZE: u32 = 0x0005;
    const WM_WINDOWPOSCHANGED: u32 = 0x0047;
    const WM_CAPTURECHANGED: u32 = 0x0215;
    const WM_LBUTTONUP: u32 = 0x0202;
    const WM_NCLBUTTONUP: u32 = 0x00A2;
    static HT_LOGGED: AtomicU64 = AtomicU64::new(0);
    static HT_EDGE: AtomicU64 = AtomicU64::new(0);
    match msg {
        WM_ENTERSIZEMOVE => {
            SIZING.store(true, SeqCst);
            SIZE_ENTER.fetch_add(1, SeqCst);
            ev("ENTERSIZEMOVE", 0, 0, 0, 0);
        }
        WM_EXITSIZEMOVE => {
            SIZING.store(false, SeqCst);
            SIZE_EXIT.fetch_add(1, SeqCst);
            ev("EXITSIZEMOVE", 0, 0, 0, 0);
        }
        WM_NCLBUTTONDOWN => {
            NC_LBUTTON_DOWN.fetch_add(1, SeqCst);
            NC_LAST_HT.store(w as u64, SeqCst);
            ev("NCLBUTTONDOWN hit", w as u64, 0, (l & 0xFFFF) as i16 as i64 as u64, ((l >> 16) & 0xFFFF) as i16 as i64 as u64);
        }
        WM_NCLBUTTONUP => ev("NCLBUTTONUP hit", w as u64, 0, 0, 0),
        WM_LBUTTONUP => ev("LBUTTONUP", 0, 0, 0, 0),
        WM_CAPTURECHANGED => ev("CAPTURECHANGED", 0, 0, 0, 0),
        WM_SYSCOMMAND => ev("SYSCOMMAND wparam", w as u64, 0, 0, 0),
        WM_SIZING => ev("SIZING edge", w as u64, 0, 0, 0),
        WM_SIZE => ev("SIZE type", w as u64, 0, (l & 0xFFFF) as u64, ((l >> 16) & 0xFFFF) as u64),
        WM_WINDOWPOSCHANGED => {
            let p = l as *const u8;
            let (cx, cy, fl) = unsafe {
                (
                    *(p.add(24) as *const i32) as i64 as u64,
                    *(p.add(28) as *const i32) as i64 as u64,
                    *(p.add(32) as *const u32) as u64,
                )
            };
            ev("WINDOWPOSCHANGED flags", fl, 0, cx, cy);
        }
        WM_NCHITTEST => {
            let r = unsafe { DefSubclassProc(hwnd, msg, w, l) };
            let edge = (10..=17).contains(&r);
            if (edge && HT_EDGE.fetch_add(1, SeqCst) < 12) || HT_LOGGED.fetch_add(1, SeqCst) < 4 {
                ev("NCHITTEST result", r as u64, 0, (l & 0xFFFF) as i16 as i64 as u64, ((l >> 16) & 0xFFFF) as i16 as i64 as u64);
            }
            return r;
        }
        _ => {}
    }
    DefSubclassProc(hwnd, msg, w, l)
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Auto-dismiss: 1 s after the dialog is created, post IDOK to it.
unsafe extern "system" fn taskdialog_cb(hwnd: HWND, msg: u32, _w: usize, _l: isize, _data: isize) -> i32 {
    if msg == TDN_CREATED {
        MODAL_CREATED.store(true, SeqCst);
        let h = hwnd as usize;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(1000));
            unsafe { PostMessageW(h as HWND, TDM_CLICK_BUTTON, IDOK as usize, 0) };
        });
    }
    0
}

/// Runs a TaskDialog on the UI thread. Called from a dedicated foreground task,
/// outside any drain poll and any GPUI borrow.
fn open_task_dialog() -> i32 {
    let title = wide("SR0-B modal");
    let main = wide("SR0-B modal request");
    let content = wide("Auto-dismissed after 1 s by the probe timer.");
    let cfg = TaskDialogConfig {
        cb_size: std::mem::size_of::<TaskDialogConfig>() as u32,
        hwnd_parent: std::ptr::null_mut(),
        h_instance: std::ptr::null_mut(),
        flags: 0,
        common_buttons: TDCBF_OK_BUTTON,
        window_title: title.as_ptr(),
        main_icon: std::ptr::null(),
        main_instruction: main.as_ptr(),
        content: content.as_ptr(),
        buttons_count: 0,
        buttons: std::ptr::null(),
        default_button: 0,
        radio_count: 0,
        radios: std::ptr::null(),
        default_radio: 0,
        verification_text: std::ptr::null(),
        expanded_info: std::ptr::null(),
        expanded_control: std::ptr::null(),
        collapsed_control: std::ptr::null(),
        footer_icon: std::ptr::null(),
        footer: std::ptr::null(),
        callback: Some(taskdialog_cb),
        callback_data: 0,
        width: 0,
    };
    let mut button: i32 = 0;
    let hr = unsafe {
        TaskDialogIndirect(&cfg, &mut button, std::ptr::null_mut(), std::ptr::null_mut())
    };
    if hr != 0 {
        MODAL_ERRORS.fetch_add(1, SeqCst);
        eprintln!("[sr0-b rust] TaskDialogIndirect hr={hr:#x}");
        return hr;
    }
    button
}

/// Runs in its own foreground task. Holds no App/Window borrow while the
/// modal loop pumps messages.
fn run_modal(kind: u32) {
    if kind != MODAL_TASKDIALOG {
        MODAL_ERRORS.fetch_add(1, SeqCst);
        return;
    }
    MODAL_OPENED.fetch_add(1, SeqCst);
    MODAL_OPENING.store(true, SeqCst);
    MODAL_ACTIVE.store(true, SeqCst);
    let result = open_task_dialog();
    MODAL_ACTIVE.store(false, SeqCst);
    MODAL_OPENING.store(false, SeqCst);
    MODAL_RESULTS.fetch_add(1, SeqCst);
    let rec = SwrUiRecord {
        tag: UI_TAG_MODAL_RESULT,
        action: kind,
        value: result,
        _pad: 0,
        window_gen: 0,
        node_id: 0,
        snapshot_version: 0,
    };
    push_ui(rec);
    wake_swift();
}

// ---- Launch and drain ----

fn waiter_loop(handle: usize) {
    loop {
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

fn launch(cx: &mut App, host: HostRef) {
    let bounds = Bounds::centered(None, size(px(640.), px(360.)), cx);
    let handle: WindowHandle<ProbeView> = match cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("SR0-B modal".into()),
                ..Default::default()
            }),
            // The AccessKit adapter must exist before the window is shown.
            show: false,
            ..Default::default()
        },
        |_, cx| cx.new(|_| ProbeView { adapter: None }),
    ) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("[sr0-b rust] open_window failed: {e:?}");
            OPEN_FAILED.store(true, SeqCst);
            cx.quit();
            return;
        }
    };

    handle
        .update(cx, |view, window, _cx| {
            let hwnd = hwnd_of(window);
            MAIN_HWND.store(hwnd as usize, SeqCst);
            view.adapter = Some(SubclassingAdapter::new(
                AkHWND(hwnd),
                Activation,
                Actions,
            ));
            unsafe { SetWindowSubclass(hwnd, observe_proc, 0x5352, 0) };
            window.activate_window();
            // Make sure no other window covers the probe for the synthetic-input run.
            unsafe { SetForegroundWindow(hwnd) };
        })
        .expect("window update failed during launch");

    {
        let mut q = lock_ui();
        q.live_gen = 1;
    }

    // Close observer runs inside App's close path. It closes the queue under
    // its lock, then wakes the drain task.
    let closed_sub = cx.on_window_closed(|_cx| {
        {
            let mut q = lock_ui();
            q.live_gen = 0;
        }
        WINDOW_CLOSED.store(true, SeqCst);
        signal_notify();
    });

    // Frame clock: 16 ms ticks force a re-render and a Swift tick callback.
    cx.spawn(async move |cx: &mut AsyncApp| loop {
        cx.background_executor()
            .timer(Duration::from_millis(16))
            .await;
        let alive = cx.update(|cx| handle.update(cx, |_v, _w, cx| cx.notify()).is_ok());
        if !matches!(alive, Ok(true)) || QUIT_REQUESTED.load(SeqCst) {
            break;
        }
        host_call(KIND_TICK);
        TICK_CALLS.fetch_add(1, SeqCst);
    })
    .detach();

    // Drain task. Its body runs as a foreground runnable with no App/Window borrow.
    cx.spawn(async move |cx: &mut AsyncApp| {
        let _keep_subscription_alive = closed_sub;
        host_call(KIND_LOOP_READY);

        let mut close_issued = false;
        loop {
            WaitSignal.await;
            DRAIN_CALLS_TOTAL.fetch_add(1, SeqCst);
            host_call(KIND_DRAIN);

            // Modal requests open in a separate task, not inside this poll.
            let pending = MODAL_PENDING.lock().unwrap_or_else(|e| e.into_inner()).take();
            if let Some(kind) = pending {
                cx.spawn(async move |_cx: &mut AsyncApp| run_modal(kind)).detach();
            }

            if QUIT_REQUESTED.load(SeqCst) && !close_issued {
                close_issued = true;
                let _ = cx.update(|cx| {
                    let _ = handle.update(cx, |_, window, _| window.remove_window());
                });
            }

            if WINDOW_CLOSED.load(SeqCst) {
                host_call(KIND_WINDOW_CLOSED);
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
        tick: raw.tick,
        window_closed: raw.window_closed,
    };
    *HOST.lock().unwrap_or_else(|e| e.into_inner()) = Some(host);
    UI_THREAD.store(unsafe { GetCurrentThreadId() }, SeqCst);

    std::panic::set_hook(Box::new(|info| {
        PANICS.fetch_add(1, SeqCst);
        eprintln!("[sr0-b rust] panic: {info}");
    }));

    if std::thread::Builder::new()
        .name("swr-wake-waiter".into())
        .spawn(move || waiter_loop(wake))
        .is_err()
    {
        RUNNING.store(false, SeqCst);
        return SWR_ERR_WAKE;
    }

    Application::new().run(move |cx: &mut App| launch(cx, host));

    let rc = if OPEN_FAILED.load(SeqCst) { SWR_ERR_APP } else { SWR_OK };
    println!(
        "[sr0-b rust] drain_calls={} tick_calls={} deferred_total={} nested_executed={} drains_idle={} drains_sizing={} drains_modal={} drains_both={} selftest_detected={} panics={} wake_signals={} wake_wait_failures={} frames_rendered={} size_enter={} size_exit={} modal_requests={} modal_opened={} modal_results={} modal_errors={} run_rc={}",
        DRAIN_CALLS_TOTAL.load(SeqCst),
        TICK_CALLS.load(SeqCst),
        DEFERRED_TOTAL.load(SeqCst),
        NESTED_EXECUTED.load(SeqCst),
        DRAINS_BY_PHASE[0].load(SeqCst),
        DRAINS_BY_PHASE[PHASE_SIZING].load(SeqCst),
        DRAINS_BY_PHASE[PHASE_MODAL].load(SeqCst),
        DRAINS_BY_PHASE[PHASE_SIZING | PHASE_MODAL].load(SeqCst),
        SELFTEST_DETECTED.load(SeqCst),
        PANICS.load(SeqCst),
        WAKE_SIGNALS.load(SeqCst),
        WAKE_WAIT_FAILURES.load(SeqCst),
        FRAMES.load(SeqCst),
        SIZE_ENTER.load(SeqCst),
        SIZE_EXIT.load(SeqCst),
        MODAL_REQUESTS.load(SeqCst),
        MODAL_OPENED.load(SeqCst),
        MODAL_RESULTS.load(SeqCst),
        MODAL_ERRORS.load(SeqCst),
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
    pub tick: Option<extern "C" fn(*mut c_void)>,
    pub window_closed: Option<extern "C" fn(*mut c_void)>,
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

/// Thread-safe. Wakes the drain task, which closes the window outside any borrow.
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

/// Swift-initiated modal request. Queued; the modal opens in its own foreground
/// task after the current drain unwinds. Safe from any callback or thread.
#[no_mangle]
pub extern "C" fn swr_request_modal(kind: u32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if kind != MODAL_TASKDIALOG {
            // Popup menu (MODAL_POPUP) is declared in the ABI but not implemented here.
            return SWR_ERR_ARGS;
        }
        MODAL_REQUESTS.fetch_add(1, SeqCst);
        *MODAL_PENDING.lock().unwrap_or_else(|e| e.into_inner()) = Some(kind);
        signal_notify();
        SWR_OK
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Pops one record from the bounded UI queue into `out`. Returns 1 when a record
/// was written, 0 when the queue is empty. Stale records are skipped and counted.
#[no_mangle]
pub extern "C" fn swr_ax_pop(out: *mut SwrUiRecord) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if out.is_null() {
            return SWR_ERR_ARGS;
        }
        let mut rec = SwrUiRecord::default();
        if pop_record(&mut rec) {
            unsafe { *out = rec };
            1
        } else {
            0
        }
    }))
    .unwrap_or(SWR_ERR_PANIC)
}

/// Bitmask of the current modal phase: bit 0 = size loop, bit 1 = modal dialog.
#[no_mangle]
pub extern "C" fn swr_phase() -> u32 {
    catch_unwind(|| current_phase() as u32).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn swr_frames_rendered() -> u64 {
    catch_unwind(|| FRAMES.load(SeqCst)).unwrap_or(0)
}

/// Counter by index (see the header for the index list). Returns 0 for unknown indices.
#[no_mangle]
pub extern "C" fn swr_stat(index: u32) -> u64 {
    catch_unwind(|| match index {
        0 => AX_ATTEMPTS.load(SeqCst),
        1 => AX_ENQUEUED.load(SeqCst),
        2 => AX_FULL.load(SeqCst),
        3 => AX_REJECTED_POST.load(SeqCst),
        4 => AX_POPPED_APPLIED.load(SeqCst),
        5 => AX_POPPED_STALE.load(SeqCst),
        6 => AX_ENQ_WHILE_CLOSED.load(SeqCst),
        7 => AX_APPLIED_AFTER_CLOSE.load(SeqCst),
        8 => lock_ui().buf.len() as u64,
        9 => DRAIN_CALLS_TOTAL.load(SeqCst),
        10 => DRAINS_BY_PHASE[0].load(SeqCst),
        11 => DRAINS_BY_PHASE[PHASE_SIZING].load(SeqCst),
        12 => DRAINS_BY_PHASE[PHASE_MODAL].load(SeqCst),
        13 => DRAINS_BY_PHASE[PHASE_SIZING | PHASE_MODAL].load(SeqCst),
        14 => DEFERRED_TOTAL.load(SeqCst),
        15 => NESTED_EXECUTED.load(SeqCst),
        16 => PANICS.load(SeqCst),
        17 => MODAL_REQUESTS.load(SeqCst),
        18 => MODAL_OPENED.load(SeqCst),
        19 => MODAL_RESULTS.load(SeqCst),
        20 => MODAL_ERRORS.load(SeqCst),
        21 => SIZE_ENTER.load(SeqCst),
        22 => SIZE_EXIT.load(SeqCst),
        23 => FRAMES.load(SeqCst),
        24 => TICK_CALLS.load(SeqCst),
        25 => WAKE_SIGNALS.load(SeqCst),
        26 => WAKE_WAIT_FAILURES.load(SeqCst),
        27 => SELFTEST_DETECTED.load(SeqCst),
        28 => NC_LBUTTON_DOWN.load(SeqCst),
        29 => NC_LAST_HT.load(SeqCst),
        _ => 0,
    })
    .unwrap_or(0)
}

/// Called only from inside a drain callback. Re-enters host_call(drain) and checks
/// that the guard deferred it. Returns 1 when deferred, 0 otherwise, -1 when not
/// inside a drain.
#[no_mangle]
pub extern "C" fn swr_selftest_reentry() -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if !HOST_ACTIVE.load(SeqCst) {
            return -1;
        }
        let before = DEFERRED_TOTAL.load(SeqCst);
        host_call(KIND_DRAIN);
        if DEFERRED_TOTAL.load(SeqCst) == before + 1 {
            SELFTEST_DETECTED.fetch_add(1, SeqCst);
            1
        } else {
            0
        }
    }))
    .unwrap_or(SWR_ERR_PANIC)
}
