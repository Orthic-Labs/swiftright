//! Rev 0.14 glyph outlines of a retained text run (`swr_text_run_outline`).
//!
//! The host rotates and rasterises text itself (gpui 0.2.2 cannot draw a rotated glyph), so the renderer hands it the vector
//! outlines of the glyphs it already shaped. Nothing is reshaped: the glyph ids and positions are the ones `text::shape`
//! recorded in the run's `WrappedLine`s, and they are placed exactly as `view::paint_tracked` / `WrappedLine::paint` place them.
//!
//! Outline source = the face actually drawn:
//!  * a bundled family reads the registered bytes (`font::REGISTRY`), picking the face as `build_run_faces` does;
//!  * an installed family asks DirectWrite for the face's file, collection index and variation axis values (`dwr::source_of`);
//!  * a fallback sub-run is named by glyph id against the system candidates (`dwr::identify_source`, as `swr_text_run_faces`).
//! The file is parsed with ttf-parser and the face's axis values are applied, so a variable face (Segoe UI Variable: wght, opsz)
//! gives the outline of the instance DirectWrite selected.
//!
//! Not done (documented in swiftright.h): simulated bold and oblique (the base face's outline is returned), colour (emoji)
//! glyphs (skipped), a sub-run whose face cannot be resolved or read (skipped), fonts behind a non-local DirectWrite loader.
//!
//! Units: the SAME as `swr_char_cell` and `swr_line_info`: physical px of the run's measurement scale (DIP x scale), origin at
//! the run's top-left, y down, each line's glyphs starting at x = 0 of that line.

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;

use crate::abi::*;
use crate::text::{self, FaceReq, Measured};
use crate::{dwr, faces, font};

/// Largest font file read for outlines (bytes). A larger file is not read and its glyphs are skipped.
const MAX_FILE: u64 = 96 << 20;
/// File bytes kept between calls, in total; the cache clears when the next file would pass it.
const FILE_CACHE_BYTES: usize = 192 << 20;

/// Outline commands and points of a whole run. `pts` holds x, y pairs (so two floats per point).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Outline {
    pub cmds: Vec<u8>,
    pub pts: Vec<f32>,
}

impl Outline {
    pub fn point_count(&self) -> usize {
        self.pts.len() / 2
    }
}

/// Points a command consumes.
pub fn points_of(cmd: u8) -> usize {
    match cmd {
        PATH_CMD_MOVE | PATH_CMD_LINE => 1,
        PATH_CMD_QUAD => 2,
        PATH_CMD_CUBIC => 3,
        _ => 0,
    }
}

/// Font file bytes: registered (leaked) or read from disk (shared with the file cache).
#[derive(Clone)]
pub enum Data {
    Static(&'static [u8]),
    Shared(Arc<Vec<u8>>),
}

impl Data {
    fn bytes(&self) -> &[u8] {
        match self {
            Data::Static(b) => b,
            Data::Shared(v) => v,
        }
    }
}

/// A resolved face: bytes, face index in a collection, variation axis values (tag characters in order, value).
#[derive(Clone)]
pub struct FaceSrc {
    pub data: Data,
    pub index: u32,
    pub axes: Vec<([u8; 4], f32)>,
}

/// One glyph to draw: the sub-run it belongs to (index into `MeasuredExt::runs`), its glyph id, baseline origin (px) and size (px).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Placed {
    pub rec_ix: usize,
    pub gid: u32,
    pub x: f32,
    pub y: f32,
    pub size_px: f32,
    pub emoji: bool,
}

// ---------------------------------------------------------------- pure outline building

/// ttf-parser outline sink: scales font units to px, flips y (font y is up) and translates to the glyph origin.
struct Sink<'a> {
    out: &'a mut Outline,
    s: f32,
    ox: f32,
    oy: f32,
}

impl Sink<'_> {
    fn pt(&mut self, x: f32, y: f32) {
        self.out.pts.push(self.ox + x * self.s);
        self.out.pts.push(self.oy - y * self.s);
    }
}

impl ttf_parser::OutlineBuilder for Sink<'_> {
    fn move_to(&mut self, x: f32, y: f32) {
        self.out.cmds.push(PATH_CMD_MOVE);
        self.pt(x, y);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.out.cmds.push(PATH_CMD_LINE);
        self.pt(x, y);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        self.out.cmds.push(PATH_CMD_QUAD);
        self.pt(x1, y1);
        self.pt(x, y);
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        self.out.cmds.push(PATH_CMD_CUBIC);
        self.pt(x1, y1);
        self.pt(x2, y2);
        self.pt(x, y);
    }
    fn close(&mut self) {
        self.out.cmds.push(PATH_CMD_CLOSE);
    }
}

/// Parses `src` and applies its axis values. None when the file does not parse.
fn open(src: &FaceSrc) -> Option<ttf_parser::Face<'_>> {
    let mut face = ttf_parser::Face::parse(src.data.bytes(), src.index).ok()?;
    if face.is_variable() {
        for (tag, value) in &src.axes {
            // None: the face has no such axis. Values outside the axis range are clamped by ttf-parser.
            let _ = face.set_variation(ttf_parser::Tag::from_bytes(tag), *value);
        }
    }
    Some(face)
}

/// Appends one glyph outline (nothing when the glyph has no outline, e.g. a space, or the id is out of range).
fn append_glyph(face: &ttf_parser::Face, gid: u32, size_px: f32, ox: f32, oy: f32, out: &mut Outline) {
    let upem = face.units_per_em() as f32;
    if gid > u16::MAX as u32 || upem <= 0.0 || !size_px.is_finite() || size_px <= 0.0 {
        return;
    }
    let (c0, p0) = (out.cmds.len(), out.pts.len());
    let ok = {
        let mut sink = Sink { out: &mut *out, s: size_px / upem, ox, oy };
        face.outline_glyph(ttf_parser::GlyphId(gid as u16), &mut sink).is_some()
    };
    if !ok {
        out.cmds.truncate(c0);
        out.pts.truncate(p0);
    }
}

/// Outline of every placed glyph. `resolve(rec_ix)` names the face of a sub-run once per sub-run (placed glyphs are grouped by
/// sub-run, in order). Colour glyphs and glyphs of an unresolved face are skipped.
pub fn build(placed: &[Placed], resolve: &mut dyn FnMut(usize) -> Option<FaceSrc>) -> Outline {
    let mut out = Outline::default();
    let mut i = 0;
    while i < placed.len() {
        let rec_ix = placed[i].rec_ix;
        let mut j = i;
        while j < placed.len() && placed[j].rec_ix == rec_ix {
            j += 1;
        }
        let group = &placed[i..j];
        i = j;
        if group.iter().all(|p| p.emoji) {
            continue;
        }
        let Some(src) = resolve(rec_ix) else { continue };
        let Some(face) = open(&src) else { continue };
        for p in group.iter().filter(|p| !p.emoji) {
            append_glyph(&face, p.gid, p.size_px, p.x, p.y, &mut out);
        }
    }
    out
}

// ---------------------------------------------------------------- placement (mirrors view::paint_tracked)

/// Position of every shaped glyph of the run, in the run's px space. Mirrors `view::paint_tracked`: the first glyph of a visual
/// line sits at x = 0, glyph x = (shaped x - line start x) + tracking per cluster since the line start, a line's baseline is
/// half-leading + ascent below its top (`WrappedLine::paint` uses the same formula with tracking 0), lines advance by the line
/// height, or sit at their reported (snapped) tops under the Mac rule.
pub fn place(m: &Measured) -> Vec<Placed> {
    let mut out = Vec::new();
    let k = m.gpui_ratio;
    let g = m.scale / k; // physical px per GPUI logical px
    let lh = m.line_height_dip * k; // GPUI logical
    let t_px = m.ext.track_dip * m.scale;
    let tops: Vec<f32> = m.lines.iter().map(|l| l.top).collect();
    let mut rec_ix = 0usize; // `MeasuredExt::runs` has one record per NON-empty layout run, in order
    let mut line_base = 0usize;
    for (wl, top) in m.wrapped.iter() {
        let layout = &wl.unwrapped_layout;
        let n_vis = wl.wrap_boundaries.len() + 1;
        let offs: Option<Vec<f32>> = if m.ext.mac_lines {
            Some(text::paragraph_line_offsets(&tops, line_base, n_vis, m.line_height_dip * m.scale))
        } else {
            None
        };
        line_base += n_vis;
        let ascent = f32::from(layout.ascent);
        let descent = f32::from(layout.descent);
        let baseline_y = ((lh - ascent - descent) / 2.0 + ascent) * g;
        let size_px = f32::from(layout.font_size) * g;
        let mut wraps = wl.wrap_boundaries.iter().peekable();
        let mut line_ix = 0usize;
        let mut line_top = *top;
        let mut line_start_x = 0.0f32;
        let mut ordinal = 0usize;
        let mut prev_index: Option<usize> = None;
        for (run_ix, run) in layout.runs.iter().enumerate() {
            if run.glyphs.is_empty() {
                continue;
            }
            for (glyph_ix, gl) in run.glyphs.iter().enumerate() {
                if wraps.peek().map_or(false, |b| b.run_ix == run_ix && b.glyph_ix == glyph_ix) {
                    wraps.next();
                    line_ix += 1;
                    line_top = match offs.as_ref().and_then(|o| o.get(line_ix)) {
                        Some(off) => *top + *off,
                        None => line_top + lh * g,
                    };
                    line_start_x = f32::from(gl.position.x);
                    ordinal = 0;
                    prev_index = None;
                }
                // A cluster (several glyphs for one index) counts once.
                if let Some(p) = prev_index {
                    if p != gl.index {
                        ordinal += 1;
                    }
                }
                prev_index = Some(gl.index);
                out.push(Placed {
                    rec_ix,
                    gid: text::glyph_id_of(gl),
                    x: (f32::from(gl.position.x) - line_start_x) * g + t_px * ordinal as f32,
                    y: line_top + baseline_y,
                    size_px,
                    emoji: gl.is_emoji,
                });
            }
            rec_ix += 1;
        }
    }
    out
}

// ---------------------------------------------------------------- face resolution and file cache

thread_local! {
    static FILES: RefCell<(HashMap<String, Option<Arc<Vec<u8>>>>, usize)> = RefCell::new((HashMap::new(), 0));
    /// The last outline built, keyed by its run: the two-call convention (counts, then data) does the work once.
    static LAST: RefCell<Option<(Arc<Measured>, Arc<Outline>)>> = const { RefCell::new(None) };
}

/// The bytes of a font file, read once and kept (None when unreadable or over `MAX_FILE`, also kept).
fn file_bytes(path: &str) -> Option<Arc<Vec<u8>>> {
    FILES.with(|c| {
        let mut c = c.borrow_mut();
        if let Some(v) = c.0.get(path) {
            return v.clone();
        }
        let read = std::fs::metadata(path).ok().filter(|m| m.len() <= MAX_FILE).and_then(|_| std::fs::read(path).ok()).map(Arc::new);
        let len = read.as_ref().map_or(0, |v| v.len());
        if c.1 + len > FILE_CACHE_BYTES {
            c.0.clear();
            c.1 = 0;
        }
        c.1 += len;
        c.0.insert(path.to_string(), read.clone());
        read
    })
}

fn from_system(s: dwr::FaceSource) -> Option<FaceSrc> {
    Some(FaceSrc { data: Data::Shared(file_bytes(&s.path)?), index: s.index, axes: s.axes })
}

/// The face of the run's primary family: bundled bytes (the real face `build_run_faces` names; a variable file gets the weight
/// handed to gpui on its wght axis) or the installed family's real face. No simulation is applied.
fn primary_src(face: &FaceReq) -> Option<FaceSrc> {
    let want = face.weight.round().max(1.0) as u32;
    let bundled = font::REGISTRY.lock().map(|g| g.family_entries(&face.family)).unwrap_or_default();
    if !bundled.is_empty() {
        let list: Vec<faces::FaceEntry> = bundled.iter().map(|e| faces::FaceEntry { weight: e.meta.weight, italic: e.meta.italic }).collect();
        let p = faces::pick_face(&list, want, face.italic, true, true);
        let hit = bundled.iter().find(|e| e.meta.weight == p.weight && e.meta.italic == p.italic).unwrap_or(&bundled[0]);
        return Some(FaceSrc { data: Data::Static(hit.bytes?), index: 0, axes: vec![(*b"wght", want as f32)] });
    }
    from_system(dwr::source_of(&face.family, want, face.italic)?)
}

/// Outline of a whole retained run (see the module docs for the units and what is skipped).
pub fn run_outline(m: &Measured, fallback_candidates: &[&str]) -> Outline {
    let placed = place(m);
    let face = &m.ext.face;
    let mut candidates: Vec<String> = Vec::new();
    if font::REGISTRY.lock().map_or(true, |g| g.family_entries(&face.family).is_empty()) {
        candidates.push(face.family.clone());
    }
    candidates.extend(face.fallbacks.iter().cloned());
    candidates.extend(fallback_candidates.iter().map(|s| s.to_string()));
    let mut primary: Option<Option<FaceSrc>> = None;
    build(&placed, &mut |rec_ix| {
        let rec = m.ext.runs.get(rec_ix)?;
        if rec.primary {
            primary.get_or_insert_with(|| primary_src(face)).clone()
        } else {
            from_system(dwr::identify_source(&candidates, rec.first_char, rec.first_gid)?)
        }
    })
}

/// `run_outline`, remembering the last result for the same retained run.
pub fn run_outline_cached(m: &Arc<Measured>, fallback_candidates: &[&str]) -> Arc<Outline> {
    if let Some(o) = LAST.with(|l| l.borrow().as_ref().filter(|(r, _)| Arc::ptr_eq(r, m)).map(|(_, o)| o.clone())) {
        return o;
    }
    let o = Arc::new(run_outline(m, fallback_candidates));
    LAST.with(|l| *l.borrow_mut() = Some((m.clone(), o.clone())));
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    const TINOS: &[u8] = include_bytes!("../testdata/fonts/Tinos-Regular.ttf");

    fn tinos() -> FaceSrc {
        FaceSrc { data: Data::Static(TINOS), index: 0, axes: Vec::new() }
    }

    fn gid_of(ch: char) -> u32 {
        let f = ttf_parser::Face::parse(TINOS, 0).unwrap();
        f.glyph_index(ch).unwrap().0 as u32
    }

    fn placed(ch: char, x: f32, y: f32, size: f32) -> Placed {
        Placed { rec_ix: 0, gid: gid_of(ch), x, y, size_px: size, emoji: false }
    }

    /// Walks the commands against the points: every command has its points, nothing is left over, every contour is closed.
    fn check_structure(o: &Outline) -> (usize, usize) {
        let mut p = 0usize;
        let (mut moves, mut closes) = (0, 0);
        let mut open = false;
        for &c in &o.cmds {
            assert!(c <= PATH_CMD_CLOSE, "unknown command {c}");
            match c {
                PATH_CMD_MOVE => {
                    assert!(!open, "MOVE inside an open contour");
                    open = true;
                    moves += 1;
                }
                PATH_CMD_CLOSE => {
                    assert!(open, "CLOSE without a contour");
                    open = false;
                    closes += 1;
                }
                _ => assert!(open, "segment outside a contour"),
            }
            p += points_of(c);
        }
        assert!(!open, "unclosed contour");
        assert_eq!(p, o.point_count(), "points consumed by the commands");
        assert_eq!(o.pts.len() % 2, 0);
        assert!(o.pts.iter().all(|v| v.is_finite()));
        (moves, closes)
    }

    fn bounds(o: &Outline) -> (f32, f32, f32, f32) {
        let xs = o.pts.chunks(2).map(|p| p[0]);
        let ys = o.pts.chunks(2).map(|p| p[1]);
        (xs.clone().fold(f32::MAX, f32::min), ys.clone().fold(f32::MAX, f32::min), xs.fold(f32::MIN, f32::max), ys.fold(f32::MIN, f32::max))
    }

    #[test]
    fn capital_a_is_two_closed_contours_with_sane_bounds_and_y_down() {
        let o = build(&[placed('A', 10.0, 50.0, 32.0)], &mut |_| Some(tinos()));
        let (moves, closes) = check_structure(&o);
        assert_eq!((moves, closes), (2, 2), "outer shape + counter");
        let (x0, y0, x1, y1) = bounds(&o);
        // Tinos 'A': cap height 1341 / 2048 em = 20.95 px at 32 px; advance 1479 / 2048 em = 23.1 px.
        assert!(x0 >= 10.0 - 1.0 && x1 <= 10.0 + 24.0 && x1 - x0 > 18.0, "x {x0}..{x1}");
        assert!((y1 - 50.0).abs() < 0.5, "baseline at the bottom of A: {y1}");
        assert!((50.0 - y0 - 20.95).abs() < 0.6, "cap height above the baseline (y down): {y0}");
    }

    #[test]
    fn round_letter_has_curves_and_o_has_two_contours() {
        let o = build(&[placed('O', 0.0, 40.0, 40.0)], &mut |_| Some(tinos()));
        let (moves, _) = check_structure(&o);
        assert_eq!(moves, 2);
        assert!(o.cmds.iter().any(|&c| c == PATH_CMD_QUAD || c == PATH_CMD_CUBIC), "TrueType O is quadratic");
    }

    #[test]
    fn glyph_position_translates_and_size_scales() {
        let a = build(&[placed('H', 0.0, 0.0, 20.0)], &mut |_| Some(tinos()));
        let b = build(&[placed('H', 100.0, 30.0, 20.0)], &mut |_| Some(tinos()));
        assert_eq!(a.cmds, b.cmds);
        for (p, q) in a.pts.chunks(2).zip(b.pts.chunks(2)) {
            assert!((q[0] - p[0] - 100.0).abs() < 1e-3 && (q[1] - p[1] - 30.0).abs() < 1e-3);
        }
        let big = build(&[placed('H', 0.0, 0.0, 40.0)], &mut |_| Some(tinos()));
        let (ax0, ay0, ax1, ay1) = bounds(&a);
        let (bx0, by0, bx1, by1) = bounds(&big);
        assert!(((bx1 - bx0) / (ax1 - ax0) - 2.0).abs() < 1e-3 && ((by1 - by0) / (ay1 - ay0) - 2.0).abs() < 1e-3);
    }

    #[test]
    fn space_emoji_unresolved_and_bad_ids_add_nothing_and_a_run_concatenates_glyphs() {
        let one = build(&[placed('i', 0.0, 20.0, 20.0)], &mut |_| Some(tinos()));
        let (m1, _) = check_structure(&one);
        // A space has no outline.
        assert!(build(&[placed(' ', 0.0, 20.0, 20.0)], &mut |_| Some(tinos())).cmds.is_empty());
        // An emoji glyph is skipped without even resolving its face.
        let mut calls = 0;
        let emoji = Placed { emoji: true, ..placed('i', 0.0, 20.0, 20.0) };
        assert!(build(&[emoji], &mut |_| { calls += 1; Some(tinos()) }).cmds.is_empty());
        assert_eq!(calls, 0);
        // An unresolved face and an out-of-range glyph id are skipped.
        assert!(build(&[placed('i', 0.0, 20.0, 20.0)], &mut |_| None).cmds.is_empty());
        assert!(build(&[Placed { gid: 60000, ..placed('i', 0.0, 20.0, 20.0) }], &mut |_| Some(tinos())).cmds.is_empty());
        assert!(build(&[Placed { gid: 70000, ..placed('i', 0.0, 20.0, 20.0) }], &mut |_| Some(tinos())).cmds.is_empty());
        // Two glyphs of one sub-run: the face is resolved once, the outlines concatenate.
        let mut resolved = 0;
        let two = build(&[placed('i', 0.0, 20.0, 20.0), placed('i', 10.0, 20.0, 20.0)], &mut |_| { resolved += 1; Some(tinos()) });
        assert_eq!(resolved, 1);
        let (m2, _) = check_structure(&two);
        assert_eq!(m2, 2 * m1);
        assert_eq!(two.cmds.len(), 2 * one.cmds.len());
        // A degenerate size draws nothing.
        assert!(build(&[placed('i', 0.0, 20.0, 0.0)], &mut |_| Some(tinos())).cmds.is_empty());
        assert!(build(&[placed('i', 0.0, 20.0, f32::NAN)], &mut |_| Some(tinos())).cmds.is_empty());
    }

    #[test]
    fn a_file_that_is_not_a_font_resolves_to_nothing() {
        static JUNK: [u8; 16] = [7; 16];
        let o = build(&[Placed { gid: 1, ..placed('i', 0.0, 20.0, 20.0) }], &mut |_| Some(FaceSrc { data: Data::Static(&JUNK), index: 0, axes: Vec::new() }));
        assert!(o.cmds.is_empty());
    }

    #[test]
    fn axis_values_on_a_static_face_are_ignored() {
        let mut s = tinos();
        s.axes = vec![(*b"wght", 700.0)];
        let a = build(&[placed('H', 0.0, 0.0, 20.0)], &mut |_| Some(s.clone()));
        let b = build(&[placed('H', 0.0, 0.0, 20.0)], &mut |_| Some(tinos()));
        assert_eq!(a, b);
    }

    #[test]
    fn point_arity_matches_the_path_command_set() {
        assert_eq!([PATH_CMD_MOVE, PATH_CMD_LINE, PATH_CMD_QUAD, PATH_CMD_CUBIC, PATH_CMD_CLOSE].map(points_of), [1, 1, 2, 3, 0]);
    }
}
