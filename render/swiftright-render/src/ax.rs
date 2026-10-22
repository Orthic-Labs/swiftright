//! AccessKit publication. One `SubclassingAdapter` per HWND (created in view.rs). The
//! tree is built from plain, Send data (`AxShared`) that commit stores; the action
//! handler only validates, enqueues a generation/node/snapshot record and wakes the UI
//! loop. It never calls the host or GPUI and may run on any thread.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use accesskit::{
    Action, ActionData, ActionHandler, ActionRequest, ActivationHandler, Live, Node, NodeId, Orientation, Rect, Role,
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

// ---- #45 step 5: the open IME candidate list (own popup, UI-less TSF mode) as UIA nodes.
// Reserved node ids: the top 4096 values of the u64 space, `CAND_ID_BASE ..= u64::MAX`. Host node and run ids are small
// counters/handles handed out by the Swift host, so they never reach this range; `cand_overlay_fits` additionally drops the
// overlay when a host id does, so a collision cannot corrupt the tree.
//   CAND_ID_BASE      the ListBox "Candidates"
//   CAND_ID_BASE + 1  the polite live label ("<candidate>, i of n")
//   CAND_ID_BASE + 16 + row   the ListBoxOption of page row `row` (at most CAND_MAX_ROWS rows)
pub const CAND_ID_BASE: u64 = u64::MAX - 0xFFF;
const CAND_LIST_ID: NodeId = NodeId(CAND_ID_BASE);
const CAND_LIVE_ID: NodeId = NodeId(CAND_ID_BASE + 1);
const CAND_OPTION_BASE: u64 = CAND_ID_BASE + 16;
pub const CAND_MAX_ROWS: usize = 64;

/// The candidate list as the popup shows it: the IME state plus the popup row rectangles, `[x, y, w, h]` in window-client physical px
/// (the coordinates of every other node's bounds), one per row of the current page.
#[derive(Clone, Debug, PartialEq)]
pub struct AxCand {
    pub state: crate::cand::CandState,
    pub rows: Vec<[f32; 4]>,
}

/// Published by view.rs `cand_refresh` / `cand_hide` (UI thread); read by `build_tree` on whichever thread UIA activates it, so it is
/// a static and not a thread local.
static CAND: Mutex<Option<AxCand>> = Mutex::new(None);

/// Stores the new candidate list (None = closed). True when it differs from the stored one (a tree update is then due).
pub fn set_cand(c: Option<AxCand>) -> bool {
    let mut g = CAND.lock().unwrap_or_else(|e| e.into_inner());
    if *g == c {
        return false;
    }
    *g = c;
    true
}

/// The stored popup row rectangles as `(x, y, w, h)` window-client px; None while no list is shown.
pub fn cand_rows() -> Option<Vec<(f64, f64, f64, f64)>> {
    let g = CAND.lock().unwrap_or_else(|e| e.into_inner());
    g.as_ref().map(|c| c.rows.iter().map(|r| (r[0] as f64, r[1] as f64, r[2] as f64, r[3] as f64)).collect())
}

fn cand_overlay_fits(s: &AxShared) -> bool {
    !s.nodes.iter().any(|n| n.id >= CAND_ID_BASE || n.runs.iter().any(|r| r.id >= CAND_ID_BASE))
}

/// "<candidate>, i of n" for the selected row (absolute index + 1 of the total); empty when the selection is not on this page.
pub fn cand_live_text(c: &AxCand) -> String {
    let st = &c.state;
    match st.selected_row() {
        Some(r) => format!("{}, {} of {}", st.strings[r], st.selection + 1, cand_total(st)),
        None => String::new(),
    }
}

fn cand_total(st: &crate::cand::CandState) -> usize {
    (st.count as usize).max(st.first_on_page() + st.rows()).max(st.selection + 1)
}

fn cand_nodes(c: &AxCand, nodes: &mut Vec<(NodeId, Node)>) {
    let st = &c.state;
    let first = st.first_on_page();
    let total = cand_total(st);
    let sel = st.selected_row();
    let rows = st.rows().min(CAND_MAX_ROWS);
    let mut list = Node::new(Role::ListBox);
    list.set_label("Candidates".to_string());
    let mut children: Vec<NodeId> = Vec::with_capacity(rows + 1);
    let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
    for i in 0..rows {
        let id = NodeId(CAND_OPTION_BASE + i as u64);
        let mut o = Node::new(Role::ListBoxOption);
        o.set_label(format!("{} {} of {}", st.strings[i], first + i + 1, total));
        o.set_selected(sel == Some(i));
        if let Some(b) = c.rows.get(i) {
            let r = rect(b);
            o.set_bounds(r);
            x0 = x0.min(r.x0);
            y0 = y0.min(r.y0);
            x1 = x1.max(r.x1);
            y1 = y1.max(r.y1);
        }
        children.push(id);
        nodes.push((id, o));
    }
    if x0 <= x1 && y0 <= y1 {
        list.set_bounds(Rect { x0, y0, x1, y1 });
    }
    // Fallback announcement: a polite live label whose text changes with the selection (UIA LiveRegionChanged).
    let mut live = Node::new(Role::Label);
    live.set_live(Live::Polite);
    live.set_value(cand_live_text(c));
    children.push(CAND_LIVE_ID);
    nodes.push((CAND_LIVE_ID, live));
    list.set_children(children);
    nodes.push((CAND_LIST_ID, list));
}

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
    let cand = CAND.lock().unwrap_or_else(|e| e.into_inner()).clone();
    build_tree_with(&s, cand.as_ref())
}

pub fn build_tree_from(s: &AxShared) -> TreeUpdate {
    build_tree_with(s, None)
}

/// `cand` = the open candidate list (None = none); it becomes a ListBox child of the focused node (the root when the focus is
/// not a published node). Focus stays where the snapshot has it.
pub fn build_tree_with(s: &AxShared, cand: Option<&AxCand>) -> TreeUpdate {
    let mut nodes: Vec<(NodeId, Node)> = Vec::new();
    let cand = cand.filter(|c| c.state.rows() > 0 && cand_overlay_fits(s));

    let mut root = Node::new(Role::Window);
    root.set_label(s.title.clone());
    // Children by parent, in snapshot (paint) order: one pass instead of a scan per node.
    let mut kids: HashMap<u64, Vec<NodeId>> = HashMap::new();
    for n in &s.nodes {
        kids.entry(n.parent).or_default().push(NodeId(n.id));
    }
    if cand.is_some() {
        let host = if s.focus != 0 && s.nodes.iter().any(|n| n.id == s.focus) { s.focus } else { 0 };
        kids.entry(host).or_default().push(CAND_LIST_ID);
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
            // Rev 0.13. accesskit_windows 0.35.1 node.rs: UIA HelpText = `placeholder`, UIA FullDescription (30159) = `description`,
            // UIA Level (30154) = `level` + 1 (accesskit's level is zero-based). accesskit_consumer `placeholder()` is filtered to an
            // empty text input, so HelpText is empty on any other node: the hint reaches UIA as FullDescription (and as HelpText
            // only on an empty text field). A Role::Label cannot hold a value apart from its name, so a value given to a static
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

    if let Some(c) = cand {
        cand_nodes(c, &mut nodes);
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
mod cand_tests {
    use super::*;
    use crate::cand::CandState;

    fn host(id: u64, role: u32) -> AxNode {
        AxNode {
            id,
            parent: 0,
            role,
            actions: 0,
            flags: 0,
            toggled: 0,
            range: None,
            label: Arc::from(""),
            value: Arc::from(""),
            identifier: Arc::from(""),
            bounds: [0.0, 0.0, 100.0, 20.0],
            runs: Arc::new(Vec::new()),
            sel: None,
            extras: None,
        }
    }

    fn shared(nodes: Vec<AxNode>) -> AxShared {
        AxShared { window: 1, version: 1, title: "t".into(), focus: 7, nodes }
    }

    fn cand() -> AxCand {
        AxCand {
            state: CandState {
                strings: vec!["\u{4F60}".into(), "\u{59B3}".into(), "\u{5C3C}".into()],
                selection: 11,
                page: 1,
                page_starts: vec![0, 9],
                count: 14,
                show_numbers: true,
            },
            rows: vec![[10.0, 30.0, 80.0, 24.0], [10.0, 54.0, 80.0, 24.0], [10.0, 78.0, 80.0, 24.0]],
        }
    }

    fn tree(c: Option<&AxCand>) -> (HashMap<u64, Node>, TreeUpdate) {
        let u = build_tree_with(&shared(vec![host(7, ROLE_TEXT_FIELD)]), c);
        (u.nodes.iter().map(|(i, n)| (i.0, n.clone())).collect(), u)
    }

    #[test]
    fn open_list_is_a_listbox_of_options_under_the_focused_field() {
        let c = cand();
        let (t, u) = tree(Some(&c));
        let list = &t[&CAND_ID_BASE];
        assert_eq!(list.role(), Role::ListBox);
        assert_eq!(list.label(), Some("Candidates"));
        assert!(t[&7].children().contains(&CAND_LIST_ID), "the list hangs off the edit node");
        assert_eq!(u.focus, NodeId(7), "focus stays on the edit node");
        let opts: Vec<&Node> = (0..3).map(|i| &t[&(CAND_ID_BASE + 16 + i)]).collect();
        assert!(opts.iter().all(|o| o.role() == Role::ListBoxOption));
        assert_eq!(opts.iter().filter(|o| o.is_selected() == Some(true)).count(), 1);
        assert_eq!(opts[2].is_selected(), Some(true), "selection 11 = page 1 row 2");
        assert_eq!(opts[0].is_selected(), Some(false));
        assert_eq!(opts[0].label(), Some("\u{4F60} 10 of 14"));
        assert_eq!(opts[2].label(), Some("\u{5C3C} 12 of 14"));
        let b = opts[1].bounds().unwrap();
        assert_eq!((b.x0, b.y0, b.x1, b.y1), (10.0, 54.0, 90.0, 78.0));
        let lb = list.bounds().unwrap();
        assert_eq!((lb.x0, lb.y0, lb.x1, lb.y1), (10.0, 30.0, 90.0, 102.0));
    }

    #[test]
    fn live_label_follows_the_selection() {
        let mut c = cand();
        let (t, _) = tree(Some(&c));
        let live = &t[&(CAND_ID_BASE + 1)];
        assert_eq!(live.live(), Some(Live::Polite));
        assert_eq!(live.value(), Some("\u{5C3C}, 12 of 14"));
        assert!(t[&CAND_ID_BASE].children().contains(&CAND_LIVE_ID));
        c.state.selection = 9;
        let (t, _) = tree(Some(&c));
        assert_eq!(t[&(CAND_ID_BASE + 1)].value(), Some("\u{4F60}, 10 of 14"));
    }

    #[test]
    fn closed_or_empty_list_adds_nothing() {
        let (t, _) = tree(None);
        assert!(t.keys().all(|k| *k < CAND_ID_BASE));
        assert!(!t[&7].children().contains(&CAND_LIST_ID));
        let mut c = cand();
        c.state.strings.clear();
        let (t, _) = tree(Some(&c));
        assert!(t.keys().all(|k| *k < CAND_ID_BASE));
    }

    #[test]
    fn host_id_in_the_reserved_range_drops_the_overlay() {
        let s = shared(vec![host(7, ROLE_TEXT_FIELD), host(CAND_ID_BASE + 3, ROLE_GROUP)]);
        let u = build_tree_with(&s, Some(&cand()));
        assert_eq!(u.nodes.iter().filter(|(i, _)| i.0 >= CAND_ID_BASE).count(), 1);
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
