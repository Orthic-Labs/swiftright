//! The retained snapshot: node table, primitives, semantics. `commit` validates a
//! transaction completely, then applies it; painting, hit-testing and the AccessKit
//! data all derive from the resulting snapshot. UI thread only; never calls the host.

use std::collections::{HashMap, HashSet};
use std::ffi::c_char;
use std::sync::Arc;

use crate::abi::*;
use crate::ax::{AxNode, AxRun, AxShared};
use crate::rt::LIVE_TREE_NODES;
use crate::text::{Measured, RunSlab, Slab, TrackedImage};
use std::sync::atomic::Ordering::SeqCst;

#[derive(Clone)]
pub enum Prim {
    Rect { r: [f32; 4], color: u32, border_color: u32, border_w: f32, radius: f32 },
    Text { x: f32, y: f32, run: Arc<Measured> },
    Underline { r: [f32; 4], color: u32 },
    /// Rev 0.6: the image scaled to fill `r`, corner radius `radius` (physical px).
    Image { r: [f32; 4], radius: f32, img: Arc<TrackedImage> },
    ClipPush([f32; 4]),
    ClipPop,
    TranslatePush(f32, f32),
    TranslatePop,
}

/// An AX text run is stored in the form AccessKit publication reads, so building the AX snapshot
/// of a commit shares it (a reference count) instead of copying its vectors.
pub type SemRun = AxRun;

#[derive(Clone)]
pub struct Sem {
    pub role: u32,
    pub actions: u32,
    pub flags: u32,
    pub label: Arc<str>,
    pub value: Arc<str>,
    pub identifier: Arc<str>,
    pub toggled: u32,
    /// Rev 0.9: value, min, max, step, jump of a slider (set from the transaction's range table, never from the node).
    pub range: Option<[f64; 5]>,
    pub runs: Arc<Vec<SemRun>>,
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
    /// Node ids and AX text-run ids: one namespace, kept current by `commit`.
    ids: HashSet<u64>,
    /// Children of each node (unordered); root children are under 0. Lets a removal find its
    /// descendants without scanning the table.
    kids: HashMap<u64, Vec<u64>>,
}

impl Tree {
    pub fn clear(&mut self) {
        self.nodes.clear();
        self.order.clear();
        self.ids.clear();
        self.kids.clear();
        self.focus = 0;
        LIVE_TREE_NODES.store(0, SeqCst);
    }

    /// Recomputes `ids` and `kids` from `nodes` (the rare path after a refused commit).
    fn rebuild_indexes(&mut self) {
        self.ids.clear();
        self.kids.clear();
        for n in self.nodes.values() {
            self.ids.insert(n.id);
            if let Some(s) = &n.sem {
                for r in s.runs.iter() {
                    self.ids.insert(r.id);
                }
            }
            self.kids.entry(n.parent).or_default().push(n.id);
        }
    }

    /// True when the node or any ancestor carries SWR_SEM_DISABLED (rev 0.6).
    pub fn is_disabled(&self, id: u64) -> bool {
        let mut cur = id;
        let mut hops = 0;
        while cur != 0 && hops <= 256 {
            let Some(n) = self.nodes.get(&cur) else { return false };
            if n.sem.as_ref().is_some_and(|s| s.flags & SEM_DISABLED != 0) {
                return true;
            }
            cur = n.parent;
            hops += 1;
        }
        false
    }

    /// Topmost hit-target node containing the physical point. Rev 0.6: a disabled node
    /// (or a node below a disabled one) swallows the press: the result is 0, not the
    /// node underneath.
    pub fn hit(&self, x: f32, y: f32) -> u64 {
        for id in self.order.iter().rev() {
            if let Some(n) = self.nodes.get(id) {
                if n.flags & NODE_HIT_TARGET != 0
                    && x >= n.bounds[0]
                    && y >= n.bounds[1]
                    && x < n.bounds[0] + n.bounds[2]
                    && y < n.bounds[1] + n.bounds[3]
                {
                    return if self.is_disabled(*id) { 0 } else { *id };
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

pub unsafe fn slice_of<'a, T>(p: *const T, n: u32) -> Result<&'a [T], Status> {
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

unsafe fn convert_prims(
    prims: &[Primitive],
    runs: &RunSlab,
    images: &Slab<TrackedImage>,
) -> Result<Vec<Prim>, Status> {
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
            PRIM_UNDERLINE => {
                let r = rect4(&p.rect)?;
                if r[3] <= 0.0 {
                    return Err(E_BAD_ARG);
                }
                out.push(Prim::Underline { r, color: p.color });
            }
            PRIM_IMAGE => {
                let img = images.get(p.image).ok_or(E_STALE_HANDLE)?;
                out.push(Prim::Image { r: rect4(&p.rect)?, radius: p.radius.max(0.0), img });
            }
            PRIM_PATH => return Err(E_UNSUPPORTED),
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

/// The empty string and the empty run list are shared: most semantic nodes carry no value, identifier or runs, and an
/// allocation per absent field is most of what converting a commit's nodes costs.
fn empty_str() -> Arc<str> {
    static EMPTY: std::sync::OnceLock<Arc<str>> = std::sync::OnceLock::new();
    EMPTY.get_or_init(|| Arc::from("")).clone()
}

fn empty_runs() -> Arc<Vec<SemRun>> {
    static EMPTY: std::sync::OnceLock<Arc<Vec<SemRun>>> = std::sync::OnceLock::new();
    EMPTY.get_or_init(|| Arc::new(Vec::new())).clone()
}

unsafe fn bytes_of<'a>(p: *const c_char, len: u32) -> Result<&'a [u8], Status> {
    if len == 0 {
        return Ok(&[]);
    }
    if p.is_null() {
        return Err(E_BAD_ARG);
    }
    Ok(std::slice::from_raw_parts(p as *const u8, len as usize))
}

/// The string at `p`, shared with `old` when the bytes are the same (a node whose label did not change allocates nothing).
unsafe fn arc_str(p: *const c_char, len: u32, old: Option<&Arc<str>>) -> Result<Arc<str>, Status> {
    if len == 0 {
        return Ok(empty_str());
    }
    let bytes = bytes_of(p, len)?;
    if let Some(o) = old {
        if o.as_bytes() == bytes {
            return Ok(o.clone());
        }
    }
    std::str::from_utf8(bytes).map(Arc::from).map_err(|_| E_BAD_ARG)
}

/// Converts the semantic payload of an upsert. `old` is the semantic of the node being replaced (if any): every string, run and
/// per-character array that is byte-identical to it is shared with it instead of copied, so re-sending a scrolled list (every
/// node's bounds change, nothing else) costs no allocation per node beyond the new run table.
unsafe fn convert_sem(s: &Semantic, old: Option<&Sem>) -> Result<Sem, Status> {
    if s.identifier_len > IDENTIFIER_MAX {
        return Err(E_TOO_LARGE);
    }
    if s.toggled > TOGGLED_MIXED {
        return Err(E_BAD_ARG);
    }
    let rs = slice_of(s.runs, s.run_count)?;
    let old_runs: Option<&Arc<Vec<SemRun>>> = old.map(|o| &o.runs);
    let mut runs: Vec<SemRun> = Vec::with_capacity(rs.len());
    let mut all_same = old_runs.is_some_and(|o| o.len() == rs.len());
    for (i, r) in rs.iter().enumerate() {
        let n = r.char_count;
        let text = bytes_of(r.text, r.text_len)?;
        let lengths = slice_of(r.char_lengths, n)?;
        let positions = slice_of(r.char_positions, n)?;
        let widths = slice_of(r.char_widths, n)?;
        let word_starts = slice_of(r.word_starts, r.word_start_count)?;
        let bounds = rect4(&r.bounds)?;
        let prev = old_runs.and_then(|o| o.get(i)).filter(|p| {
            p.id == r.id
                && p.text.as_bytes() == text
                && p.lengths[..] == *lengths
                && p.positions[..] == *positions
                && p.widths[..] == *widths
                && p.word_starts[..] == *word_starts
        });
        match prev {
            Some(p) => {
                if p.bounds != bounds {
                    all_same = false;
                }
                runs.push(AxRun {
                    id: p.id,
                    text: p.text.clone(),
                    lengths: p.lengths.clone(),
                    positions: p.positions.clone(),
                    widths: p.widths.clone(),
                    word_starts: p.word_starts.clone(),
                    bounds,
                });
            }
            None => {
                all_same = false;
                runs.push(AxRun {
                    id: r.id,
                    text: std::str::from_utf8(text).map(Arc::from).map_err(|_| E_BAD_ARG)?,
                    lengths: Arc::from(lengths),
                    positions: Arc::from(positions),
                    widths: Arc::from(widths),
                    word_starts: Arc::from(word_starts),
                    bounds,
                });
            }
        }
    }
    let runs = if runs.is_empty() {
        empty_runs()
    } else if all_same {
        // Nothing about the runs changed, bounds included: the previous table is the table.
        old_runs.cloned().unwrap_or_else(|| Arc::new(runs))
    } else {
        Arc::new(runs)
    };
    Ok(Sem {
        role: s.role,
        actions: s.actions,
        flags: s.flags,
        label: arc_str(s.label, s.label_len, old.map(|o| &o.label))?,
        value: arc_str(s.value, s.value_len, old.map(|o| &o.value))?,
        identifier: arc_str(s.identifier, s.identifier_len, old.map(|o| &o.identifier))?,
        toggled: s.toggled,
        range: None,
        runs,
        sel: if s.flags & SEM_HAS_SELECTION != 0 {
            Some((s.sel_anchor_run, s.sel_anchor_char, s.sel_focus_run, s.sel_focus_char))
        } else {
            None
        },
    })
}

/// What a commit changed, so a refused one can be put back exactly.
#[derive(Default)]
struct Journal {
    /// Nodes that were removed (with their descendants).
    removed: Vec<PNode>,
    /// The previous value of each node an upsert replaced.
    replaced: Vec<PNode>,
    /// Ids of nodes an upsert created.
    added: Vec<u64>,
}

fn run_ids(n: &PNode) -> impl Iterator<Item = u64> + '_ {
    n.sem.iter().flat_map(|s| s.runs.iter().map(|r| r.id))
}

/// Validates and applies `t` to `tree` in place. All-or-nothing: every upsert is converted first
/// (nothing touched on error), and a refusal after that point is undone from a journal, so the cost
/// of a commit follows what it changes, not the size of the tree. Returns the AX snapshot to publish.
pub unsafe fn commit(
    tree: &mut Tree,
    runs: &RunSlab,
    images: &Slab<TrackedImage>,
    t: &Transaction,
) -> Result<AxShared, Status> {
    commit_ranges(tree, runs, images, t, &[])
}

/// Rev 0.9: the numeric range of a slider arrives in the transaction's range table. Every entry must name a node upserted by the
/// same transaction whose role is SWR_ROLE_SLIDER; value, min, max, step and jump must be finite, min <= max, step and jump >= 0
/// and the value inside [min, max]. Anything else is E_BAD_ARG and nothing is applied.
fn check_ranges(ranges: &[RangeEntry], ups: &[Node]) -> Result<HashMap<u64, [f64; 5]>, Status> {
    let mut m: HashMap<u64, [f64; 5]> = HashMap::with_capacity(ranges.len());
    for r in ranges {
        let ok = [r.value, r.min, r.max, r.step, r.jump].iter().all(|v| v.is_finite())
            && r.min <= r.max
            && r.value >= r.min
            && r.value <= r.max
            && r.step >= 0.0
            && r.jump >= 0.0
            && r.flags == 0;
        let slider = ups.iter().any(|n| n.id == r.id && n.has_semantic != 0 && n.semantic.role == ROLE_SLIDER);
        if !ok || !slider || m.insert(r.id, [r.value, r.min, r.max, r.step, r.jump]).is_some() {
            return Err(E_BAD_ARG);
        }
    }
    Ok(m)
}

pub unsafe fn commit_ranges(
    tree: &mut Tree,
    runs: &RunSlab,
    images: &Slab<TrackedImage>,
    t: &Transaction,
    ranges: &[RangeEntry],
) -> Result<AxShared, Status> {
    if t.upsert_count > MAX_UPSERTS || t.remove_count > MAX_REMOVES || t.primitive_count > MAX_PRIMITIVES {
        return Err(E_TOO_LARGE);
    }
    if t.version <= tree.version {
        return Err(E_STALE_VERSION);
    }
    let ups = slice_of(t.upserts, t.upsert_count)?;
    let rems = slice_of(t.removes, t.remove_count)?;
    let prims = slice_of(t.primitives, t.primitive_count)?;

    // 1. Convert and check every upsert on its own (no tree access).
    let range_map = check_ranges(ranges, ups)?;
    let mut seen: HashSet<u64> = HashSet::with_capacity(ups.len());
    let mut fresh: Vec<PNode> = Vec::with_capacity(ups.len());
    for n in ups {
        if n.id == 0 || !seen.insert(n.id) {
            return Err(E_BAD_ARG);
        }
        let end = n.prim_offset as usize + n.prim_count as usize;
        if end > prims.len() {
            return Err(E_BAD_ARG);
        }
        let node_prims = convert_prims(&prims[n.prim_offset as usize..end], runs, images)?;
        let old_sem = tree.nodes.get(&n.id).and_then(|o| o.sem.as_ref());
        let mut sem = if n.has_semantic != 0 { Some(convert_sem(&n.semantic, old_sem)?) } else { None };
        if let Some(s) = sem.as_mut() {
            s.range = range_map.get(&n.id).copied();
        }
        fresh.push(PNode {
            id: n.id,
            parent: n.parent,
            order: n.order,
            flags: n.flags,
            bounds: rect4(&n.bounds)?,
            prims: node_prims,
            sem,
        });
    }

    // 2. Removes first; each takes its descendants with it (ids that are not in the tree are ignored).
    let mut journal = Journal::default();
    let mut structure_changed = false;
    let mut dead: HashSet<u64> = HashSet::new();
    if !rems.is_empty() {
        let mut stack: Vec<u64> = rems.iter().copied().filter(|id| tree.nodes.contains_key(id)).collect();
        while let Some(id) = stack.pop() {
            if dead.insert(id) {
                if let Some(ch) = tree.kids.get(&id) {
                    stack.extend(ch.iter().copied());
                }
            }
        }
    }
    if !dead.is_empty() {
        structure_changed = true;
        let mut parents: HashSet<u64> = HashSet::new();
        for id in &dead {
            if let Some(n) = tree.nodes.remove(id) {
                tree.ids.remove(&n.id);
                for r in run_ids(&n) {
                    tree.ids.remove(&r);
                }
                parents.insert(n.parent);
                tree.kids.remove(id);
                journal.removed.push(n);
            }
        }
        for p in parents {
            if let Some(v) = tree.kids.get_mut(&p) {
                v.retain(|c| !dead.contains(c));
                if v.is_empty() {
                    tree.kids.remove(&p);
                }
            }
        }
    }

    // 3. Upserts. Pass one frees the run ids of nodes about to be replaced, so ids that move between
    // nodes in one commit are not seen as collisions; pass two installs and checks the new ones.
    // (A node whose run ids are unchanged, the usual case of a node that only moved, touches the id set not at all.)
    let mut runs_changed: Vec<bool> = Vec::with_capacity(fresh.len());
    for n in &fresh {
        let changed = match tree.nodes.get(&n.id) {
            Some(old) => {
                let same = run_ids(old).eq(run_ids(n));
                if !same {
                    for r in run_ids(old) {
                        tree.ids.remove(&r);
                    }
                }
                !same
            }
            None => true,
        };
        runs_changed.push(changed);
    }
    let mut failure: Option<Status> = None;
    for (n, runs_changed) in fresh.into_iter().zip(runs_changed) {
        let id = n.id;
        if let Some(old) = tree.nodes.get(&id) {
            if old.parent != n.parent || old.order != n.order {
                structure_changed = true;
            }
            if old.parent != n.parent {
                let old_parent = old.parent;
                if let Some(v) = tree.kids.get_mut(&old_parent) {
                    v.retain(|c| *c != id);
                    if v.is_empty() {
                        tree.kids.remove(&old_parent);
                    }
                }
                tree.kids.entry(n.parent).or_default().push(id);
            }
        } else {
            structure_changed = true;
            if !tree.ids.insert(id) {
                failure = Some(E_BAD_ARG);
                break;
            }
            tree.kids.entry(n.parent).or_default().push(id);
            journal.added.push(id);
        }
        let mut ok = true;
        if runs_changed {
            for r in run_ids(&n) {
                if r == 0 || !tree.ids.insert(r) {
                    ok = false;
                    break;
                }
            }
        }
        if let Some(prev) = tree.nodes.insert(id, n) {
            journal.replaced.push(prev);
        }
        if !ok {
            failure = Some(E_BAD_ARG);
            break;
        }
    }

    // 4. Parents must exist and chains must terminate at the root (no cycles): a cycle or a
    // dangling parent can only come from a node this commit upserted. The focus must exist.
    if failure.is_none() {
        'chains: for id in &seen {
            let mut cur = tree.nodes[id].parent;
            let mut hops = 0;
            while cur != 0 {
                let Some(p) = tree.nodes.get(&cur) else {
                    failure = Some(E_NOT_FOUND);
                    break 'chains;
                };
                cur = p.parent;
                hops += 1;
                if hops > 256 {
                    failure = Some(E_BAD_ARG);
                    break 'chains;
                }
            }
        }
    }
    if failure.is_none() && t.focus != 0 && !tree.nodes.contains_key(&t.focus) {
        failure = Some(E_NOT_FOUND);
    }
    if let Some(e) = failure {
        // Put everything back (newest change first), then rebuild the indexes from the table.
        for id in &journal.added {
            tree.nodes.remove(id);
        }
        for prev in journal.replaced.drain(..) {
            tree.nodes.insert(prev.id, prev);
        }
        for n in journal.removed.drain(..) {
            tree.nodes.insert(n.id, n);
        }
        tree.rebuild_indexes();
        return Err(e);
    }

    LIVE_TREE_NODES.store(tree.nodes.len() as u64, SeqCst);
    if structure_changed {
        tree.order = dfs_order(&tree.nodes);
    }
    tree.version = t.version;
    tree.focus = t.focus;
    Ok(build_ax(tree))
}

/// The AX snapshot of the committed tree. Strings and runs are shared with the tree (`Arc`), so
/// this is one small record per semantic node.
fn build_ax(tree: &Tree) -> AxShared {
    let mut nodes = Vec::new();
    for id in &tree.order {
        let n = &tree.nodes[id];
        let Some(s) = &n.sem else { continue };
        // Nearest semantic ancestor (or 0).
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
            // SWR_SEM_DISABLED is inherited by semantic descendants of a disabled node.
            flags: if tree.is_disabled(n.id) { s.flags | SEM_DISABLED } else { s.flags },
            toggled: s.toggled,
            range: s.range,
            label: s.label.clone(),
            value: s.value.clone(),
            identifier: s.identifier.clone(),
            bounds: n.bounds,
            runs: s.runs.clone(),
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rt::{IMAGE_HANDLES, LIVE_RUNS};
    use crate::text::{Measured, MAX_RUNS};
    use std::time::Instant;

    /// The original commit: clone the whole table, apply, validate everything, rebuild the order. Kept as the
    /// reference the incremental commit must agree with (result, table, paint order) and as the benchmark baseline.
    unsafe fn reference_commit(
        nodes: &HashMap<u64, PNode>,
        version: u64,
        runs: &RunSlab,
        images: &Slab<TrackedImage>,
        t: &Transaction,
    ) -> Result<(HashMap<u64, PNode>, Vec<u64>), Status> {
        if t.upsert_count > MAX_UPSERTS || t.remove_count > MAX_REMOVES || t.primitive_count > MAX_PRIMITIVES {
            return Err(E_TOO_LARGE);
        }
        if t.version <= version {
            return Err(E_STALE_VERSION);
        }
        let ups = slice_of(t.upserts, t.upsert_count)?;
        let rems = slice_of(t.removes, t.remove_count)?;
        let prims = slice_of(t.primitives, t.primitive_count)?;
        let mut staged = nodes.clone();
        if !rems.is_empty() {
            let mut dead: HashSet<u64> = rems.iter().copied().collect();
            loop {
                let before = dead.len();
                let more: Vec<u64> = staged.values().filter(|n| dead.contains(&n.parent)).map(|n| n.id).collect();
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
            let node_prims = convert_prims(&prims[n.prim_offset as usize..end], runs, images)?;
            let sem = if n.has_semantic != 0 { Some(convert_sem(&n.semantic, None)?) } else { None };
            staged.insert(
                n.id,
                PNode { id: n.id, parent: n.parent, order: n.order, flags: n.flags, bounds: rect4(&n.bounds)?, prims: node_prims, sem },
            );
        }
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
        let mut ids: HashSet<u64> = HashSet::new();
        for n in staged.values() {
            if !ids.insert(n.id) {
                return Err(E_BAD_ARG);
            }
        }
        for n in staged.values() {
            if let Some(s) = &n.sem {
                for r in s.runs.iter() {
                    if r.id == 0 || !ids.insert(r.id) {
                        return Err(E_BAD_ARG);
                    }
                }
            }
        }
        if t.focus != 0 && !staged.contains_key(&t.focus) {
            return Err(E_NOT_FOUND);
        }
        let order = dfs_order(&staged);
        Ok((staged, order))
    }

    /// Owns the memory a Transaction points into.
    struct Tx {
        nodes: Vec<Node>,
        prims: Vec<Primitive>,
        removes: Vec<u64>,
        _strings: Vec<Box<[u8]>>,
        _runs: Vec<Box<AxTextRun>>,
        _floats: Vec<Box<[f32]>>,
        _bytes: Vec<Box<[u8]>>,
        version: u64,
        focus: u64,
    }

    impl Tx {
        fn new(version: u64) -> Tx {
            Tx { nodes: vec![], prims: vec![], removes: vec![], _strings: vec![], _runs: vec![], _floats: vec![], _bytes: vec![], version, focus: 0 }
        }

        fn raw(&self) -> Transaction {
            Transaction {
                struct_size: std::mem::size_of::<Transaction>() as u32,
                flags: 0,
                window: 1,
                version: self.version,
                focus: self.focus,
                upserts: self.nodes.as_ptr(),
                removes: self.removes.as_ptr(),
                primitives: self.prims.as_ptr(),
                upsert_count: self.nodes.len() as u32,
                remove_count: self.removes.len() as u32,
                primitive_count: self.prims.len() as u32,
                reserved: 0,
            }
        }

        fn string(&mut self, s: &str) -> (*const c_char, u32) {
            let b: Box<[u8]> = s.as_bytes().into();
            let p = b.as_ptr() as *const c_char;
            let n = b.len() as u32;
            self._strings.push(b);
            (p, n)
        }

        /// A node with a rect primitive, optionally a text run primitive, optionally a semantic with one AX run.
        fn node(&mut self, id: u64, parent: u64, order: u32, x: f32, label: Option<&str>, run_id: u64, text_run: u64) {
            let prim_offset = self.prims.len() as u32;
            let mut prim_count = 1;
            self.prims.push(Primitive {
                kind: PRIM_RECT, color: 0xFF0000FF, rect: Rect { x, y: 0.0, w: 10.0, h: 10.0 }, border_color: 0, border_width: 0.0,
                radius: 0.0, image_id: 0, text_run: 0, m: [0.0; 6], image: 0,
            });
            if text_run != 0 {
                self.prims.push(Primitive {
                    kind: PRIM_TEXT_RUN, color: 0, rect: Rect { x, y: 0.0, w: 0.0, h: 0.0 }, border_color: 0, border_width: 0.0,
                    radius: 0.0, image_id: 0, text_run, m: [0.0; 6], image: 0,
                });
                prim_count += 1;
            }
            let mut semantic: Semantic = unsafe { std::mem::zeroed() };
            let mut has = 0;
            if let Some(l) = label {
                has = 1;
                let (lp, ll) = self.string(l);
                semantic.label = lp;
                semantic.label_len = ll;
                semantic.role = ROLE_STATIC_TEXT;
                if run_id != 0 {
                    let (tp, tl) = self.string(l);
                    let lengths: Box<[u8]> = l.chars().map(|c| c.len_utf8() as u8).collect::<Vec<_>>().into();
                    let positions: Box<[f32]> = (0..l.chars().count()).map(|i| i as f32 * 8.0).collect::<Vec<_>>().into();
                    let widths: Box<[f32]> = vec![8.0; l.chars().count()].into();
                    let words: Box<[u8]> = vec![0u8].into();
                    let run = Box::new(AxTextRun {
                        id: run_id, text: tp, char_lengths: lengths.as_ptr(), char_positions: positions.as_ptr(), char_widths: widths.as_ptr(),
                        word_starts: words.as_ptr(), bounds: Rect { x, y: 0.0, w: 80.0, h: 10.0 }, text_len: tl,
                        char_count: lengths.len() as u32, word_start_count: 1, reserved: 0,
                    });
                    semantic.runs = &*run as *const AxTextRun;
                    semantic.run_count = 1;
                    self._runs.push(run);
                    self._floats.push(positions);
                    self._floats.push(widths);
                    self._bytes.push(lengths);
                    self._bytes.push(words);
                }
            }
            self.nodes.push(Node {
                id, parent, bounds: Rect { x, y: 0.0, w: 10.0, h: 10.0 }, order, flags: NODE_HIT_TARGET, prim_offset, prim_count,
                has_semantic: has, reserved: 0, semantic,
            });
        }
    }

    fn slabs() -> (RunSlab, Slab<TrackedImage>) {
        (Slab::new(&LIVE_RUNS, MAX_RUNS), Slab::new(&IMAGE_HANDLES, 16))
    }

    fn measured() -> Arc<Measured> {
        Arc::new(Measured {
            text: "x".into(), wrapped: vec![], cells: vec![], lines: vec![], width: 8.0, height: 24.0, first_baseline: 18.0,
            last_baseline: 18.0, line_height_dip: 24.0, scale: 1.0, char_count: 1, key: 1, ext: Default::default(),
        })
    }

    /// The comparable content of a table.
    fn digest(nodes: &HashMap<u64, PNode>) -> Vec<(u64, u64, u32, u32, [i64; 4], usize, Option<(String, usize)>)> {
        let mut v: Vec<_> = nodes
            .values()
            .map(|n| {
                (
                    n.id, n.parent, n.order, n.flags,
                    [n.bounds[0] as i64, n.bounds[1] as i64, n.bounds[2] as i64, n.bounds[3] as i64],
                    n.prims.len(),
                    n.sem.as_ref().map(|s| (s.label.to_string(), s.runs.len())),
                )
            })
            .collect();
        v.sort();
        v
    }

    /// A tiny deterministic generator.
    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    /// Rev 0.9: a slider node takes its numeric range from the range table of the same transaction; bad entries refuse the
    /// whole commit and leave the tree as it was.
    #[test]
    fn slider_range_table() {
        let (runs, images) = slabs();
        let mut tree = Tree::default();
        let mut tx = Tx::new(1);
        tx.node(1, 0, 0, 0.0, Some("Watch limit"), 0, 0);
        tx.nodes[0].semantic.role = ROLE_SLIDER;
        let good = [RangeEntry { id: 1, value: 40.0, min: 0.0, max: 100.0, step: 1.0, jump: 10.0, flags: 0, reserved: 0 }];
        let ax = unsafe { commit_ranges(&mut tree, &runs, &images, &tx.raw(), &good) }.unwrap();
        let n = ax.nodes.iter().find(|n| n.id == 1).unwrap();
        assert_eq!(n.role, ROLE_SLIDER);
        assert_eq!(n.range, Some([40.0, 0.0, 100.0, 1.0, 10.0]));

        // A next commit without a table: the node's range is gone (an upsert replaces semantics).
        let mut tx2 = Tx::new(2);
        tx2.node(1, 0, 0, 0.0, Some("Watch limit"), 0, 0);
        tx2.nodes[0].semantic.role = ROLE_SLIDER;
        let ax = unsafe { commit_ranges(&mut tree, &runs, &images, &tx2.raw(), &[]) }.unwrap();
        assert_eq!(ax.nodes.iter().find(|n| n.id == 1).unwrap().range, None);

        let cases: [(&str, RangeEntry); 6] = [
            ("value above max", RangeEntry { id: 1, value: 101.0, min: 0.0, max: 100.0, step: 1.0, jump: 10.0, flags: 0, reserved: 0 }),
            ("min above max", RangeEntry { id: 1, value: 5.0, min: 10.0, max: 0.0, step: 1.0, jump: 10.0, flags: 0, reserved: 0 }),
            ("nan", RangeEntry { id: 1, value: f64::NAN, min: 0.0, max: 100.0, step: 1.0, jump: 10.0, flags: 0, reserved: 0 }),
            ("negative step", RangeEntry { id: 1, value: 5.0, min: 0.0, max: 100.0, step: -1.0, jump: 10.0, flags: 0, reserved: 0 }),
            ("unknown node", RangeEntry { id: 9, value: 5.0, min: 0.0, max: 100.0, step: 1.0, jump: 10.0, flags: 0, reserved: 0 }),
            ("flags", RangeEntry { id: 1, value: 5.0, min: 0.0, max: 100.0, step: 1.0, jump: 10.0, flags: 1, reserved: 0 }),
        ];
        for (i, (what, e)) in cases.iter().enumerate() {
            let mut t = Tx::new(10 + i as u64);
            t.node(1, 0, 0, 0.0, Some("Watch limit"), 0, 0);
            t.nodes[0].semantic.role = ROLE_SLIDER;
            let r = unsafe { commit_ranges(&mut tree, &runs, &images, &t.raw(), std::slice::from_ref(e)) };
            assert_eq!(r.err(), Some(E_BAD_ARG), "{what}");
        }
        // A range for a node that is not a slider.
        let mut t = Tx::new(30);
        t.node(1, 0, 0, 0.0, Some("Text"), 0, 0);
        let r = unsafe { commit_ranges(&mut tree, &runs, &images, &t.raw(), &good) };
        assert_eq!(r.err(), Some(E_BAD_ARG));
        assert_eq!(tree.version, 2, "refused commits leave the version");
    }

    /// Random valid and invalid transactions: the incremental commit and the reference agree on the result, on the
    /// table after it, and on the paint order; a refused commit leaves the table as it was.
    #[test]
    fn incremental_commit_matches_reference() {
        let (mut runs, images) = slabs();
        let handle = runs.insert(measured()).unwrap();
        let mut tree = Tree::default();
        let mut reference: HashMap<u64, PNode> = HashMap::new();
        let mut ref_version = 0u64;
        let mut rng = Rng(0x9E3779B97F4A7C15);
        let mut refused = 0;
        let mut accepted = 0;
        for step in 1..=3000u64 {
            let mut tx = Tx::new(ref_version + 1);
            if rng.below(60) == 0 {
                tx.version = ref_version; // stale
            }
            let n_up = rng.below(12) as usize;
            let mut used: HashSet<u64> = HashSet::new();
            for _ in 0..n_up {
                let id = 1 + rng.below(40);
                if !used.insert(id) && rng.below(30) != 0 {
                    continue;
                }
                let mut parent = if rng.below(3) == 0 { 0 } else { 1 + rng.below(40) };
                if rng.below(50) == 0 {
                    parent = id; // self parent: must be refused
                }
                let label = if rng.below(2) == 0 { Some(format!("n{id}-{}", rng.below(5))) } else { None };
                let run_id = if label.is_some() && rng.below(3) != 0 { 1000 + id * 2 + rng.below(2) } else { 0 };
                let text_run = if rng.below(4) == 0 { handle } else { 0 };
                tx.node(id, parent, rng.below(5) as u32, rng.below(100) as f32, label.as_deref(), run_id, text_run);
            }
            for _ in 0..rng.below(4) {
                tx.removes.push(1 + rng.below(45));
            }
            if rng.below(8) == 0 {
                tx.focus = 1 + rng.below(40);
            }
            if rng.below(70) == 0 {
                tx.nodes.push(tx.nodes.first().copied().unwrap_or(unsafe { std::mem::zeroed() })); // duplicate id (or id 0)
            }
            let raw = tx.raw();
            let want = unsafe { reference_commit(&reference, ref_version, &runs, &images, &raw) };
            let before = digest(&tree.nodes);
            let got = unsafe { commit(&mut tree, &runs, &images, &raw) };
            match (&want, &got) {
                (Ok((table, order)), Ok(ax)) => {
                    accepted += 1;
                    reference = table.clone();
                    ref_version = raw.version;
                    assert_eq!(digest(&tree.nodes), digest(&reference), "table after step {step}");
                    assert_eq!(&tree.order, order, "paint order after step {step}");
                    assert_eq!(tree.version, raw.version);
                    assert_eq!(ax.nodes.len(), tree.nodes.values().filter(|n| n.sem.is_some()).count());
                }
                (Err(_), Err(_)) => {
                    // Both refuse. (With several faults in one transaction the reference reports whichever its hash-order
                    // walk meets first, so the status codes are only comparable for a single fault.)
                    refused += 1;
                    assert_eq!(digest(&tree.nodes), before, "refused commit changed the table at step {step}");
                    assert_eq!(digest(&tree.nodes), digest(&reference));
                    assert_eq!(tree.version, ref_version);
                }
                (a, b) => panic!("step {step}: reference {:?} vs incremental {:?}", a.as_ref().map(|_| ()), b.as_ref().map(|_| ())),
            }
            // The indexes stay what a rebuild would give.
            let mut check = Tree::default();
            check.nodes = tree.nodes.clone();
            check.rebuild_indexes();
            assert_eq!(tree.ids, check.ids, "id set after step {step}");
            let norm = |k: &HashMap<u64, Vec<u64>>| {
                let mut v: Vec<(u64, Vec<u64>)> = k.iter().map(|(a, b)| { let mut b = b.clone(); b.sort(); (*a, b) }).collect();
                v.sort();
                v
            };
            assert_eq!(norm(&tree.kids), norm(&check.kids), "children index after step {step}");
        }
        eprintln!("incremental_commit_matches_reference: accepted={accepted} refused={refused}");
        assert!(accepted > 50 && refused > 50, "the generator should exercise both outcomes");
    }

    /// 200-row list: 600 nodes in the table, every commit moves all of them (a scroll tick). Prints the cost of the
    /// original clone-everything commit and of the incremental one.
    #[test]
    fn scroll_commit_cost() {
        let (mut runs, images) = slabs();
        let handle = runs.insert(measured()).unwrap();
        let mut tree = Tree::default();
        let mut reference: HashMap<u64, PNode> = HashMap::new();
        let build = |version: u64, shift: f32| {
            let mut tx = Tx::new(version);
            for i in 0..600u64 {
                tx.node(1 + i, 0, i as u32, shift + i as f32, Some(&format!("row {i} detail text of some length")), (1 << 40) + i, handle);
            }
            tx
        };
        let first = build(1, 0.0);
        unsafe {
            commit(&mut tree, &runs, &images, &first.raw()).unwrap();
            reference = reference_commit(&reference, 0, &runs, &images, &first.raw()).unwrap().0;
        }
        let iters = 300u64;
        let mut ref_ns = 0u128;
        let mut new_ns = 0u128;
        let mut ref_ver = 1u64;
        for k in 0..iters {
            let tx = build(2 + k, (k % 7) as f32);
            let raw = tx.raw();
            let t0 = Instant::now();
            let r = unsafe { reference_commit(&reference, ref_ver, &runs, &images, &raw).unwrap() };
            ref_ns += t0.elapsed().as_nanos();
            reference = r.0;
            ref_ver = raw.version;
            let t1 = Instant::now();
            unsafe { commit(&mut tree, &runs, &images, &raw).unwrap() };
            new_ns += t1.elapsed().as_nanos();
        }
        // Where the time goes: cloning the table, converting the upserts, building the AX snapshot.
        let mut clone_ns = 0u128;
        let mut ax_ns = 0u128;
        let mut convert_ns = 0u128;
        for k in 0..iters {
            let t0 = Instant::now();
            let c = reference.clone();
            clone_ns += t0.elapsed().as_nanos();
            drop(c);
            let t1 = Instant::now();
            let _ = build_ax(&tree);
            ax_ns += t1.elapsed().as_nanos();
            let tx = build(1000 + k, 0.0);
            let raw = tx.raw();
            let t2 = Instant::now();
            let ups = unsafe { slice_of(raw.upserts, raw.upsert_count).unwrap() };
            let prims = unsafe { slice_of(raw.primitives, raw.primitive_count).unwrap() };
            for n in ups {
                let _ = unsafe { convert_prims(&prims[n.prim_offset as usize..(n.prim_offset + n.prim_count) as usize], &runs, &images) };
                let _ = unsafe { convert_sem(&n.semantic, None) };
            }
            convert_ns += t2.elapsed().as_nanos();
        }
        eprintln!(
            "scroll_commit_cost 600 nodes, all upserted (per commit): original clone commit {:.3} ms, incremental commit incl. AX snapshot {:.3} ms; \
             parts: table clone {:.3} ms, convert upserts {:.3} ms, AX snapshot {:.3} ms",
            ref_ns as f64 / iters as f64 / 1e6,
            new_ns as f64 / iters as f64 / 1e6,
            clone_ns as f64 / iters as f64 / 1e6,
            convert_ns as f64 / iters as f64 / 1e6,
            ax_ns as f64 / iters as f64 / 1e6
        );
    }
}
