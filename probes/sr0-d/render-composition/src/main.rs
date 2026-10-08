//! SR0-D dependency probe: one binary that composes a published GPUI 0.2.2
//! window with a published accesskit_windows 0.35.1 SubclassingAdapter.

#[cfg(windows)]
mod probe {
    use accesskit::{
        Action, ActionHandler, ActionRequest, ActivationHandler, Node, NodeId, Rect, Role, TreeId,
        TreeInfo, TreeUpdate,
    };
    use accesskit_windows::{HWND, SubclassingAdapter};
    use gpui::{
        App, Application, Bounds, Context, IntoElement, Render, Window, WindowBounds,
        WindowOptions, div, prelude::*, px, size,
    };
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    use std::ffi::c_void;

    const ROOT_ID: NodeId = NodeId(1);
    const BUTTON_ID: NodeId = NodeId(2);
    const INPUT_ID: NodeId = NodeId(3);

    /// Called on the window thread; returns the full tree synchronously.
    struct Activation;

    impl ActivationHandler for Activation {
        fn request_initial_tree(&mut self) -> Option<TreeUpdate> {
            Some(build_tree())
        }
    }

    /// Must be Send. Logs only; never calls back into GPUI.
    struct Actions;

    impl ActionHandler for Actions {
        fn do_action(&mut self, request: ActionRequest) {
            eprintln!("[sr0-d] action request: {request:?}");
        }
    }

    fn build_tree() -> TreeUpdate {
        let mut root = Node::new(Role::Window);
        root.set_label("SR0-D probe window");
        root.set_children([BUTTON_ID, INPUT_ID]);

        let mut button = Node::new(Role::Button);
        button.set_label("Probe");
        button.add_action(Action::Click);
        button.add_action(Action::Focus);
        button.set_bounds(Rect { x0: 20.0, y0: 20.0, x1: 140.0, y1: 60.0 });

        let mut input = Node::new(Role::TextInput);
        input.set_label("Probe input");
        input.set_value("");
        input.add_action(Action::Focus);
        input.add_action(Action::SetValue);
        input.set_bounds(Rect { x0: 20.0, y0: 80.0, x1: 320.0, y1: 110.0 });

        TreeUpdate {
            nodes: vec![(ROOT_ID, root), (BUTTON_ID, button), (INPUT_ID, input)],
            tree: Some(TreeInfo::new(ROOT_ID)),
            tree_id: TreeId::ROOT,
            focus: ROOT_ID,
        }
    }

    /// gpui 0.2.2 pulls windows 0.61 while accesskit_windows uses windows 0.62,
    /// so the HWND types differ. Bridge through the raw pointer value.
    fn hwnd_of(window: &Window) -> HWND {
        let handle = HasWindowHandle::window_handle(window)
            .expect("gpui window has no native window handle");
        match handle.as_raw() {
            RawWindowHandle::Win32(h) => HWND(h.hwnd.get() as *mut c_void),
            other => panic!("expected a Win32 window handle, got {other:?}"),
        }
    }

    struct ProbeView {
        adapter: Option<SubclassingAdapter>,
    }

    impl Render for ProbeView {
        fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
            div().size_full().child("SR0-D probe")
        }
    }

    pub fn run() {
        Application::new().run(|cx: &mut App| {
            let bounds = Bounds::centered(None, size(px(640.), px(480.)), cx);
            let handle = cx
                .open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(bounds)),
                        // The accesskit subclassing adapter must exist before the window is shown.
                        show: false,
                        ..Default::default()
                    },
                    |_, cx| cx.new(|_| ProbeView { adapter: None }),
                )
                .expect("open_window failed");

            handle
                .update(cx, |view, window, _cx| {
                    let hwnd = hwnd_of(window);
                    view.adapter = Some(SubclassingAdapter::new(hwnd, Activation, Actions));
                    window.activate_window();
                })
                .expect("attaching accesskit adapter failed");

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
    eprintln!("sr0d-render-composition is a Windows-only probe");
    std::process::exit(2);
}
