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
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering::SeqCst};
use std::sync::{Arc, Mutex};

use accesskit_windows::{SubclassingAdapter, HWND as AkHWND};
use gpui::{
    canvas, div, fill, point, prelude::*, px, rgba, size, App, AsyncApp, Application, Bounds,
    ContentMask, Context, Corners, ElementInputHandler, Entity, EntityInputHandler, FocusHandle,
    IntoElement, KeyDownEvent, MouseButton, MouseDownEvent, MouseUpEvent, Pixels, Render,
    RenderImage, TextAlign, TitlebarOptions, UTF16Selection, Window, WindowBackgroundAppearance,
    WindowBounds, WindowHandle, WindowOptions, WindowTextSystem,
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::abi::*;
use crate::ax::{Actions, Activation};
use crate::rt::*;
use crate::text::{RunSlab, Slab, TextCache, TrackedImage, MAX_RUNS};
use crate::tree::{Prim, Tree};

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

/// Runs in its own foreground task: no App/Window borrow and no host callback is active.
fn run_modal(req: ModalPending) {
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
    push_event(ev);
}

// ------------------------------------------------------------------ the view

pub struct RootView {
    focus: FocusHandle,
    adapter: Option<SubclassingAdapter>,
}

impl RootView {
    fn publish_ax(&mut self) {
        if let Some(a) = self.adapter.as_mut() {
            if let Some(events) = a.update_if_active(crate::ax::build_tree) {
                events.raise();
            }
        }
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

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focus = self.focus.clone();
        let focus_paint = self.focus.clone();
        let view = cx.entity();
        div()
            .size_full()
            .track_focus(&focus)
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

fn masked(window: &mut Window, clip: Option<Bounds<Pixels>>, f: impl FnOnce(&mut Window)) {
    match clip {
        Some(b) => window.with_content_mask(Some(ContentMask { bounds: b }), f),
        None => f(window),
    }
}

fn paint_tree(
    tree: &Tree,
    origin: gpui::Point<Pixels>,
    scale: f32,
    window: &mut Window,
    cx: &mut App,
) {
    let inv = 1.0 / scale;
    for id in tree.order.iter() {
        let Some(node) = tree.nodes.get(id) else { continue };
        let mut clips: Vec<Bounds<Pixels>> = Vec::new();
        let mut tx = (0.0f32, 0.0f32);
        let mut tx_stack: Vec<(f32, f32)> = Vec::new();
        for p in &node.prims {
            let clip = clips.last().cloned();
            match p {
                Prim::Rect { r, color, border_color, border_w, radius } => {
                    let b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    let mut q = fill(b, rgba(*color));
                    if *radius > 0.0 {
                        q = q.corner_radii(px(radius * inv));
                    }
                    if *border_w > 0.0 {
                        q = q.border_widths(px(border_w * inv)).border_color(rgba(*border_color));
                    }
                    masked(window, clip, |w| w.paint_quad(q));
                }
                Prim::Text { x, y, run } => {
                    // Rev 0.6: one GPUI WrappedLine per paragraph, stacked by `top` (run-local px).
                    let lh = px(run.line_height_dip);
                    for (wl, top) in run.wrapped.iter() {
                        let o = point(
                            origin.x + px((*x + tx.0) * inv),
                            origin.y + px((*y + *top + tx.1) * inv),
                        );
                        masked(window, clip, |w| {
                            let _ = wl.paint(o, lh, TextAlign::Left, None, w, cx);
                        });
                    }
                }
                Prim::Image { r, radius, img } => {
                    if r[2] > 0.0 && r[3] > 0.0 {
                        let b = Bounds::new(
                            point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                            size(px(r[2] * inv), px(r[3] * inv)),
                        );
                        let corners = Corners::all(px(*radius * inv));
                        let img = img.img.clone();
                        masked(window, clip, |w| {
                            let _ = w.paint_image(b, corners, img, 0, false);
                        });
                    }
                }
                Prim::Underline { r, color } => {
                    // SWR_PRIM_UNDERLINE (rev 0.5): solid bar, painted as a quad in v0.
                    let b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    masked(window, clip, |w| w.paint_quad(fill(b, rgba(*color))));
                }
                Prim::ClipPush(r) => {
                    let mut b = Bounds::new(
                        point(origin.x + px((r[0] + tx.0) * inv), origin.y + px((r[1] + tx.1) * inv)),
                        size(px(r[2] * inv), px(r[3] * inv)),
                    );
                    if let Some(prev) = clips.last() {
                        b = b.intersect(prev);
                    }
                    clips.push(b);
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
    let bits = scale.to_bits();
    if WIN_W.swap(w, SeqCst) != w || WIN_H.swap(h, SeqCst) != h || WIN_SCALE_BITS.swap(bits, SeqCst) != bits {
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
            paint_tree(&ui.tree, bounds.origin, scale, window, cx);
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
    let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f(&host, win, node)));
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
const WM_IME_SETCONTEXT: u32 = 0x0281;
const WM_IME_NOTIFY: u32 = 0x0282;
const WM_IME_STARTCOMPOSITION: u32 = 0x010D;
const WM_IME_ENDCOMPOSITION: u32 = 0x010E;
const WM_IME_COMPOSITION: u32 = 0x010F;
static IME_MSG_LOGS: AtomicU32 = AtomicU32::new(0);

fn place_ime_windows(hwnd: *mut c_void) {
    let r = with_ime(|h, win, node| {
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
    .flatten();
    let Some(r) = r else { return };
    let (x, y, w, h) = (r.x as i32, r.y as i32, (r.w as i32).max(1), (r.h as i32).max(1));
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
    let out = DefSubclassProc(hwnd, msg, w, l);
    match msg {
        WM_IME_SETCONTEXT | WM_IME_NOTIFY | WM_IME_STARTCOMPOSITION | WM_IME_ENDCOMPOSITION | WM_IME_COMPOSITION => {
            // Evidence for the next desktop run: which IME messages arrive, and what they carry.
            if IME_MSG_LOGS.fetch_add(1, SeqCst) < 400 {
                eprintln!("[swiftright-render] ime_msg msg=0x{msg:04X} wparam=0x{w:X} lparam=0x{:X}", l as usize);
            }
            if msg == WM_IME_COMPOSITION || msg == WM_IME_STARTCOMPOSITION || (msg == WM_IME_NOTIFY && matches!(w, 3 | 4 | 5 | 6 | 7)) {
                place_ime_windows(hwnd);
            }
        }
        _ => {}
    }
    out
}

fn install_ime_subclass(hwnd: *mut c_void) {
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
        if call_host(|| f(ctx, win, ts)) {
            bump(S_TICKS_DEL);
        }
    }
}

fn present(cx: &mut AsyncApp, handle: WindowHandle<RootView>) {
    let _ = cx.update(|cx| {
        let _ = handle.update(cx, |view, window, cx| {
            view.publish_ax();
            window.refresh();
            cx.notify();
        });
    });
}

fn launch(cx: &mut App, title: String, width: u32, height: u32, host: Host) {
    let bounds = Bounds::centered(None, size(px(width as f32), px(height as f32)), cx);
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
        view.adapter = Some(SubclassingAdapter::new(AkHWND(hwnd), Activation, Actions));
        window.focus(&view.focus);
        window.activate_window();
        if let Ok(()) = with_ui(|ui| ui.text_system = Some(window.text_system().clone())) {}
        // GPUI reports a 0x0 viewport at scale 1 while the window is still hidden, so the
        // initial metrics come straight from Win32 (client rect + per-window DPI).
        let mut rc = [0i32; 4];
        unsafe { GetClientRect(hwnd, &mut rc) };
        let dpi = unsafe { GetDpiForWindow(hwnd) };
        let s = if dpi == 0 { window.scale_factor() } else { dpi as f32 / 96.0 };
        WIN_W.store((rc[2] - rc[0]).max(0) as u32, SeqCst);
        WIN_H.store((rc[3] - rc[1]).max(0) as u32, SeqCst);
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

    // Drain task: its body runs as a GPUI foreground runnable, outside every App and
    // Window borrow. All host callbacks except ime_* are issued from here.
    cx.spawn(async move |cx: &mut AsyncApp| {
        let _keep_subscription_alive = closed_sub;
        if let Some(f) = host.loop_ready {
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

            let pending = MODAL.lock().unwrap_or_else(|e| e.into_inner()).take();
            if let Some(req) = pending {
                if !close_issued {
                    cx.spawn(async move |_cx: &mut AsyncApp| run_modal(req)).detach();
                }
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
    if OPEN_FAILED.load(SeqCst) {
        E_PLATFORM
    } else {
        SWR_OK
    }
}
