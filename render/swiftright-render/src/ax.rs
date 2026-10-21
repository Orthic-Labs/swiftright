//! AccessKit publication. One `SubclassingAdapter` per HWND (created in view.rs). The
//! tree is built from plain, Send data (`AxShared`) that commit stores; the action
//! handler only validates, enqueues a generation/node/snapshot record and wakes the UI
//! loop. It never calls the host or GPUI and may run on any thread.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use accesskit::{
    Action, ActionData, ActionHandler, ActionRequest, ActivationHandler, Node, NodeId, Orientation, Rect, Role,
    TextDirection, TextPosition, TextSelection, Toggled, TreeId, TreeInfo, TreeUpdate,
};

use crate::abi::*;
use crate::rt::*;

/// One AX text run. The data of a run (text and the per-character arrays) is immutable and shared (`Arc`): a node that only
/// moved (scrolling) is committed with new bounds and the same character data, and its conversion allocates nothing for it.
#[derive(Clone)]
pub struct AxRun {
    pub id: u64,
    pub text: Arc<str>,
    pub lengths: Arc<[u8]>,
    pub positions: Arc<[f32]>,
    pub widths: Arc<[f32]>,
    pub word_starts: Arc<[u8]>,
    pub bounds: [f32; 4],
}

/// Rev 0.13: the accessibility extras of one node (hint, value, description, header and link traits). Immutable and shared.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AxExtras {
    pub help: Arc<str>,
    pub value: Arc<str>,
    pub description: Arc<str>,
    pub header: bool,
    pub link: bool,
    /// 0 = unset (2 for a heading); 1..=6.
    pub heading_level: u8,
}

/// The heading level published when a header has none set. macOS AX reports a SwiftUI header with an unknown level.
pub const DEFAULT_HEADING_LEVEL: u8 = 2;

#[derive(Clone)]
pub struct AxNode {
    pub id: u64,
    pub parent: u64,
    pub role: u32,
    pub actions: u32,
    pub flags: u32,
    pub toggled: u32,
    pub range: Option<[f64; 5]>,
    pub label: Arc<str>,
    pub value: Arc<str>,
    pub identifier: Arc<str>,
    pub bounds: [f32; 4],
    pub runs: Arc<Vec<AxRun>>,
    pub sel: Option<(u64, u32, u64, u32)>,
    /// Rev 0.13; None when the transaction carried no entry for the node.
    pub extras: Option<Arc<AxExtras>>,
}

#[derive(Clone)]
pub struct AxShared {
    pub window: u64,
    pub version: u64,
    pub title: String,
    pub focus: u64,
    pub nodes: Vec<AxNode>,
}

pub static AX: Mutex<AxShared> = Mutex::new(AxShared {
    window: 0,
    version: 0,
    title: String::new(),
    focus: 0,
    nodes: Vec::new(),
});

pub fn lock_ax() -> std::sync::MutexGuard<'static, AxShared> {
    AX.lock().unwrap_or_else(|e| e.into_inner())
}

const ROOT_ID: NodeId = NodeId(0);

fn rect(b: &[f32; 4]) -> Rect {
    Rect {
        x0: b[0] as f64,
        y0: b[1] as f64,
        x1: (b[0] + b[2]) as f64,
        y1: (b[1] + b[3]) as f64,
    }
}

/// The AccessKit role of a node after its traits (rev 0.13). `isLink` turns a static text, group, generic container or button
/// into Role::Link (UIA Hyperlink; a button keeps its Click action); `isHeader` turns a static text or group into Role::Heading.
/// Any other role keeps its own: a header trait on a text field or a slider changes nothing.
pub fn effective_role(base: Role, x: Option<&AxExtras>) -> Role {
    let Some(x) = x else { return base };
    match base {
        Role::Label | Role::Group | Role::GenericContainer | Role::Button if x.link => Role::Link,
        Role::Label | Role::Group | Role::GenericContainer if x.header => Role::Heading,
        _ => base,
    }
}

pub fn build_tree() -> TreeUpdate {
    let s = lock_ax().clone();
    build_tree_from(&s)
}

pub fn build_tree_from(s: &AxShared) -> TreeUpdate {
    let mut nodes: Vec<(NodeId, Node)> = Vec::new();

    let mut root = Node::new(Role::Window);
    root.set_label(s.title.clone());
    // Children by parent, in snapshot (paint) order: one pass instead of a scan per node.
    let mut kids: HashMap<u64, Vec<NodeId>> = HashMap::new();
    for n in &s.nodes {
        kids.entry(n.parent).or_default().push(NodeId(n.id));
    }
    root.set_children(kids.remove(&0).unwrap_or_default());
    nodes.push((ROOT_ID, root));

    for n in &s.nodes {
        let role = match n.role {
            ROLE_BUTTON => Role::Button,
            ROLE_STATIC_TEXT => Role::Label,
            ROLE_TEXT_FIELD => {
                if n.flags & SEM_MULTILINE != 0 {
                    Role::MultilineTextInput
                } else {
                    Role::TextInput
                }
            }
            ROLE_LIST => Role::List,
            ROLE_LIST_ITEM => Role::ListItem,
            ROLE_GROUP => Role::Group,
            // Rev 0.6. accesskit 0.25.1 lib.rs Role::{CheckBox, Switch, Image, Menu, MenuItem,
            // AlertDialog, Dialog}; UIA control types: accesskit_windows 0.35.1 node.rs
            // control_type() (CheckBox, Button, Image, Menu, MenuItem, Window, Window).
            ROLE_CHECKBOX => Role::CheckBox,
            ROLE_SWITCH => Role::Switch,
            ROLE_IMAGE => Role::Image,
            ROLE_MENU => Role::Menu,
            ROLE_MENU_ITEM => Role::MenuItem,
            ROLE_ALERT => Role::AlertDialog,
            ROLE_DIALOG => Role::Dialog,
            // Rev 0.9. accesskit Role::Slider -> UIA Slider; with a numeric value accesskit_windows publishes RangeValuePattern.
            ROLE_SLIDER => Role::Slider,
            // Rev 0.11 (issue #31). Role::ScrollBar -> UIA ScrollBar (accesskit_windows 0.35.1 node.rs control_type); the range entry
            // (value 0..1) gives it the RangeValue pattern (is_range_value_pattern_supported = numeric_value is some).
            ROLE_SCROLL_BAR => Role::ScrollBar,
            ROLE_LINK => Role::Link,
            _ => Role::GenericContainer,
        };
        let x = n.extras.as_deref();
        let role = effective_role(role, x);
        let mut node = Node::new(role);
        // A static text publishes its text as its VALUE, and accesskit_consumer `label_comes_from_value` (Role::Label only) makes the
        // value the UIA Name. A static text promoted to Heading or Link has no such rule, so its text must be its label.
        let promoted = n.role == ROLE_STATIC_TEXT && role != Role::Label;
        if !n.label.is_empty() {
            node.set_label(n.label.to_string());
        } else if promoted && !n.value.is_empty() {
            node.set_label(n.value.to_string());
        }
        if promoted {
            if let Some(v) = x.map(|x| &x.value).filter(|v| !v.is_empty()) {
                node.set_value(v.to_string());
            }
        } else if n.role == ROLE_STATIC_TEXT {
            // accesskit_consumer node.rs `label_comes_from_value` is true for Role::Label, and
            // accesskit_windows `name()` then writes the VALUE as UIA Name. The bridge's text
            // is the label, so a static text without a value publishes its label as the value.
            node.set_value(if n.value.is_empty() { n.label.to_string() } else { n.value.to_string() });
        } else if let Some(v) = x.map(|x| &x.value).filter(|v| !v.is_empty() && n.role != ROLE_TEXT_FIELD) {
            // Rev 0.13: an accessibilityValue on any other element is its UIA Value (the node's own value is replaced; a text
            // field's value is its text and stays).
            node.set_value(v.to_string());
        } else if !n.value.is_empty() || n.role == ROLE_TEXT_FIELD {
            node.set_value(n.value.to_string());
        }
        if let Some(x) = x {
            // Rev 0.13. accesskit_windows 0.35.1 node.rs: UIA HelpText = `placeholder`, UIA FullDescription = `description`,
            // UIA Level = `level` + 1 (accesskit's level is zero-based). The hint goes to HelpText and, when no description is
            // given, FullDescription too. A Role::Label cannot hold a value apart from its name, so a value given to a static
            // text is appended to the description instead of renaming the element.
            if !x.help.is_empty() {
                node.set_placeholder(x.help.to_string());
            }
            let mut desc: Vec<&str> = Vec::new();
            if !x.description.is_empty() {
                desc.push(&x.description);
            } else if !x.help.is_empty() {
                desc.push(&x.help);
            }
            if role == Role::Label && !x.value.is_empty() {
                desc.push(&x.value);
            }
            if !desc.is_empty() {
                node.set_description(desc.join(", "));
            }
            if role == Role::Heading {
                let level = if x.heading_level == 0 { DEFAULT_HEADING_LEVEL } else { x.heading_level };
                node.set_level(level as usize - 1);
            }
        }
        if !n.identifier.is_empty() {
            // AccessKit author id -> UIA AutomationId (accesskit_windows node.rs automation_id).
            node.set_author_id(n.identifier.to_string());
        }
        if n.actions & ACT_INVOKE != 0 {
            node.add_action(Action::Click);
        }
        if n.actions & ACT_FOCUS != 0 {
            node.add_action(Action::Focus);
        }
        if n.actions & ACT_SET_VALUE != 0 {
            node.add_action(Action::SetValue);
        }
        if n.actions & ACT_SET_SELECTION != 0 {
            node.add_action(Action::SetTextSelection);
        }
        // Rev 0.6 state. Toggled -> UIA TogglePattern (node.rs is_toggle_pattern_supported /
        // toggle_state); selected -> UIA SelectionItemPattern for list items (node.rs
        // is_selection_item_pattern_supported needs `selected` to be Some); disabled -> UIA
        // IsEnabled (node.rs is_enabled) and refused Invoke/Toggle/Select (node.rs do_action).
        match n.toggled {
            TOGGLED_OFF => node.set_toggled(Toggled::False),
            TOGGLED_ON => node.set_toggled(Toggled::True),
            TOGGLED_MIXED => node.set_toggled(Toggled::Mixed),
            _ => {}
        }
        if let Some([value, min, max, step, jump]) = n.range {
            // UIA RangeValue: Value, Minimum, Maximum, SmallChange (step), LargeChange (jump).
            node.set_numeric_value(value);
            node.set_min_numeric_value(min);
            node.set_max_numeric_value(max);
            node.set_numeric_value_step(step);
            node.set_numeric_value_jump(jump);
        }
        if n.role == ROLE_SCROLL_BAR {
            node.set_orientation(Orientation::Vertical);
        }
        if n.flags & SEM_SELECTABLE != 0 {
            node.set_selected(n.flags & SEM_SELECTED != 0);
        }
        if n.flags & SEM_DISABLED != 0 {
            node.set_disabled();
        }
        node.set_bounds(rect(&n.bounds));
        let mut children: Vec<NodeId> = kids.remove(&n.id).unwrap_or_default();
        children.extend(n.runs.iter().map(|r| NodeId(r.id)));
        node.set_children(children);
        if let Some((ar, ac, fr, fc)) = n.sel {
            node.set_text_selection(TextSelection {
                anchor: TextPosition { node: NodeId(ar), character_index: ac as usize },
                focus: TextPosition { node: NodeId(fr), character_index: fc as usize },
            });
        }
        nodes.push((NodeId(n.id), node));

        for r in n.runs.iter() {
            let mut run = Node::new(Role::TextRun);
            run.set_value(r.text.to_string());
            run.set_text_direction(TextDirection::LeftToRight);
            run.set_character_lengths(r.lengths.to_vec());
            run.set_character_positions(r.positions.to_vec());
            run.set_character_widths(r.widths.to_vec());
            run.set_word_starts(r.word_starts.to_vec());
            run.set_bounds(rect(&r.bounds));
            nodes.push((NodeId(r.id), run));
        }
    }

    let focus = if s.focus != 0 && s.nodes.iter().any(|n| n.id == s.focus) {
        NodeId(s.focus)
    } else {
        ROOT_ID
    };
    TreeUpdate {
        nodes,
        tree: Some(TreeInfo::new(ROOT_ID)),
        tree_id: TreeId::ROOT,
        focus,
    }
}

pub struct Activation;

impl ActivationHandler for Activation {
    fn request_initial_tree(&mut self) -> Option<TreeUpdate> {
        Some(build_tree())
    }
}

/// Must be Send. Validates against the live snapshot, enqueues, wakes the UI loop.
pub struct Actions;

impl ActionHandler for Actions {
    fn do_action(&mut self, request: ActionRequest) {
        let target = request.target_node.0;
        // Resolve under the AX lock, push after releasing it.
        let resolved = {
            let s = lock_ax();
            if s.window == 0 {
                None
            } else {
                let mut found = None;
                for n in &s.nodes {
                    if n.id == target {
                        // Rev 0.6: a disabled node accepts no action.
                        let actions = if n.flags & SEM_DISABLED != 0 { 0 } else { n.actions };
                        found = Some((n.id, actions, None::<usize>, s.window, s.version));
                        break;
                    }
                    let mut base = 0usize;
                    for r in n.runs.iter() {
                        if r.id == target {
                            let actions = if n.flags & SEM_DISABLED != 0 { 0 } else { n.actions };
                            found = Some((n.id, actions, Some(base), s.window, s.version));
                            break;
                        }
                        base += r.lengths.len();
                    }
                    if found.is_some() {
                        break;
                    }
                }
                found
            }
        };
        let Some((node, actions, _run_base, window, version)) = resolved else {
            bump(S_AX_REJ);
            return;
        };
        let mut ev = Event::new(EV_AX_ACTION, 0);
        ev.window = window;
        ev.node = node;
        ev.snapshot = version;
        match (&request.action, &request.data) {
            (Action::Click, _) if actions & ACT_INVOKE != 0 => ev.action = AX_INVOKE,
            (Action::Focus, _) if actions & ACT_FOCUS != 0 => ev.action = AX_FOCUS,
            (Action::SetValue, Some(ActionData::Value(v))) if actions & ACT_SET_VALUE != 0 => {
                ev.action = AX_SET_VALUE;
                let b = v.as_bytes();
                let mut n = b.len().min(EVENT_TEXT_CAP - 1);
                while n > 0 && std::str::from_utf8(&b[..n]).is_err() {
                    n -= 1;
                }
                ev.text_len = copy_text(&mut ev.text, 0, &b[..n]) as u32;
                ev.i0 = (n < b.len()) as i32;
            }
            (Action::SetTextSelection, Some(ActionData::SetTextSelection(sel)))
                if actions & ACT_SET_SELECTION != 0 =>
            {
                ev.action = AX_SET_SELECTION;
                ev.i0 = global_char(node, sel.anchor.node.0, sel.anchor.character_index) as i32;
                ev.i1 = global_char(node, sel.focus.node.0, sel.focus.character_index) as i32;
            }
            _ => {
                bump(S_AX_REJ);
                return;
            }
        }
        if push_event(ev) {
            bump(S_AX_ENQ);
        } else {
            bump(S_AX_REJ);
        }
    }
}

/// Character index within the owning node's value for (run node id, index in run).
fn global_char(node: u64, run_id: u64, idx: usize) -> usize {
    let s = lock_ax();
    let Some(n) = s.nodes.iter().find(|n| n.id == node) else { return 0 };
    let mut base = 0usize;
    for r in n.runs.iter() {
        if r.id == run_id {
            return base + idx.min(r.lengths.len());
        }
        base += r.lengths.len();
    }
    0
}

#[cfg(test)]
mod extras_tests {
    use super::*;

    fn node(id: u64, role: u32, label: &str, value: &str, extras: Option<AxExtras>) -> AxNode {
        AxNode {
            id,
            parent: 0,
            role,
            actions: 0,
            flags: 0,
            toggled: 0,
            range: None,
            label: Arc::from(label),
            value: Arc::from(value),
            identifier: Arc::from(""),
            bounds: [0.0, 0.0, 10.0, 10.0],
            runs: Arc::new(Vec::new()),
            sel: None,
            extras: extras.map(Arc::new),
        }
    }

    fn build(nodes: Vec<AxNode>) -> HashMap<u64, Node> {
        let s = AxShared { window: 1, version: 1, title: "t".into(), focus: 0, nodes };
        build_tree_from(&s).nodes.into_iter().map(|(id, n)| (id.0, n)).collect()
    }

    fn x() -> AxExtras {
        AxExtras::default()
    }

    #[test]
    fn absent_extras_keep_the_existing_mapping() {
        let t = build(vec![node(1, ROLE_STATIC_TEXT, "Hello", "", None), node(2, ROLE_BUTTON, "Go", "", None)]);
        let a = &t[&1];
        assert_eq!(a.role(), Role::Label);
        assert_eq!(a.value(), Some("Hello"));
        assert_eq!(a.description(), None);
        assert_eq!(a.placeholder(), None);
        assert_eq!(a.level(), None);
        assert_eq!(t[&2].role(), Role::Button);
    }

    #[test]
    fn hint_is_help_text_and_full_description() {
        let t = build(vec![node(2, ROLE_BUTTON, "Scan", "", Some(AxExtras { help: Arc::from("Starts the scan"), ..x() }))]);
        let b = &t[&2];
        assert_eq!(b.role(), Role::Button);
        assert_eq!(b.placeholder(), Some("Starts the scan"));
        assert_eq!(b.description(), Some("Starts the scan"));
        // An explicit description wins for FullDescription; the hint stays HelpText.
        let t = build(vec![node(2, ROLE_BUTTON, "Scan", "", Some(AxExtras { help: Arc::from("h"), description: Arc::from("d"), ..x() }))]);
        assert_eq!(t[&2].placeholder(), Some("h"));
        assert_eq!(t[&2].description(), Some("d"));
    }

    #[test]
    fn header_is_a_heading_named_by_its_label_with_level_two_by_default() {
        let t = build(vec![
            node(1, ROLE_STATIC_TEXT, "Settings", "", Some(AxExtras { header: true, ..x() })),
            node(2, ROLE_STATIC_TEXT, "Sub", "Sub", Some(AxExtras { header: true, heading_level: 3, ..x() })),
        ]);
        let h = &t[&1];
        assert_eq!(h.role(), Role::Heading);
        assert_eq!(h.label(), Some("Settings"));
        assert_eq!(h.value(), None, "a heading has no Value pattern of its own");
        assert_eq!(h.level(), Some(1), "zero-based: UIA Level 2");
        assert_eq!(t[&2].level(), Some(2), "UIA Level 3");
        // A text carried only in `value` still names the heading.
        let t = build(vec![node(1, ROLE_STATIC_TEXT, "", "Only value", Some(AxExtras { header: true, ..x() }))]);
        assert_eq!(t[&1].label(), Some("Only value"));
    }

    #[test]
    fn link_trait_is_a_hyperlink_and_a_button_keeps_its_click() {
        let t = build(vec![
            node(1, ROLE_STATIC_TEXT, "Docs", "", Some(AxExtras { link: true, ..x() })),
            node(2, ROLE_BUTTON, "Open", "", Some(AxExtras { link: true, ..x() })),
        ]);
        assert_eq!(t[&1].role(), Role::Link);
        assert_eq!(t[&1].label(), Some("Docs"));
        assert_eq!(t[&2].role(), Role::Link);
        // Link wins over header; other roles ignore both traits.
        assert_eq!(effective_role(Role::Label, Some(&AxExtras { link: true, header: true, ..x() })), Role::Link);
        assert_eq!(effective_role(Role::TextInput, Some(&AxExtras { header: true, link: true, ..x() })), Role::TextInput);
        assert_eq!(effective_role(Role::Slider, Some(&AxExtras { header: true, ..x() })), Role::Slider);
    }

    #[test]
    fn value_is_a_value_pattern_except_on_a_static_text() {
        let t = build(vec![
            node(1, ROLE_GROUP, "Volume", "", Some(AxExtras { value: Arc::from("40 percent"), ..x() })),
            node(2, ROLE_STATIC_TEXT, "Memory", "", Some(AxExtras { value: Arc::from("1.2 GB"), ..x() })),
        ]);
        assert_eq!(t[&1].value(), Some("40 percent"));
        // The static text keeps its name (its value is the name); the extra value is appended to the description.
        assert_eq!(t[&2].role(), Role::Label);
        assert_eq!(t[&2].value(), Some("Memory"));
        assert_eq!(t[&2].description(), Some("1.2 GB"));
    }
}

#[cfg(test)]
mod render_scale_tests {
    use super::rect;
    use crate::scale;

    /// UIA bounding rectangles are the host's physical-pixel rectangles, converted by nothing: the window's client area is
    /// `dip * S` px (scale.rs), the host lays out on that grid, and accesskit_windows maps client px to screen px. So the bounds
    /// follow the render scale through the host's layout and no GPUI scale (G) enters this path.
    #[test]
    fn uia_bounds_are_the_host_physical_rectangle_at_any_scale() {
        // A 100 x 50 DIP control at (10, 20) DIP, laid out by a host at S = 2.5, is (25, 50, 250, 125) px.
        let s = 2.5f32;
        let b = [10.0 * s, 20.0 * s, 100.0 * s, 50.0 * s];
        let r = rect(&b);
        assert_eq!((r.x0, r.y0, r.x1, r.y1), (25.0, 50.0, 275.0, 175.0));
        // The same rectangle on a different display scale is the same numbers: nothing here reads a DPI.
        assert_eq!((rect(&b).x0, rect(&b).x1), (r.x0, r.x1));
        // The window that rectangle lives in is `dip * S` px wide on every display.
        assert_eq!(scale::physical_px(320, s), 800);
    }
}
