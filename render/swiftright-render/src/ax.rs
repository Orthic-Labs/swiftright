//! AccessKit publication. One `SubclassingAdapter` per HWND (created in view.rs). The
//! tree is built from plain, Send data (`AxShared`) that commit stores; the action
//! handler only validates, enqueues a generation/node/snapshot record and wakes the UI
//! loop. It never calls the host or GPUI and may run on any thread.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use accesskit::{
    Action, ActionData, ActionHandler, ActionRequest, ActivationHandler, Node, NodeId, Rect, Role,
    TextDirection, TextPosition, TextSelection, Toggled, TreeId, TreeInfo, TreeUpdate,
};

use crate::abi::*;
use crate::rt::*;

#[derive(Clone)]
pub struct AxRun {
    pub id: u64,
    pub text: String,
    pub lengths: Vec<u8>,
    pub positions: Vec<f32>,
    pub widths: Vec<f32>,
    pub word_starts: Vec<u8>,
    pub bounds: [f32; 4],
}

#[derive(Clone)]
pub struct AxNode {
    pub id: u64,
    pub parent: u64,
    pub role: u32,
    pub actions: u32,
    pub flags: u32,
    pub toggled: u32,
    pub label: Arc<str>,
    pub value: Arc<str>,
    pub identifier: Arc<str>,
    pub bounds: [f32; 4],
    pub runs: Arc<Vec<AxRun>>,
    pub sel: Option<(u64, u32, u64, u32)>,
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

pub fn build_tree() -> TreeUpdate {
    let s = lock_ax().clone();
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
            _ => Role::GenericContainer,
        };
        let mut node = Node::new(role);
        if !n.label.is_empty() {
            node.set_label(n.label.to_string());
        }
        if n.role == ROLE_STATIC_TEXT {
            // accesskit_consumer node.rs `label_comes_from_value` is true for Role::Label, and
            // accesskit_windows `name()` then writes the VALUE as UIA Name. The bridge's text
            // is the label, so a static text without a value publishes its label as the value.
            node.set_value(if n.value.is_empty() { n.label.to_string() } else { n.value.to_string() });
        } else if !n.value.is_empty() || n.role == ROLE_TEXT_FIELD {
            node.set_value(n.value.to_string());
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
            run.set_value(r.text.clone());
            run.set_text_direction(TextDirection::LeftToRight);
            run.set_character_lengths(r.lengths.clone());
            run.set_character_positions(r.positions.clone());
            run.set_character_widths(r.widths.clone());
            run.set_word_starts(r.word_starts.clone());
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
