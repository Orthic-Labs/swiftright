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
use std::sync::atomic::{AtomicU64, Ordering::SeqCst};
use std::sync::{Arc, Mutex};

use accesskit_windows::{SubclassingAdapter, HWND as AkHWND};
use gpui::{
    canvas, div, fill, point, prelude::*, px, rgba, size, App, AsyncApp, Application, Bounds,
    ContentMask, Context, ElementInputHandler, Entity, EntityInputHandler, FocusHandle,
    IntoElement, KeyDownEvent, MouseButton, MouseDownEvent, MouseUpEvent, Pixels, Render,
    TextAlign, TitlebarOptions, UTF16Selection, Window, WindowBackgroundAppearance, WindowBounds,
    WindowHandle, WindowOptions, WindowTextSystem,
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::abi::*;
use crate::ax::{Actions, Activation};
use crate::rt::*;
use crate::text::{RunSlab, TextCache};
use crate::tree::{Prim, Tree};

#[link(name = "user32")]
extern "system" {
    fn MessageBoxW(hwnd: *mut c_void, text: *const u16, caption: *const u16, utype: u32) -> i32;
    fn GetWindowLongPtrW(hwnd: *mut c_void, index: i32) -> isize;
    fn GetClientRect(hwnd: *mut c_void, rect: *mut [i32; 4]) -> i32;
    fn GetDpiForWindow(hwnd: *mut c_void) -> u32;
    fn SetProcessDpiAwarenessContext(context: isize) -> i32;
}

// ------------------------------------------------------------ UI-thread state

pub struct Ui {
    pub text_system: Option<Arc<WindowTextSystem>>,
    pub runs: RunSlab,
    pub cache: TextCache,
    pub tree: Tree,
}

thread_local! {
    static UI: RefCell<Ui> = RefCell::new(Ui {
        text_system: None,
        runs: RunSlab::new(),
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

struct ModalPending {
    id: u64,
    buttons: u32,
    title: String,
    message: String,
}
static MODAL: Mutex<Option<ModalPending>> = Mutex::new(None);

pub fn queue_modal(id: u64, buttons: u32, title: String, message: String) -> Status {
    let mut m = MODAL.lock().unwrap_or_else(|e| e.into_inner());
    if m.is_some() {
        return E_QUEUE_FULL;
    }
    *m = Some(ModalPending { id, buttons, title, message });
    drop(m);
    signal_notify();
    SWR_OK
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Runs in its own foreground task: no App/Window borrow and no host callback is active.
fn run_modal(req: ModalPending) {
    let utype = match req.buttons {
        2 => 1u32, // MB_OKCANCEL
        3 => 4u32, // MB_YESNO
        _ => 0u32, // MB_OK
    };
    let t = wide(&req.title);
    let m = wide(&req.message);
    let owner = MAIN_HWND.load(SeqCst) as *mut c_void;
    let result = unsafe { MessageBoxW(owner, m.as_ptr(), t.as_ptr(), utype) };
    let mut ev = Event::new(EV_MODAL_RESULT, 0);
    ev.arg = req.id;
    ev.i0 = result;
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
                    if let Some(wl) = &run.wrapped {
                        let o = point(
                            origin.x + px((*x + tx.0) * inv),
                            origin.y + px((*y + tx.1) * inv),
                        );
                        let lh = px(run.line_height_dip);
                        masked(window, clip, |w| {
                            let _ = wl.paint(o, lh, TextAlign::Left, None, w, cx);
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
                // Post-close pump (rev 0.5): drain only. The window and its tree are gone;
                // commits, measurements and tick requests are refused with SWR_E_SHUTDOWN.
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
                    break;
                }
                if POST_CLOSE_EXPIRED.load(SeqCst) {
                    bump(S_POST_TIMEOUTS);
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
                });
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
