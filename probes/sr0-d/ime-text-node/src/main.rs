//! SR0-D IME text-node probe.
//!
//! A hand-authored text node whose buffer lives in `ExternalBuffer` (a plain Rust
//! struct owned by the view, not by any GPUI text widget). It is registered with
//! GPUI 0.2.2's input path through `Window::handle_input` + `ElementInputHandler`,
//! so the Windows IMM32 messages (WM_IME_COMPOSITION, WM_IME_STARTCOMPOSITION,
//! WM_CHAR) are delivered to `EntityInputHandler` methods. Every handler call logs
//! one line to stderr.
//!
//! Log prefix: `[ime-probe]`. All handler calls must run on the UI thread.

#[cfg(windows)]
mod probe {
    use gpui::{
        App, Application, Bounds, Context, Element, ElementId, ElementInputHandler, Entity,
        EntityInputHandler, FocusHandle, GlobalElementId, IntoElement, KeyBinding, LayoutId,
        Pixels, Point, Render, Style, UTF16Selection, Window, WindowBounds, WindowOptions,
        actions, div, point, prelude::*, px, relative, size,
    };
    use std::ops::Range;
    use std::sync::OnceLock;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread::ThreadId;

    actions!(ime_probe, [Backspace, SelectAll]);

    /// Recorded in `run` before the GPUI loop starts; every handler asserts against it.
    static UI_THREAD: OnceLock<ThreadId> = OnceLock::new();
    static FIRST_PAINT_LOGGED: AtomicBool = AtomicBool::new(false);

    /// Fixed candidate/composition anchor in logical window pixels. Deterministic on purpose.
    const CANDIDATE_X: f32 = 320.0;
    const CANDIDATE_Y: f32 = 160.0;
    const CANDIDATE_H: f32 = 24.0;

    fn assert_ui_thread(method: &str) {
        let ui = *UI_THREAD.get().expect("UI thread not recorded before run");
        let cur = std::thread::current().id();
        assert!(
            cur == ui,
            "[ime-probe] {method} called off the UI thread: current={cur:?} ui={ui:?}"
        );
    }

    /// The external buffer. Ranges are UTF-16 code units, as the IME API requires.
    #[derive(Debug, Clone)]
    pub struct ExternalBuffer {
        pub text: String,
        pub selection: Range<usize>,
        pub marked: Option<Range<usize>>,
    }

    impl ExternalBuffer {
        fn utf16_len(&self) -> usize {
            self.text.encode_utf16().count()
        }

        /// UTF-16 offset -> byte offset (clamped to the buffer end).
        fn byte_of(&self, u16_off: usize) -> usize {
            let mut units = 0usize;
            for (b, ch) in self.text.char_indices() {
                if units >= u16_off {
                    return b;
                }
                units += ch.len_utf16();
            }
            self.text.len()
        }

        /// Byte offset (must be a char boundary) -> UTF-16 offset.
        fn u16_of(&self, byte: usize) -> usize {
            self.text[..byte].encode_utf16().count()
        }

        fn clamp16(&self, r: Range<usize>) -> Range<usize> {
            let n = self.utf16_len();
            let s = r.start.min(n);
            let e = r.end.min(n).max(s);
            s..e
        }

        fn replace16(&mut self, range16: Range<usize>, new_text: &str) -> Range<usize> {
            let r = self.clamp16(range16);
            let bs = self.byte_of(r.start);
            let be = self.byte_of(r.end);
            self.text.replace_range(bs..be, new_text);
            r.start..r.start + new_text.encode_utf16().count()
        }

        fn display(&self) -> String {
            match &self.marked {
                Some(m) => {
                    let m = self.clamp16(m.clone());
                    let (ms, me) = (self.byte_of(m.start), self.byte_of(m.end));
                    format!(
                        "{}[{}]{}",
                        &self.text[..ms],
                        &self.text[ms..me],
                        &self.text[me..]
                    )
                }
                None => self.text.clone(),
            }
        }

        fn state(&self) -> String {
            format!(
                "text={:?} selection16={:?} marked16={:?}",
                self.text, self.selection, self.marked
            )
        }
    }

    pub struct ImeProbe {
        pub focus_handle: FocusHandle,
        pub buffer: ExternalBuffer,
    }

    impl ImeProbe {
        fn on_backspace(&mut self, _: &Backspace, window: &mut Window, cx: &mut Context<Self>) {
            assert_ui_thread("action:Backspace");
            if !self.buffer.selection.is_empty() {
                eprintln!("[ime-probe] action=Backspace selection-nonempty -> delete selection");
                self.replace_text_in_range(None, "", window, cx);
                return;
            }
            let caret16 = self.buffer.selection.start;
            if caret16 == 0 {
                eprintln!("[ime-probe] action=Backspace caret=0 -> no-op");
                return;
            }
            let caret_b = self.buffer.byte_of(caret16);
            let (prev_b, ch) = self.buffer.text[..caret_b]
                .char_indices()
                .last()
                .expect("caret>0 implies a previous char");
            let start16 = self.buffer.u16_of(prev_b);
            eprintln!(
                "[ime-probe] action=Backspace caret16={caret16} delete16={}..{}",
                start16,
                start16 + ch.len_utf16()
            );
            self.replace_text_in_range(Some(start16..start16 + ch.len_utf16()), "", window, cx);
        }

        fn on_select_all(&mut self, _: &SelectAll, _window: &mut Window, cx: &mut Context<Self>) {
            assert_ui_thread("action:SelectAll");
            self.buffer.selection = 0..self.buffer.utf16_len();
            eprintln!(
                "[ime-probe] action=SelectAll -> {}",
                self.buffer.state()
            );
            cx.notify();
        }
    }

    impl EntityInputHandler for ImeProbe {
        fn text_for_range(
            &mut self,
            range: Range<usize>,
            adjusted: &mut Option<Range<usize>>,
            _window: &mut Window,
            _cx: &mut Context<Self>,
        ) -> Option<String> {
            assert_ui_thread("text_for_range");
            let r = self.buffer.clamp16(range.clone());
            *adjusted = Some(r.clone());
            let s = self.buffer.text[self.buffer.byte_of(r.start)..self.buffer.byte_of(r.end)]
                .to_string();
            eprintln!(
                "[ime-probe] text_for_range args16={range:?} adjusted={r:?} -> {s:?} | {}",
                self.buffer.state()
            );
            Some(s)
        }

        fn selected_text_range(
            &mut self,
            ignore_disabled_input: bool,
            _window: &mut Window,
            _cx: &mut Context<Self>,
        ) -> Option<UTF16Selection> {
            assert_ui_thread("selected_text_range");
            let sel = UTF16Selection {
                range: self.buffer.selection.clone(),
                reversed: false,
            };
            eprintln!(
                "[ime-probe] selected_text_range ignore_disabled={ignore_disabled_input} -> {:?} | {}",
                sel.range,
                self.buffer.state()
            );
            Some(sel)
        }

        fn marked_text_range(
            &self,
            _window: &mut Window,
            _cx: &mut Context<Self>,
        ) -> Option<Range<usize>> {
            assert_ui_thread("marked_text_range");
            let m = self.buffer.marked.clone();
            eprintln!("[ime-probe] marked_text_range -> {m:?}");
            m
        }

        fn unmark_text(&mut self, _window: &mut Window, cx: &mut Context<Self>) {
            assert_ui_thread("unmark_text");
            self.buffer.marked = None;
            eprintln!("[ime-probe] unmark_text | {}", self.buffer.state());
            cx.notify();
        }

        fn replace_text_in_range(
            &mut self,
            range: Option<Range<usize>>,
            text: &str,
            _window: &mut Window,
            cx: &mut Context<Self>,
        ) {
            assert_ui_thread("replace_text_in_range");
            let target = range
                .clone()
                .or_else(|| self.buffer.marked.clone())
                .unwrap_or_else(|| self.buffer.selection.clone());
            let ins = self.buffer.replace16(target.clone(), text);
            self.buffer.selection = ins.end..ins.end;
            self.buffer.marked = None;
            eprintln!(
                "[ime-probe] replace_text_in_range args_range16={range:?} target16={target:?} text={text:?} | {}",
                self.buffer.state()
            );
            cx.notify();
        }

        fn replace_and_mark_text_in_range(
            &mut self,
            range: Option<Range<usize>>,
            new_text: &str,
            new_selected: Option<Range<usize>>,
            _window: &mut Window,
            cx: &mut Context<Self>,
        ) {
            assert_ui_thread("replace_and_mark_text_in_range");
            let target = range
                .clone()
                .or_else(|| self.buffer.marked.clone())
                .unwrap_or_else(|| self.buffer.selection.clone());
            let ins = self.buffer.replace16(target.clone(), new_text);
            self.buffer.marked = if new_text.is_empty() {
                None
            } else {
                Some(ins.clone())
            };
            self.buffer.selection = match &new_selected {
                Some(r) => self
                    .buffer
                    .clamp16((ins.start + r.start)..(ins.start + r.end)),
                None => ins.end..ins.end,
            };
            eprintln!(
                "[ime-probe] replace_and_mark_text_in_range args_range16={range:?} target16={target:?} new_text={new_text:?} new_selected16={new_selected:?} | {}",
                self.buffer.state()
            );
            cx.notify();
        }

        fn bounds_for_range(
            &mut self,
            range: Range<usize>,
            element_bounds: Bounds<Pixels>,
            _window: &mut Window,
            _cx: &mut Context<Self>,
        ) -> Option<Bounds<Pixels>> {
            assert_ui_thread("bounds_for_range");
            let fixed = Bounds::new(
                point(px(CANDIDATE_X), px(CANDIDATE_Y)),
                size(px(2.0), px(CANDIDATE_H)),
            );
            eprintln!(
                "[ime-probe] bounds_for_range args16={range:?} element_bounds={element_bounds:?} -> fixed={fixed:?}"
            );
            Some(fixed)
        }

        fn character_index_for_point(
            &mut self,
            p: Point<Pixels>,
            _window: &mut Window,
            _cx: &mut Context<Self>,
        ) -> Option<usize> {
            assert_ui_thread("character_index_for_point");
            let idx = self.buffer.selection.start;
            eprintln!("[ime-probe] character_index_for_point point={p:?} -> {idx}");
            Some(idx)
        }
    }

    impl Render for ImeProbe {
        fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
            let display = self.buffer.display();
            let focus = self.focus_handle.clone();
            div()
                .size_full()
                .p_4()
                .track_focus(&focus)
                .on_action(cx.listener(Self::on_backspace))
                .on_action(cx.listener(Self::on_select_all))
                .flex()
                .flex_col()
                .child("SR0-D IME text node probe (external buffer, not a GPUI text widget)")
                .child(format!("buffer: {display}"))
                .child(format!("selection (utf16): {:?}", self.buffer.selection))
                .child(format!("marked (utf16): {:?}", self.buffer.marked))
                .child(TextNodeElement {
                    view: cx.entity(),
                })
        }
    }

    /// Hand-authored node: lays out a 32px strip and registers the view as the
    /// window's input handler for the current frame. Requires focus, like GPUI's own
    /// text input; registration is skipped (and logged) when unfocused.
    pub struct TextNodeElement {
        view: Entity<ImeProbe>,
    }

    impl IntoElement for TextNodeElement {
        type Element = Self;

        fn into_element(self) -> Self::Element {
            self
        }
    }

    impl Element for TextNodeElement {
        type RequestLayoutState = ();
        type PrepaintState = ();

        fn id(&self) -> Option<ElementId> {
            None
        }

        fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
            None
        }

        fn request_layout(
            &mut self,
            _id: Option<&GlobalElementId>,
            _inspector_id: Option<&gpui::InspectorElementId>,
            window: &mut Window,
            cx: &mut App,
        ) -> (LayoutId, Self::RequestLayoutState) {
            let mut style = Style::default();
            style.size.width = relative(1.).into();
            style.size.height = px(32.).into();
            (window.request_layout(style, [], cx), ())
        }

        fn prepaint(
            &mut self,
            _id: Option<&GlobalElementId>,
            _inspector_id: Option<&gpui::InspectorElementId>,
            _bounds: Bounds<Pixels>,
            _request_layout: &mut Self::RequestLayoutState,
            _window: &mut Window,
            _cx: &mut App,
        ) -> Self::PrepaintState {
        }

        fn paint(
            &mut self,
            _id: Option<&GlobalElementId>,
            _inspector_id: Option<&gpui::InspectorElementId>,
            bounds: Bounds<Pixels>,
            _request_layout: &mut Self::RequestLayoutState,
            _prepaint: &mut Self::PrepaintState,
            window: &mut Window,
            cx: &mut App,
        ) {
            let focus = self.view.read(cx).focus_handle.clone();
            let focused = focus.is_focused(window);
            if !FIRST_PAINT_LOGGED.swap(true, Ordering::SeqCst) {
                eprintln!(
                    "[ime-probe] first paint: bounds={bounds:?} focused={focused} handle_input_registered={focused}"
                );
            }
            window.handle_input(
                &focus,
                ElementInputHandler::new(bounds, self.view.clone()),
                cx,
            );
        }
    }

    pub fn run() {
        UI_THREAD
            .set(std::thread::current().id())
            .expect("run called twice");
        eprintln!(
            "[ime-probe] start ui_thread={:?}",
            std::thread::current().id()
        );

        Application::new().run(|cx: &mut App| {
            cx.bind_keys([
                KeyBinding::new("backspace", Backspace, None),
                KeyBinding::new("ctrl-a", SelectAll, None),
            ]);

            let bounds = Bounds::centered(None, size(px(640.), px(360.)), cx);
            let handle = cx
                .open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(bounds)),
                        ..Default::default()
                    },
                    |_, cx| {
                        cx.new(|cx| ImeProbe {
                            focus_handle: cx.focus_handle(),
                            buffer: ExternalBuffer {
                                text: String::new(),
                                selection: 0..0,
                                marked: None,
                            },
                        })
                    },
                )
                .expect("open_window failed");

            handle
                .update(cx, |view, window, _cx| {
                    window.focus(&view.focus_handle);
                    window.activate_window();
                    eprintln!("[ime-probe] window focused at startup");
                })
                .expect("focusing the probe view failed");

            cx.activate(true);
        });
    }
}

#[cfg(windows)]
fn main() {
    probe::run();
}

#[cfg(not(windows))]
fn main() {
    eprintln!("sr0d-ime-text-node is a Windows-only probe");
    std::process::exit(2);
}
