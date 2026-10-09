//! The retained snapshot: node table, primitives, semantics. `commit` validates a
//! transaction completely, then applies it; painting, hit-testing and the AccessKit
//! data all derive from the resulting snapshot. UI thread only; never calls the host.

use std::collections::{HashMap, HashSet};
use std::ffi::c_char;
use std::sync::Arc;

use crate::abi::*;
use crate::ax::{AxNode, AxRun, AxShared};
use crate::text::{Measured, RunSlab};

#[derive(Clone)]
pub enum Prim {
    Rect { r: [f32; 4], color: u32, border_color: u32, border_w: f32, radius: f32 },
    Text { x: f32, y: f32, run: Arc<Measured> },
    ClipPush([f32; 4]),
    ClipPop,
    TranslatePush(f32, f32),
    TranslatePop,
}

#[derive(Clone)]
pub struct SemRun {
    pub id: u64,
    pub text: String,
    pub lengths: Vec<u8>,
    pub positions: Vec<f32>,
    pub widths: Vec<f32>,
    pub word_starts: Vec<u8>,
    pub bounds: [f32; 4],
}

#[derive(Clone)]
pub struct Sem {
    pub role: u32,
    pub actions: u32,
    pub flags: u32,
    pub label: String,
    pub value: String,
    pub identifier: String,
    pub runs: Vec<SemRun>,
    pub sel: Option<(u64, u32, u64, u32)>,
}

#[derive(Clone)]
pub struct PNode {
    pub id: u64,
    pub parent: u64,
    pub order: u32,
    pub flags: u32,
    pub bounds: [f32; 4],
    pub prims: Vec<Prim>,
    pub sem: Option<Sem>,
}

#[derive(Default)]
pub struct Tree {
    pub nodes: HashMap<u64, PNode>,
    /// Paint order: depth-first, siblings by (order, id).
    pub order: Vec<u64>,
    pub version: u64,
    pub focus: u64,
}

impl Tree {
    pub fn clear(&mut self) {
        self.nodes.clear();
        self.order.clear();
        self.focus = 0;
    }

    /// Topmost hit-target node containing the physical point.
    pub fn hit(&self, x: f32, y: f32) -> u64 {
        for id in self.order.iter().rev() {
            if let Some(n) = self.nodes.get(id) {
                if n.flags & NODE_HIT_TARGET != 0
                    && x >= n.bounds[0]
                    && y >= n.bounds[1]
                    && x < n.bounds[0] + n.bounds[2]
                    && y < n.bounds[1] + n.bounds[3]
                {
                    return *id;
                }
            }
        }
        0
    }
}

fn dfs_order(nodes: &HashMap<u64, PNode>) -> Vec<u64> {
    let mut kids: HashMap<u64, Vec<(u32, u64)>> = HashMap::new();
    for n in nodes.values() {
        kids.entry(n.parent).or_default().push((n.order, n.id));
    }
    for v in kids.values_mut() {
        v.sort();
    }
    let mut out = Vec::with_capacity(nodes.len());
    let mut stack: Vec<u64> = kids
        .get(&0)
        .map(|v| v.iter().rev().map(|k| k.1).collect())
        .unwrap_or_default();
    while let Some(id) = stack.pop() {
        out.push(id);
        if let Some(v) = kids.get(&id) {
            for k in v.iter().rev() {
                stack.push(k.1);
            }
        }
    }
    out
}

unsafe fn str_of(p: *const c_char, len: u32) -> Result<String, Status> {
    if len == 0 {
        return Ok(String::new());
    }
    if p.is_null() {
        return Err(E_BAD_ARG);
    }
    let s = std::slice::from_raw_parts(p as *const u8, len as usize);
    String::from_utf8(s.to_vec()).map_err(|_| E_BAD_ARG)
}

unsafe fn slice_of<'a, T>(p: *const T, n: u32) -> Result<&'a [T], Status> {
    if n == 0 {
        return Ok(&[]);
    }
    if p.is_null() {
        return Err(E_BAD_ARG);
    }
    Ok(std::slice::from_raw_parts(p, n as usize))
}

fn rect4(r: &Rect) -> Result<[f32; 4], Status> {
    if !(r.x.is_finite() && r.y.is_finite() && r.w.is_finite() && r.h.is_finite()) || r.w < 0.0 || r.h < 0.0 {
        return Err(E_BAD_ARG);
    }
    Ok([r.x, r.y, r.w, r.h])
}

unsafe fn convert_prims(prims: &[Primitive], runs: &RunSlab) -> Result<Vec<Prim>, Status> {
    let mut out = Vec::with_capacity(prims.len());
    let mut clip = 0i32;
    let mut xf = 0i32;
    for p in prims {
        match p.kind {
            PRIM_RECT => out.push(Prim::Rect {
                r: rect4(&p.rect)?,
                color: p.color,
                border_color: p.border_color,
                border_w: p.border_width.max(0.0),
                radius: p.radius.max(0.0),
            }),
            PRIM_TEXT_RUN => {
                let run = runs.get(p.text_run).ok_or(E_STALE_HANDLE)?;
                out.push(Prim::Text { x: p.rect.x, y: p.rect.y, run });
            }
            PRIM_IMAGE | PRIM_PATH => return Err(E_UNSUPPORTED),
            PRIM_CLIP_PUSH => {
                clip += 1;
                out.push(Prim::ClipPush(rect4(&p.rect)?));
            }
            PRIM_CLIP_POP => {
                clip -= 1;
                if clip < 0 {
                    return Err(E_BAD_ARG);
                }
                out.push(Prim::ClipPop);
            }
            PRIM_TRANSFORM_PUSH => {
                // v0: translation only (a=1,b=0,c=0,d=1).
                if p.m[0] != 1.0 || p.m[1] != 0.0 || p.m[2] != 0.0 || p.m[3] != 1.0 {
                    return Err(E_UNSUPPORTED);
                }
                xf += 1;
                out.push(Prim::TranslatePush(p.m[4], p.m[5]));
            }
            PRIM_TRANSFORM_POP => {
                xf -= 1;
                if xf < 0 {
                    return Err(E_BAD_ARG);
                }
                out.push(Prim::TranslatePop);
            }
            _ => return Err(E_BAD_ARG),
        }
    }
    if clip != 0 || xf != 0 {
        return Err(E_BAD_ARG);
    }
    Ok(out)
}

unsafe fn convert_sem(s: &Semantic) -> Result<Sem, Status> {
    if s.identifier_len > IDENTIFIER_MAX {
        return Err(E_TOO_LARGE);
    }
    let rs = slice_of(s.runs, s.run_count)?;
    let mut runs = Vec::with_capacity(rs.len());
    for r in rs {
        let n = r.char_count;
        runs.push(SemRun {
            id: r.id,
            text: str_of(r.text, r.text_len)?,
            lengths: slice_of(r.char_lengths, n)?.to_vec(),
            positions: slice_of(r.char_positions, n)?.to_vec(),
            widths: slice_of(r.char_widths, n)?.to_vec(),
            word_starts: slice_of(r.word_starts, r.word_start_count)?.to_vec(),
            bounds: rect4(&r.bounds)?,
        });
    }
    Ok(Sem {
        role: s.role,
        actions: s.actions,
        flags: s.flags,
        label: str_of(s.label, s.label_len)?,
        value: str_of(s.value, s.value_len)?,
        identifier: str_of(s.identifier, s.identifier_len)?,
        runs,
        sel: if s.flags & SEM_HAS_SELECTION != 0 {
            Some((s.sel_anchor_run, s.sel_anchor_char, s.sel_focus_run, s.sel_focus_char))
        } else {
            None
        },
    })
}

/// Validates and applies `t` to `tree`. All-or-nothing. Returns the AX snapshot to publish.
pub unsafe fn commit(tree: &mut Tree, runs: &RunSlab, t: &Transaction) -> Result<AxShared, Status> {
    if t.upsert_count > MAX_UPSERTS || t.remove_count > MAX_REMOVES || t.primitive_count > MAX_PRIMITIVES {
        return Err(E_TOO_LARGE);
    }
    if t.version <= tree.version {
        return Err(E_STALE_VERSION);
    }
    let ups = slice_of(t.upserts, t.upsert_count)?;
    let rems = slice_of(t.removes, t.remove_count)?;
    let prims = slice_of(t.primitives, t.primitive_count)?;

    let mut staged = tree.nodes.clone();

    // Removes first; each takes its descendants with it.
    if !rems.is_empty() {
        let mut dead: HashSet<u64> = rems.iter().copied().collect();
        loop {
            let before = dead.len();
            let more: Vec<u64> = staged
                .values()
                .filter(|n| dead.contains(&n.parent))
                .map(|n| n.id)
                .collect();
            dead.extend(more);
            if dead.len() == before {
                break;
            }
        }
        for id in dead {
            staged.remove(&id);
        }
    }

    let mut seen: HashSet<u64> = HashSet::new();
    for n in ups {
        if n.id == 0 || !seen.insert(n.id) {
            return Err(E_BAD_ARG);
        }
        let end = n.prim_offset as usize + n.prim_count as usize;
        if end > prims.len() {
            return Err(E_BAD_ARG);
        }
        let node_prims = convert_prims(&prims[n.prim_offset as usize..end], runs)?;
        let sem = if n.has_semantic != 0 { Some(convert_sem(&n.semantic)?) } else { None };
        staged.insert(
            n.id,
            PNode {
                id: n.id,
                parent: n.parent,
                order: n.order,
                flags: n.flags,
                bounds: rect4(&n.bounds)?,
                prims: node_prims,
                sem,
            },
        );
    }

    // Parents must exist and chains must terminate at the root (no cycles).
    for n in staged.values() {
        let mut cur = n.parent;
        let mut hops = 0;
        while cur != 0 {
            let p = staged.get(&cur).ok_or(E_NOT_FOUND)?;
            cur = p.parent;
            hops += 1;
            if hops > 256 {
                return Err(E_BAD_ARG);
            }
        }
    }
    // Node ids and AX text-run ids share one namespace.
    let mut ids: HashSet<u64> = HashSet::new();
    for n in staged.values() {
        if !ids.insert(n.id) {
            return Err(E_BAD_ARG);
        }
    }
    for n in staged.values() {
        if let Some(s) = &n.sem {
            for r in &s.runs {
                if r.id == 0 || !ids.insert(r.id) {
                    return Err(E_BAD_ARG);
                }
            }
        }
    }
    if t.focus != 0 && !staged.contains_key(&t.focus) {
        return Err(E_NOT_FOUND);
    }

    tree.nodes = staged;
    tree.order = dfs_order(&tree.nodes);
    tree.version = t.version;
    tree.focus = t.focus;
    Ok(build_ax(tree))
}

fn build_ax(tree: &Tree) -> AxShared {
    // Nearest semantic ancestor (or 0) for every semantic node.
    let mut nodes = Vec::new();
    for id in &tree.order {
        let n = &tree.nodes[id];
        let Some(s) = &n.sem else { continue };
        let mut anc = n.parent;
        while anc != 0 {
            let p = &tree.nodes[&anc];
            if p.sem.is_some() {
                break;
            }
            anc = p.parent;
        }
        nodes.push(AxNode {
            id: n.id,
            parent: anc,
            role: s.role,
            actions: s.actions,
            flags: s.flags,
            label: s.label.clone(),
            value: s.value.clone(),
            identifier: s.identifier.clone(),
            bounds: n.bounds,
            runs: s
                .runs
                .iter()
                .map(|r| AxRun {
                    id: r.id,
                    text: r.text.clone(),
                    lengths: r.lengths.clone(),
                    positions: r.positions.clone(),
                    widths: r.widths.clone(),
                    word_starts: r.word_starts.clone(),
                    bounds: r.bounds,
                })
                .collect(),
            sel: s.sel,
        });
    }
    AxShared {
        window: crate::rt::LIVE_WINDOW.load(std::sync::atomic::Ordering::SeqCst),
        version: tree.version,
        title: String::new(),
        focus: tree.focus,
        nodes,
    }
}
