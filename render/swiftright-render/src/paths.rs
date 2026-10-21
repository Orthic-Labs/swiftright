//! Rev 0.12 path table: decoding, validation and the pure geometry the renderer needs (flattening, bounds, and the row-band
//! cover of a path used as a clip). No GPUI here, so everything in this module is unit-testable on its own.
//!
//! A transaction carries three flat arrays (`swr_path_entry`, command bytes, x/y float points). Every entry is decoded and
//! validated whether or not a primitive names it, so a malformed table fails the whole commit (all-or-nothing, like every other
//! validation). Coordinates are physical px of the window, the same space as `swr_primitive.rect`.

use std::sync::Arc;

use crate::abi::*;

/// Largest coordinate magnitude accepted (physical px). Keeps flattening and tessellation finite.
pub const MAX_COORD: f32 = 1.0e6;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Seg {
    Move([f32; 2]),
    Line([f32; 2]),
    Quad([f32; 2], [f32; 2]),
    Cubic([f32; 2], [f32; 2], [f32; 2]),
    Close,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cap {
    Butt,
    Round,
    Square,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Join {
    Miter,
    Round,
    Bevel,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PathData {
    pub segs: Vec<Seg>,
    pub even_odd: bool,
    pub cap: Cap,
    pub join: Join,
    pub miter: f32,
    /// Hull of every anchor and control point: x, y, w, h (physical px).
    pub bounds: [f32; 4],
}

fn finite_pt(x: f32, y: f32) -> Result<[f32; 2], Status> {
    if x.is_finite() && y.is_finite() && x.abs() <= MAX_COORD && y.abs() <= MAX_COORD {
        Ok([x, y])
    } else {
        Err(E_BAD_ARG)
    }
}

/// The sub-slice `[offset, offset + count)` of `len` items, or E_BAD_ARG when it does not fit.
fn window(offset: u32, count: u32, len: usize) -> Result<std::ops::Range<usize>, Status> {
    let start = offset as usize;
    let end = start.checked_add(count as usize).ok_or(E_BAD_ARG)?;
    if end > len {
        return Err(E_BAD_ARG);
    }
    Ok(start..end)
}

/// Decodes one entry. The command stream must start with a move, every drawing command needs a current point (after a close
/// only a move may follow), and `pt_count` must equal exactly the points the commands consume.
pub fn decode_entry(e: &PathEntry, cmds: &[u8], pts: &[f32]) -> Result<PathData, Status> {
    let cr = window(e.cmd_offset, e.cmd_count, cmds.len())?;
    let pr = window(e.pt_offset, e.pt_count, pts.len() / 2)?;
    let cmds = &cmds[cr];
    let pts = &pts[pr.start * 2..pr.end * 2];
    if cmds.is_empty() || cmds[0] != PATH_CMD_MOVE {
        return Err(E_BAD_ARG);
    }
    if e.flags & !0x1F != 0 {
        return Err(E_BAD_ARG);
    }
    let cap = match (e.flags >> 1) & 3 {
        0 => Cap::Butt,
        1 => Cap::Round,
        2 => Cap::Square,
        _ => return Err(E_BAD_ARG),
    };
    let join = match (e.flags >> 3) & 3 {
        0 => Join::Miter,
        1 => Join::Round,
        2 => Join::Bevel,
        _ => return Err(E_BAD_ARG),
    };
    if !e.miter_limit.is_finite() || e.miter_limit < 0.0 || (e.miter_limit != 0.0 && e.miter_limit < 1.0) {
        return Err(E_BAD_ARG);
    }
    let mut next = 0usize;
    let mut take = |n: usize| -> Result<Vec<[f32; 2]>, Status> {
        if next + n > e.pt_count as usize {
            return Err(E_BAD_ARG);
        }
        let mut v = Vec::with_capacity(n);
        for i in 0..n {
            v.push(finite_pt(pts[(next + i) * 2], pts[(next + i) * 2 + 1])?);
        }
        next += n;
        Ok(v)
    };
    let mut segs = Vec::with_capacity(cmds.len());
    let (mut min, mut max) = ([f32::MAX; 2], [f32::MIN; 2]);
    let mut open = false; // a current point exists (a move has been seen and no close since)
    for &c in cmds {
        let seg = match c {
            PATH_CMD_MOVE => {
                let p = take(1)?;
                open = true;
                Seg::Move(p[0])
            }
            PATH_CMD_LINE | PATH_CMD_QUAD | PATH_CMD_CUBIC => {
                if !open {
                    return Err(E_BAD_ARG);
                }
                match c {
                    PATH_CMD_LINE => Seg::Line(take(1)?[0]),
                    PATH_CMD_QUAD => {
                        let p = take(2)?;
                        Seg::Quad(p[0], p[1])
                    }
                    _ => {
                        let p = take(3)?;
                        Seg::Cubic(p[0], p[1], p[2])
                    }
                }
            }
            PATH_CMD_CLOSE => {
                if !open {
                    return Err(E_BAD_ARG);
                }
                open = false;
                Seg::Close
            }
            _ => return Err(E_BAD_ARG),
        };
        for p in seg_points(&seg) {
            for k in 0..2 {
                min[k] = min[k].min(p[k]);
                max[k] = max[k].max(p[k]);
            }
        }
        segs.push(seg);
    }
    if next != e.pt_count as usize {
        return Err(E_BAD_ARG);
    }
    let bounds = if min[0] > max[0] { [0.0; 4] } else { [min[0], min[1], max[0] - min[0], max[1] - min[1]] };
    Ok(PathData {
        segs,
        even_odd: e.flags & PATH_FLAG_EVEN_ODD != 0,
        cap,
        join,
        miter: if e.miter_limit == 0.0 { 4.0 } else { e.miter_limit },
        bounds,
    })
}

fn seg_points(s: &Seg) -> Vec<[f32; 2]> {
    match *s {
        Seg::Move(a) | Seg::Line(a) => vec![a],
        Seg::Quad(a, b) => vec![a, b],
        Seg::Cubic(a, b, c) => vec![a, b, c],
        Seg::Close => vec![],
    }
}

/// Decodes the whole table. Limits are checked first (E_TOO_LARGE), then every entry (E_BAD_ARG).
pub fn decode_table(entries: &[PathEntry], cmds: &[u8], pts: &[f32]) -> Result<Vec<Arc<PathData>>, Status> {
    if entries.len() > MAX_PATHS as usize || cmds.len() > MAX_PATH_CMDS as usize || pts.len() / 2 > MAX_PATH_PTS as usize {
        return Err(E_TOO_LARGE);
    }
    entries.iter().map(|e| decode_entry(e, cmds, pts).map(Arc::new)).collect()
}

impl PathData {
    /// Polylines (one per sub-path, each implicitly closed for filling and clipping) with curves flattened to within `tol` px.
    pub fn flatten(&self, tol: f32) -> Vec<Vec<[f32; 2]>> {
        let tol = tol.max(1.0e-3);
        let mut out: Vec<Vec<[f32; 2]>> = Vec::new();
        let mut cur: Vec<[f32; 2]> = Vec::new();
        let mut last = [0.0f32; 2];
        for s in &self.segs {
            match *s {
                Seg::Move(p) => {
                    if cur.len() > 1 {
                        out.push(std::mem::take(&mut cur));
                    } else {
                        cur.clear();
                    }
                    cur.push(p);
                    last = p;
                }
                Seg::Line(p) => {
                    cur.push(p);
                    last = p;
                }
                Seg::Quad(c, p) => {
                    let dd = ((last[0] - 2.0 * c[0] + p[0]).powi(2) + (last[1] - 2.0 * c[1] + p[1]).powi(2)).sqrt();
                    let n = ((dd / (4.0 * tol)).sqrt().ceil() as usize).clamp(1, 128);
                    for i in 1..=n {
                        let t = i as f32 / n as f32;
                        let u = 1.0 - t;
                        cur.push([
                            u * u * last[0] + 2.0 * u * t * c[0] + t * t * p[0],
                            u * u * last[1] + 2.0 * u * t * c[1] + t * t * p[1],
                        ]);
                    }
                    last = p;
                }
                Seg::Cubic(c1, c2, p) => {
                    let d1 = ((last[0] - 2.0 * c1[0] + c2[0]).powi(2) + (last[1] - 2.0 * c1[1] + c2[1]).powi(2)).sqrt();
                    let d2 = ((c1[0] - 2.0 * c2[0] + p[0]).powi(2) + (c1[1] - 2.0 * c2[1] + p[1]).powi(2)).sqrt();
                    let n = ((3.0 * d1.max(d2) / (4.0 * tol)).sqrt().ceil() as usize).clamp(1, 128);
                    for i in 1..=n {
                        let t = i as f32 / n as f32;
                        let u = 1.0 - t;
                        let (a, b, c, d) = (u * u * u, 3.0 * u * u * t, 3.0 * u * t * t, t * t * t);
                        cur.push([
                            a * last[0] + b * c1[0] + c * c2[0] + d * p[0],
                            a * last[1] + b * c1[1] + c * c2[1] + d * p[1],
                        ]);
                    }
                    last = p;
                }
                Seg::Close => {
                    if cur.len() > 1 {
                        let first = cur[0];
                        out.push(std::mem::take(&mut cur));
                        last = first;
                    }
                    cur.clear();
                }
            }
        }
        if cur.len() > 1 {
            out.push(cur);
        }
        out
    }

    /// Row-band cover of the filled path inside `region` (x, y, w, h), for a renderer that can only clip by rectangle.
    /// Rows are `band` px tall starting at floor(region.y); a row is sampled at its centre line, so a pixel row is inside
    /// exactly where its centre is (the sampling GPUI's rectangle clip applies to the pixels it draws). Spans are exact in x;
    /// vertically adjacent rows with identical spans merge into one rect. The curved edge is a staircase of `band` px, not
    /// anti-aliased (a rectangle clip is binary).
    pub fn cover_rects(&self, region: [f32; 4], band: f32) -> Vec<[f32; 4]> {
        let band = band.max(0.25);
        let contours = self.flatten(0.1);
        let (rx0, rx1) = (region[0], region[0] + region[2]);
        let y_start = region[1].floor();
        let y_end = (region[1] + region[3]).ceil();
        let rows = (((y_end - y_start) / band).ceil().max(0.0) as usize).min(16384);
        let mut out: Vec<[f32; 4]> = Vec::new();
        let mut open_top = 0.0f32;
        let mut prev: Vec<[f32; 2]> = Vec::new();
        let flush = |out: &mut Vec<[f32; 4]>, spans: &[[f32; 2]], top: f32, bottom: f32| {
            for s in spans {
                out.push([s[0], top, s[1] - s[0], bottom - top]);
            }
        };
        for r in 0..rows {
            let top = y_start + r as f32 * band;
            let yc = top + band * 0.5;
            let spans = self.row_spans(&contours, yc, rx0, rx1);
            if r == 0 {
                open_top = top;
                prev = spans;
            } else if spans != prev {
                flush(&mut out, &prev, open_top, top);
                open_top = top;
                prev = spans;
            }
        }
        if rows > 0 {
            flush(&mut out, &prev, open_top, y_start + rows as f32 * band);
        }
        out
    }

    /// Inside spans of the filled path on the horizontal line `y`, clamped to [x0, x1].
    fn row_spans(&self, contours: &[Vec<[f32; 2]>], y: f32, x0: f32, x1: f32) -> Vec<[f32; 2]> {
        let mut xs: Vec<(f32, i32)> = Vec::new();
        for c in contours {
            let n = c.len();
            for i in 0..n {
                let (a, b) = (c[i], c[(i + 1) % n]);
                if a[1] == b[1] {
                    continue;
                }
                let (lo, hi, dir) = if a[1] < b[1] { (a[1], b[1], 1) } else { (b[1], a[1], -1) };
                if y >= lo && y < hi {
                    let t = (y - a[1]) / (b[1] - a[1]);
                    xs.push((a[0] + t * (b[0] - a[0]), dir));
                }
            }
        }
        xs.sort_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
        let mut spans: Vec<[f32; 2]> = Vec::new();
        let mut wind = 0i32;
        let mut start = 0.0f32;
        for (x, d) in xs {
            let was_in = if self.even_odd { wind & 1 != 0 } else { wind != 0 };
            wind += d;
            let is_in = if self.even_odd { wind & 1 != 0 } else { wind != 0 };
            if !was_in && is_in {
                start = x;
            } else if was_in && !is_in {
                let (a, b) = (start.max(x0), x.min(x1));
                if b > a {
                    match spans.last_mut() {
                        Some(l) if a <= l[1] => l[1] = l[1].max(b),
                        _ => spans.push([a, b]),
                    }
                }
            }
        }
        spans
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(cmds: u32, pts: u32) -> PathEntry {
        PathEntry { cmd_offset: 0, cmd_count: cmds, pt_offset: 0, pt_count: pts, flags: 0, miter_limit: 0.0, reserved: [0; 2] }
    }

    fn square() -> (Vec<u8>, Vec<f32>) {
        (
            vec![PATH_CMD_MOVE, PATH_CMD_LINE, PATH_CMD_LINE, PATH_CMD_LINE, PATH_CMD_CLOSE],
            vec![0.0, 0.0, 10.0, 0.0, 10.0, 10.0, 0.0, 10.0],
        )
    }

    #[test]
    fn decodes_a_square_with_bounds_and_defaults() {
        let (c, p) = square();
        let d = decode_entry(&entry(5, 4), &c, &p).unwrap();
        assert_eq!(d.segs.len(), 5);
        assert_eq!(d.bounds, [0.0, 0.0, 10.0, 10.0]);
        assert!(!d.even_odd);
        assert_eq!((d.cap, d.join, d.miter), (Cap::Butt, Join::Miter, 4.0));
    }

    #[test]
    fn decodes_flags_cap_join_and_miter() {
        let (c, p) = square();
        let mut e = entry(5, 4);
        e.flags = PATH_FLAG_EVEN_ODD | (1 << 1) | (2 << 3);
        e.miter_limit = 2.5;
        let d = decode_entry(&e, &c, &p).unwrap();
        assert!(d.even_odd);
        assert_eq!((d.cap, d.join, d.miter), (Cap::Round, Join::Bevel, 2.5));
        e.flags = 3 << 1;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
        e.flags = 1 << 5;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
        e.flags = 0;
        e.miter_limit = 0.5;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
        e.miter_limit = f32::NAN;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
    }

    #[test]
    fn rejects_malformed_streams() {
        let (c, p) = square();
        // Point count must match what the commands consume.
        assert_eq!(decode_entry(&entry(5, 3), &c, &p), Err(E_BAD_ARG));
        assert_eq!(decode_entry(&entry(5, 5), &c, &p), Err(E_BAD_ARG));
        // Out of range windows.
        let mut e = entry(5, 4);
        e.cmd_offset = 1;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
        let mut e = entry(5, 4);
        e.pt_offset = u32::MAX;
        assert_eq!(decode_entry(&e, &c, &p), Err(E_BAD_ARG));
        // Must start with a move; empty is invalid; unknown command; draw after close.
        assert_eq!(decode_entry(&entry(0, 0), &[], &[]), Err(E_BAD_ARG));
        assert_eq!(decode_entry(&entry(1, 1), &[PATH_CMD_LINE], &[0.0, 0.0]), Err(E_BAD_ARG));
        assert_eq!(decode_entry(&entry(1, 0), &[9], &[]), Err(E_BAD_ARG));
        let after_close = [PATH_CMD_MOVE, PATH_CMD_LINE, PATH_CMD_CLOSE, PATH_CMD_LINE];
        assert_eq!(decode_entry(&entry(4, 3), &after_close, &[0.0; 6]), Err(E_BAD_ARG));
        // A move may follow a close.
        let again = [PATH_CMD_MOVE, PATH_CMD_LINE, PATH_CMD_CLOSE, PATH_CMD_MOVE, PATH_CMD_LINE];
        assert!(decode_entry(&entry(5, 4), &again, &[0.0; 8]).is_ok());
        // Non-finite and huge coordinates.
        let (c, mut p) = square();
        p[2] = f32::INFINITY;
        assert_eq!(decode_entry(&entry(5, 4), &c, &p), Err(E_BAD_ARG));
        p[2] = 2.0e6;
        assert_eq!(decode_entry(&entry(5, 4), &c, &p), Err(E_BAD_ARG));
    }

    #[test]
    fn curves_consume_two_and_three_points() {
        let c = [PATH_CMD_MOVE, PATH_CMD_QUAD, PATH_CMD_CUBIC, PATH_CMD_CLOSE];
        let p: Vec<f32> = (0..12).map(|i| i as f32).collect();
        let d = decode_entry(&entry(4, 6), &c, &p).unwrap();
        assert!(matches!(d.segs[1], Seg::Quad(..)));
        assert!(matches!(d.segs[2], Seg::Cubic(..)));
        assert_eq!(d.bounds, [0.0, 1.0, 10.0, 10.0]);
    }

    #[test]
    fn table_limits_and_all_entries_validated() {
        let (c, p) = square();
        let good = entry(5, 4);
        let mut bad = entry(5, 4);
        bad.cmd_offset = 3;
        assert_eq!(decode_table(&[good, bad], &c, &p).err(), Some(E_BAD_ARG));
        let many = vec![good; MAX_PATHS as usize + 1];
        assert_eq!(decode_table(&many, &c, &p).err(), Some(E_TOO_LARGE));
        assert_eq!(decode_table(&[good, good], &c, &p).unwrap().len(), 2);
        assert!(decode_table(&[], &[], &[]).unwrap().is_empty());
    }

    #[test]
    fn two_entries_share_arrays_by_offset() {
        let c = [PATH_CMD_MOVE, PATH_CMD_LINE, PATH_CMD_LINE, PATH_CMD_MOVE, PATH_CMD_LINE];
        let p = [0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 5.0, 5.0, 6.0, 6.0];
        let a = PathEntry { cmd_offset: 0, cmd_count: 3, pt_offset: 0, pt_count: 3, ..Default::default() };
        let b = PathEntry { cmd_offset: 3, cmd_count: 2, pt_offset: 3, pt_count: 2, ..Default::default() };
        let t = decode_table(&[a, b], &c, &p).unwrap();
        assert_eq!(t[1].bounds, [5.0, 5.0, 1.0, 1.0]);
    }

    fn poly(points: &[[f32; 2]], even_odd: bool) -> PathData {
        let mut segs = vec![Seg::Move(points[0])];
        segs.extend(points[1..].iter().map(|p| Seg::Line(*p)));
        segs.push(Seg::Close);
        PathData { segs, even_odd, cap: Cap::Butt, join: Join::Miter, miter: 4.0, bounds: [0.0; 4] }
    }

    #[test]
    fn flatten_closes_and_keeps_subpaths() {
        let d = poly(&[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]], false);
        let f = d.flatten(0.1);
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].len(), 3);
        // A circle quadrant as a cubic stays within tolerance of the true radius.
        let k = 0.5522847498_f32 * 10.0;
        let q = PathData {
            segs: vec![Seg::Move([10.0, 0.0]), Seg::Cubic([10.0, k], [k, 10.0], [0.0, 10.0]), Seg::Close],
            even_odd: false,
            cap: Cap::Butt,
            join: Join::Miter,
            miter: 4.0,
            bounds: [0.0; 4],
        };
        let f = q.flatten(0.05);
        assert!(f[0].len() > 4);
        for p in &f[0][..f[0].len()] {
            let r = (p[0] * p[0] + p[1] * p[1]).sqrt();
            if p[0] > 0.0 && p[1] > 0.0 {
                assert!((r - 10.0).abs() < 0.06, "r = {r}");
            }
        }
    }

    #[test]
    fn cover_of_a_rectangle_is_one_rect() {
        let d = poly(&[[2.0, 3.0], [12.0, 3.0], [12.0, 9.0], [2.0, 9.0]], false);
        let r = d.cover_rects([0.0, 0.0, 20.0, 20.0], 1.0);
        assert_eq!(r, vec![[2.0, 3.0, 10.0, 6.0]]);
        // Clamped to the region.
        let r = d.cover_rects([4.0, 4.0, 4.0, 2.0], 1.0);
        assert_eq!(r, vec![[4.0, 4.0, 4.0, 2.0]]);
        // Outside the region entirely.
        assert!(d.cover_rects([30.0, 30.0, 5.0, 5.0], 1.0).is_empty());
    }

    #[test]
    fn cover_of_a_triangle_is_a_staircase_sampled_at_row_centres() {
        // Right triangle: x from 0 to y (apex at the origin), rows 0..4.
        let d = poly(&[[0.0, 0.0], [4.0, 4.0], [0.0, 4.0]], false);
        let r = d.cover_rects([0.0, 0.0, 4.0, 4.0], 1.0);
        // Row centres 0.5, 1.5, 2.5, 3.5: the span is [0, centre]... the hypotenuse is x = y, inside is x < y.
        assert_eq!(r.len(), 4);
        for (i, rect) in r.iter().enumerate() {
            assert_eq!(rect[1], i as f32);
            assert_eq!(rect[3], 1.0);
            assert_eq!(rect[0], 0.0);
            assert!((rect[2] - (i as f32 + 0.5)).abs() < 1e-5, "row {i}: {rect:?}");
        }
    }

    #[test]
    fn fill_rules_differ_on_nested_same_direction_squares() {
        let outer = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]];
        let inner = [[3.0, 3.0], [7.0, 3.0], [7.0, 7.0], [3.0, 7.0]];
        let mut segs = vec![];
        for sq in [outer, inner] {
            segs.push(Seg::Move(sq[0]));
            for p in &sq[1..] {
                segs.push(Seg::Line(*p));
            }
            segs.push(Seg::Close);
        }
        let mut d = PathData { segs, even_odd: false, cap: Cap::Butt, join: Join::Miter, miter: 4.0, bounds: [0.0; 4] };
        let nz = d.cover_rects([0.0, 0.0, 10.0, 10.0], 1.0);
        assert_eq!(nz, vec![[0.0, 0.0, 10.0, 10.0]]);
        d.even_odd = true;
        let eo = d.cover_rects([0.0, 0.0, 10.0, 10.0], 1.0);
        // The hole splits the middle rows into two spans.
        assert!(eo.contains(&[0.0, 3.0, 3.0, 4.0]));
        assert!(eo.contains(&[7.0, 3.0, 3.0, 4.0]));
        assert!(eo.contains(&[0.0, 0.0, 10.0, 3.0]));
        assert!(eo.contains(&[0.0, 7.0, 10.0, 3.0]));
    }

    #[test]
    fn cover_of_a_circle_is_symmetric_and_close_to_the_area() {
        let r = 20.0f32;
        let k = 0.5522847498_f32 * r;
        let (cx, cy) = (r, r);
        let segs = vec![
            Seg::Move([cx + r, cy]),
            Seg::Cubic([cx + r, cy + k], [cx + k, cy + r], [cx, cy + r]),
            Seg::Cubic([cx - k, cy + r], [cx - r, cy + k], [cx - r, cy]),
            Seg::Cubic([cx - r, cy - k], [cx - k, cy - r], [cx, cy - r]),
            Seg::Cubic([cx + k, cy - r], [cx + r, cy - k], [cx + r, cy]),
            Seg::Close,
        ];
        let d = PathData { segs, even_odd: false, cap: Cap::Butt, join: Join::Miter, miter: 4.0, bounds: [0.0; 4] };
        let rects = d.cover_rects([0.0, 0.0, 40.0, 40.0], 1.0);
        let area: f32 = rects.iter().map(|q| q[2] * q[3]).sum();
        let want = std::f32::consts::PI * r * r;
        assert!((area - want).abs() / want < 0.02, "area {area} vs {want}");
        for q in &rects {
            // Mirror symmetry about x = 20.
            assert!(((q[0] + q[2] / 2.0) - 20.0).abs() < 0.05);
        }
    }
}
