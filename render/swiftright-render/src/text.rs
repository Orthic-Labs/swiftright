//! Synchronous text measurement over GPUI's text system, retained shaped runs and the
//! cache. Measurement is read-only: it never calls the host, never touches GPUI app or
//! window borrows (it uses an independently retained `Arc<WindowTextSystem>`), and runs
//! on the UI thread only.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering::SeqCst};
use std::sync::Arc;

use gpui::{font, px, Font, FontFallbacks, FontFeatures, FontStyle, FontWeight, Hsla, Rgba, SharedString, TextRun, WindowTextSystem, WrappedLine};

use crate::abi::*;

pub const MAX_RUNS: usize = 65536;
pub const CACHE_CAP: usize = 512;
/// #34: the cache is also bounded in bytes. Each entry is sized by its whole text (the text, one cell per character, the shaped
/// glyphs), so a field that grows by one character per edit adds an entry per edit sized by the whole field; a count cap alone
/// then retains CACHE_CAP x the field. The cache clears when the next entry would pass CACHE_BYTES, and an entry larger than
/// CACHE_ENTRY_MAX is returned uncached (measured again on its next use).
pub const CACHE_BYTES: usize = 8 << 20;
pub const CACHE_ENTRY_MAX: usize = CACHE_BYTES / 4;
/// Estimated bytes one measurement retains per character: its CharCell, its shaped glyph (id, position, cluster) and line bookkeeping.
pub const RETAINED_PER_CHAR: usize = 128;

/// A shaped, wrapped run plus plain per-character geometry. Rev 0.6: the text may hold
/// '\n'; each paragraph is one GPUI `WrappedLine` stacked below the previous one, and the
/// '\n' is a zero-width cell (`CELL_LINE_BREAK`) ending the visual line it terminates.
/// Geometry is physical px (logical shaping x `scale`).
pub struct Measured {
    pub text: String,
    /// One entry per paragraph: the shaped paragraph and its top in run-local physical px.
    pub wrapped: Vec<(WrappedLine, f32)>,
    pub cells: Vec<CharCell>,
    pub lines: Vec<LineInfo>,
    pub width: f32,
    pub height: f32,
    pub first_baseline: f32,
    pub last_baseline: f32,
    pub line_height_dip: f32,
    pub scale: f32,
    /// Rev 0.10: GPUI logical px per host DIP-at-scale, `S / G` under an explicit render scale, exactly 1.0 otherwise. Line
    /// height and tracking handed to GPUI at paint time are multiplied by it (shaping used the same factor).
    pub gpui_ratio: f32,
    pub char_count: u32,
    pub key: u64,
    /// Rev 0.12: the request text when `text` is its max-lines truncation (cache lookups compare against the request).
    pub src: Option<String>,
    /// Rev 0.8: what the face resolver decided and what the shaper produced, for painting and `swr_text_run_faces`.
    pub ext: MeasuredExt,
}

/// One shaped sub-run (same gpui font id) of a `Measured` text, recorded at shaping time.
#[derive(Clone, Debug, Default)]
pub struct RunRec {
    pub font_id: usize,
    /// The run is drawn with the requested family. gpui reports a run's font id by FACE identity (postscript name, weight, style),
    /// which may be an id another request created, so ids are not compared: `TextSystem::get_font_for_id` gives the requested
    /// Font behind an id (None for a face gpui picked by fallback, F0 trace) and its family is compared with the request's.
    pub primary: bool,
    /// The family of the requested Font behind this run's font id, if there is one.
    pub req_family: Option<String>,
    /// Byte range in the run text.
    pub utf8_start: u32,
    pub utf8_len: u32,
    pub glyphs: u32,
    /// Glyphs with id 0 (.notdef).
    pub notdef: u32,
    pub emoji: bool,
    pub advance_px: f32,
    pub ascent_px: f32,
    pub descent_px: f32,
    /// First character of the sub-run and its glyph id, to name a fallback face.
    pub first_char: u32,
    pub first_gid: u32,
}

/// The face request behind a run (rev 0.8; the 0.6 path leaves the defaults).
#[derive(Clone, Debug, Default)]
pub struct FaceReq {
    pub family: String,
    /// The weight handed to gpui and the italic flag it got.
    pub weight: f32,
    pub italic: bool,
    /// SIMFLAG_* the shaper applies to the primary face (predicted by the policy).
    pub sim: u32,
    /// System fallback families the shaper was given.
    pub fallbacks: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct MeasuredExt {
    pub runs: Vec<RunRec>,
    pub face: FaceReq,
    /// tracking + kerning, DIP added after every glyph cluster; 0 paints through `WrappedLine::paint` as before.
    pub track_dip: f32,
    /// 0xRRGGBBAA, for glyph-positioned painting.
    pub color: u32,
    pub font_size: f32,
    /// Mac multi-line rule (G75b): every visual line is painted at its reported (snapped) top instead of advancing by the line height.
    pub mac_lines: bool,
}

/// Generation-tagged slab of retained, owner-freed objects (shaped runs, images). Handle:
/// low 32 bits slot + 1, high 32 bits generation (>= 1); 0 is never valid. `live` mirrors
/// the number of occupied slots for swr_stats.live_nodes.
pub struct Slab<T> {
    slots: Vec<(u32, Option<Arc<T>>)>,
    live: &'static AtomicU64,
    max: usize,
}

pub type RunSlab = Slab<Measured>;

/// A registered image. `LIVE_IMAGES` counts it from creation until the last reference
/// (host handle or committed node) is dropped, so the gauge falls only when it is freed.
pub struct TrackedImage {
    pub img: Arc<gpui::RenderImage>,
}

impl TrackedImage {
    pub fn new(img: gpui::RenderImage) -> TrackedImage {
        crate::rt::LIVE_IMAGES.fetch_add(1, SeqCst);
        TrackedImage { img: Arc::new(img) }
    }
}

impl Drop for TrackedImage {
    fn drop(&mut self) {
        crate::rt::LIVE_IMAGES.fetch_sub(1, SeqCst);
    }
}

impl<T> Slab<T> {
    pub fn new(live: &'static AtomicU64, max: usize) -> Slab<T> {
        Slab { slots: Vec::new(), live, max }
    }

    pub fn insert(&mut self, m: Arc<T>) -> Result<u64, Status> {
        let slot = match self.slots.iter().position(|s| s.1.is_none()) {
            Some(i) => i,
            None => {
                if self.slots.len() >= self.max {
                    return Err(E_TOO_LARGE);
                }
                self.slots.push((1, None));
                self.slots.len() - 1
            }
        };
        self.slots[slot].1 = Some(m);
        self.live.fetch_add(1, SeqCst);
        Ok(((self.slots[slot].0 as u64) << 32) | (slot as u64 + 1))
    }

    fn locate(&self, h: u64) -> Option<usize> {
        let low = (h & 0xFFFF_FFFF) as usize;
        let gen = (h >> 32) as u32;
        if low == 0 || gen == 0 || low > self.slots.len() {
            return None;
        }
        let slot = low - 1;
        if self.slots[slot].0 == gen && self.slots[slot].1.is_some() {
            Some(slot)
        } else {
            None
        }
    }

    pub fn get(&self, h: u64) -> Option<Arc<T>> {
        self.locate(h).and_then(|s| self.slots[s].1.clone())
    }

    /// Releases the handle; the removed object is returned so the caller can finish with it.
    pub fn take(&mut self, h: u64) -> Option<Arc<T>> {
        let s = self.locate(h)?;
        self.retire(s)
    }

    pub fn release(&mut self, h: u64) -> Status {
        match self.take(h) {
            None => E_STALE_HANDLE,
            Some(_) => SWR_OK,
        }
    }

    /// Drops every live object (window closed: the owner died). Each dropped handle's
    /// generation advances, so a later release fails with SWR_E_STALE_HANDLE. Returns them.
    pub fn clear(&mut self) -> Vec<Arc<T>> {
        let mut out = Vec::new();
        for s in 0..self.slots.len() {
            if let Some(a) = self.retire(s) {
                out.push(a);
            }
        }
        out
    }

    fn retire(&mut self, s: usize) -> Option<Arc<T>> {
        let old = self.slots[s].1.take()?;
        let mut g = self.slots[s].0.wrapping_add(1);
        if g == 0 {
            g = 1;
        }
        self.slots[s].0 = g;
        self.live.fetch_sub(1, SeqCst);
        Some(old)
    }
}

/// Rev 0.8 request extension, already validated and resolved by the face policy (src/faces.rs).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Ext {
    /// The weight gpui is asked for (a named instance, or the raw request when a simulation is wanted).
    pub weight: f32,
    pub italic: bool,
    /// SIMFLAG_* predicted by the policy.
    pub sim: u32,
    pub features: Vec<(String, u32)>,
    /// System families only.
    pub fallbacks: Vec<String>,
    /// tracking_dip + kerning_dip.
    pub track_dip: f32,
    /// The face's baseline this far below the line top, DIP.
    pub baseline_dip: Option<f32>,
    /// Rev 0.12: at most this many visual lines; longer text ends in an ellipsis. 0 = unlimited.
    pub max_lines: u32,
}

pub struct Request<'a> {
    pub ext: Option<&'a Ext>,
    pub text: &'a str,
    pub family: &'a str,
    pub locale: &'a str,
    pub weight: u32,
    pub direction: u32,
    pub color: u32,
    pub font_size: f32,
    pub line_height: f32,
    pub scale: f32,
    pub max_width: f32,
    /// Rev 0.10: see `Measured::gpui_ratio`. 1.0 without an explicit render scale.
    pub gpui_ratio: f32,
}

pub fn cache_key(r: &Request) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    r.text.hash(&mut h);
    r.family.hash(&mut h);
    r.locale.hash(&mut h);
    r.weight.hash(&mut h);
    r.direction.hash(&mut h);
    r.color.hash(&mut h);
    r.font_size.to_bits().hash(&mut h);
    r.line_height.to_bits().hash(&mut h);
    r.scale.to_bits().hash(&mut h);
    // Rev 0.10: a different S / G ratio is a different shaping. Hashed only when it is not 1, so every key without an override is
    // exactly what it was.
    if r.gpui_ratio != 1.0 {
        r.gpui_ratio.to_bits().hash(&mut h);
    }
    r.max_width.max(0.0).to_bits().hash(&mut h);
    // Rev 0.8: a request with an extension is a different shaping; a 0.6 request keeps its 0.6 key.
    if let Some(e) = r.ext {
        1u8.hash(&mut h);
        e.weight.to_bits().hash(&mut h);
        e.italic.hash(&mut h);
        e.sim.hash(&mut h);
        e.features.hash(&mut h);
        e.fallbacks.hash(&mut h);
        e.track_dip.to_bits().hash(&mut h);
        e.baseline_dip.map(f32::to_bits).hash(&mut h);
        if e.max_lines > 0 {
            e.max_lines.hash(&mut h);
        }
    }
    h.finish()
}

fn is_wide(c: char) -> bool {
    (c as u32) >= 0x3000
}

fn word_starts_of(chars: &[char]) -> Vec<bool> {
    (0..chars.len())
        .map(|i| {
            let c = chars[i];
            if c.is_whitespace() {
                false
            } else if i == 0 {
                true
            } else {
                let p = chars[i - 1];
                p.is_whitespace() || is_wide(c) || is_wide(p)
            }
        })
        .collect()
}

/// What a cache entry retains, in bytes (an estimate; see RETAINED_PER_CHAR).
pub trait Retained {
    fn retained_bytes(&self) -> usize;
    fn cached_text(&self) -> &str;
}

impl Retained for Measured {
    fn retained_bytes(&self) -> usize {
        self.text.len() + (self.char_count as usize + 1) * RETAINED_PER_CHAR
    }
    fn cached_text(&self) -> &str {
        self.src.as_deref().unwrap_or(&self.text)
    }
}

pub struct TextCacheOf<T: Retained> {
    map: HashMap<u64, Arc<T>>,
    bytes: usize,
}

pub type TextCache = TextCacheOf<Measured>;

impl<T: Retained> TextCacheOf<T> {
    pub fn new() -> Self {
        TextCacheOf { map: HashMap::new(), bytes: 0 }
    }

    pub fn get(&self, key: u64, text: &str) -> Option<Arc<T>> {
        self.map.get(&key).filter(|m| m.cached_text() == text).cloned()
    }

    /// Drops every cached shaping (a registered font changes what a family resolves to).
    pub fn clear(&mut self) {
        self.map.clear();
        self.bytes = 0;
    }

    pub fn put(&mut self, key: u64, m: Arc<T>) {
        let b = m.retained_bytes();
        if b > CACHE_ENTRY_MAX {
            return;
        }
        if self.map.len() >= CACHE_CAP || self.bytes + b > CACHE_BYTES {
            self.clear();
        }
        if let Some(old) = self.map.insert(key, m) {
            self.bytes -= old.retained_bytes();
        }
        self.bytes += b;
    }

    /// Estimated retained bytes (never above CACHE_BYTES).
    pub fn bytes(&self) -> usize {
        self.bytes
    }

    pub fn len(&self) -> usize {
        self.map.len()
    }
}

/// Baseline placement matching CoreText/SwiftUI `Text` (measured on macOS: baseline = round(ascent) DIP below the line top at every
/// scale; the font's leading is not placed above the text). Returns (baseline offset inside a line box in px, paint-origin shift in px):
/// GPUI paints the baseline at half-leading + ascent, so the shift moves it to round(ascent).
pub(crate) fn baseline_placement(line_height: f32, ascent: f32, descent: f32, ct_ascent: f32, scale: f32) -> (f32, f32) {
    let target = ct_ascent.round();
    let gpui = (line_height - (ascent + descent)) / 2.0 + ascent;
    (target * scale, (target - gpui) * scale)
}

/// The gpui `Font` of a request. Rev 0.8: weight, italic, OpenType features (the host sends kern=1 on every Windows run: gpui
/// leaves kerning off by default, G15) and system fallback families go through unchanged.
pub fn build_font(r: &Request) -> Font {
    let mut f = font(r.family.to_string());
    f.weight = FontWeight(r.weight as f32);
    if let Some(e) = r.ext {
        f.weight = FontWeight(e.weight);
        if e.italic {
            f.style = FontStyle::Italic;
        }
        if !e.features.is_empty() {
            f.features = FontFeatures(Arc::new(e.features.clone()));
        }
        if !e.fallbacks.is_empty() {
            f.fallbacks = Some(FontFallbacks::from_fonts(e.fallbacks.clone()));
        }
    }
    f
}

/// Baseline placement with a host-supplied baseline (rev 0.8 `baseline_offset_dip`): no rounding, the number is the baseline.
pub(crate) fn exact_baseline_placement(line_height: f32, ascent: f32, descent: f32, target_dip: f32, scale: f32) -> (f32, f32) {
    let gpui = (line_height - (ascent + descent)) / 2.0 + ascent;
    (target_dip * scale, (target_dip - gpui) * scale)
}

/// Mac (CoreText/SwiftUI) multi-line Text pitch (decision G75b). SwiftUI's block height is `round(n x pitch)` rounded once (12 pt at 2.5x: pitch 37.5 px,
/// 1 line 38, 2 lines 75, 3 lines 113) and line k's baseline sits `round-half-up(k x pitch)` px below the first (measured, frame-centring-facts-b-v1:
/// 12 pt lineLimit 2: +38 px; lineLimit 3: +75 px over two advances). The host sends the pitch as `line_height` together with a
/// `baseline_dip` (system fonts only); a request without one keeps the plain `n x line_px` stacking. `MeasuredExt::mac_lines` makes the
/// painter place every visual line at its reported top.
pub(crate) fn mac_round(v: f32, mac: bool) -> f32 {
    if mac { (v + 0.5).floor() } else { v }
}

/// Height in px of an `n` line block whose line pitch is `line_px`.
pub(crate) fn block_height_px(n: usize, line_px: f32, mac: bool) -> f32 {
    mac_round(n as f32 * line_px, mac)
}

/// Top in px of line `k` (0 based) of a block whose line pitch is `line_px` (half-up snapped under the Mac rule).
pub(crate) fn line_top_px(k: usize, line_px: f32, mac: bool) -> f32 {
    mac_round(k as f32 * line_px, mac)
}

/// Offsets in px of the `n` visual lines of the paragraph starting at global line `base`, from that paragraph's own top, taken from the
/// reported line tops (a missing top falls back to the plain `j x line_px` advance).
pub(crate) fn paragraph_line_offsets(tops: &[f32], base: usize, n: usize, line_px: f32) -> Vec<f32> {
    let t0 = tops.get(base).copied().unwrap_or(0.0);
    (0..n).map(|j| tops.get(base + j).map_or(j as f32 * line_px, |t| t - t0)).collect()
}

/// Ordinal of the glyph cluster that contains byte `b`, given the sorted unique cluster start offsets of a paragraph.
pub(crate) fn cluster_ordinal(starts: &[usize], b: usize) -> usize {
    starts.partition_point(|&s| s <= b).saturating_sub(1)
}

/// The id of a gpui `GlyphId` (its field is crate private; Debug prints `GlyphId(n)`).
fn glyph_id_of(g: &gpui::ShapedGlyph) -> u32 {
    format!("{:?}", g.id).trim_start_matches("GlyphId(").trim_end_matches(')').parse().unwrap_or(0)
}

/// Ellipsis appended by max-lines truncation.
pub const ELLIPSIS: char = '\u{2026}';

/// Text kept before the ellipsis when `text` runs past `n` visual lines: everything up to the end of line `n`, trailing whitespace
/// dropped. `line_ends` are the byte ends of the visual lines (a paragraph's newline belongs to the line it ends). None when the
/// text already fits.
pub(crate) fn limit_prefix(text: &str, line_ends: &[usize], n: usize) -> Option<String> {
    if n == 0 || line_ends.len() <= n {
        return None;
    }
    let end = line_ends[n - 1].min(text.len());
    Some(text[..end].trim_end().to_string())
}

/// `kept` minus its last character and any whitespace before it.
pub(crate) fn shrink_prefix(kept: &str) -> String {
    let mut s = kept.to_string();
    s.pop();
    s.truncate(s.trim_end().len());
    s
}

/// Byte offsets (char boundaries) from `lo` to the end of `text`, ascending: the candidate cut points of the last kept line.
pub(crate) fn cut_points(text: &str, lo: usize) -> Vec<usize> {
    let lo = lo.min(text.len());
    let mut v: Vec<usize> = text.char_indices().map(|(i, _)| i).filter(|&i| i >= lo).collect();
    v.push(text.len());
    v.dedup();
    v
}

/// The largest index `i` in `0..len` with `fits(i)` true, assuming `fits` is true up to some index and false after it; None when
/// `fits(0)` is false.
pub(crate) fn last_fitting(len: usize, mut fits: impl FnMut(usize) -> Result<bool, Status>) -> Result<Option<usize>, Status> {
    if len == 0 || !fits(0)? {
        return Ok(None);
    }
    let (mut ok, mut bad) = (0usize, len);
    while bad - ok > 1 {
        let mid = ok + (bad - ok) / 2;
        if fits(mid)? { ok = mid } else { bad = mid }
    }
    Ok(Some(ok))
}

/// `shape_once`, then, under `ext.max_lines`, CoreText-style tail truncation (#51): lines 1..n-1 wrap as usual and the last kept
/// line takes as many characters of the rest of the text as fit with the ellipsis (not just the words that wrapped onto it).
pub fn shape(ts: &WindowTextSystem, r: &Request, key: u64) -> Result<Measured, Status> {
    let n = r.ext.map_or(0, |e| e.max_lines) as usize;
    let full = shape_once(ts, r, key)?;
    if n == 0 || full.lines.len() <= n {
        return Ok(full);
    }
    let ends: Vec<usize> = full.lines.iter().map(|l| (l.utf8_start + l.utf8_len) as usize).collect();
    let shape_cut = |cut: usize| -> Result<Measured, Status> {
        let kept = r.text[..cut].trim_end();
        let cand = format!("{kept}{ELLIPSIS}");
        let q = Request {
            ext: r.ext,
            text: &cand,
            family: r.family,
            locale: r.locale,
            weight: r.weight,
            direction: r.direction,
            color: r.color,
            font_size: r.font_size,
            line_height: r.line_height,
            scale: r.scale,
            max_width: r.max_width,
            gpui_ratio: r.gpui_ratio,
        };
        shape_once(ts, &q, key)
    };
    // The last kept line starts where line n starts in the full layout; a paragraph break inside it ends the kept text there.
    let lo = if n >= 2 { ends[n - 2] } else { 0 };
    let mut hi = r.text.len();
    if let Some(nl) = r.text[lo..].find('\n') {
        hi = lo + nl;
    }
    let cuts = cut_points(&r.text[..hi], lo);
    let best = last_fitting(cuts.len(), |i| Ok(shape_cut(cuts[i])?.lines.len() <= n))?;
    let cut = match best {
        Some(i) => cuts[i],
        None => {
            // Not even the ellipsis fits after the wrapped lines: fall back to dropping characters from the whole-line prefix.
            let mut kept = limit_prefix(r.text, &ends, n).unwrap_or_default();
            for _ in 0..512 {
                if kept.is_empty() || shape_cut(kept.len())?.lines.len() <= n {
                    break;
                }
                kept = shrink_prefix(&kept);
            }
            kept.len()
        }
    };
    let mut m = shape_cut(cut)?;
    m.src = Some(r.text.to_string());
    Ok(m)
}

/// Shapes `r.text` with GPUI's text system. Rev 0.6: '\n' splits paragraphs.
fn shape_once(ts: &WindowTextSystem, r: &Request, key: u64) -> Result<Measured, Status> {
    let scale = r.scale;
    // Rev 0.10: `k` = S / G (1.0 without an explicit render scale). GPUI shapes at `font_size * k` logical px and turns logical into
    // device px with G = S / k, so every layout value it returns converts to physical px with `g`, and every host-facing DIP value
    // (line height, tracking, baselines) keeps `scale`. With k == 1.0, g == scale and nothing below changes.
    let k = r.gpui_ratio;
    let g = scale / k;
    let lh = r.line_height;
    let line_px = lh * scale;
    let mac = r.ext.map_or(false, |e| e.baseline_dip.is_some());
    let chars: Vec<char> = r.text.chars().collect();

    if r.text.is_empty() {
        let empty_baseline = r.ext.and_then(|e| e.baseline_dip).map_or(lh * scale * 0.8, |b| b * scale);
        return Ok(Measured {
            text: String::new(),
            wrapped: Vec::new(),
            cells: Vec::new(),
            lines: vec![LineInfo {
                utf8_start: 0,
                utf8_len: 0,
                width: 0.0,
                top: 0.0,
                baseline: empty_baseline,
                reserved: 0.0,
            }],
            width: 0.0,
            height: block_height_px(1, line_px, mac),
            first_baseline: empty_baseline,
            last_baseline: empty_baseline,
            line_height_dip: lh,
            scale,
            gpui_ratio: k,
            char_count: 0,
            key,
            src: None,
            ext: MeasuredExt { track_dip: r.ext.map_or(0.0, |e| e.track_dip), color: r.color, font_size: r.font_size, face: face_req(r), ..Default::default() },
        });
    }

    let f = build_font(r);
    let color: Hsla = Rgba::from(gpui::rgba(r.color)).into();
    let run = TextRun {
        len: r.text.len(),
        font: f,
        color,
        background_color: None,
        underline: None,
        strikethrough: None,
    };
    let wrap = if r.max_width > 0.0 {
        Some(px(r.max_width / g))
    } else {
        None
    };
    let shaped = ts
        .shape_text(SharedString::from(r.text.to_string()), px(r.font_size * k), &[run], wrap, None)
        .map_err(|_| E_PLATFORM)?;
    let paragraph_texts: Vec<&str> = r.text.split('\n').collect();
    if shaped.len() != paragraph_texts.len() {
        return Err(E_PLATFORM);
    }

    let ws = word_starts_of(&chars);
    let mut cells: Vec<CharCell> = Vec::with_capacity(chars.len());
    let mut infos: Vec<LineInfo> = Vec::new();
    let mut wrapped: Vec<(WrappedLine, f32)> = Vec::with_capacity(shaped.len());
    let mut asc_desc: Option<(f32, f32)> = None;
    let mut width = 0f32;
    let mut char_ix = 0usize; // index into `chars` / `ws`
    let mut para_base = 0usize; // byte offset of the paragraph start in r.text
    let n_para = shaped.len();
    let mut line_base = 0usize; // visual lines before this paragraph

    struct Pending {
        first: usize,
        end: usize,
        width: f32,
        is_para_last: bool,
        has_break: bool,
    }
    let mut pend: Vec<Pending> = Vec::new();
    let t_px = r.ext.map_or(0.0, |e| e.track_dip) * scale; // tracking + kerning, physical px per glyph cluster
    let mut run_recs: Vec<RunRec> = Vec::new();

    for (pi, wl) in shaped.into_iter().enumerate() {
        let ptext = paragraph_texts[pi];
        let layout = wl.unwrapped_layout.clone();
        if asc_desc.is_none() && !ptext.is_empty() {
            // DIP units: GPUI shaped at `font_size * k`, so its ascent and descent are k times the host's.
            asc_desc = Some((f32::from(layout.ascent) / k, f32::from(layout.descent) / k));
        }
        // Rev 0.8: glyph cluster starts (tracking is added per cluster) and one record per shaped sub-run (same gpui font id).
        let mut cluster_starts: Vec<usize> = layout.runs.iter().flat_map(|run| run.glyphs.iter().map(|g| g.index)).collect();
        cluster_starts.sort_unstable();
        cluster_starts.dedup();
        for (ri, run) in layout.runs.iter().enumerate() {
            let Some(first) = run.glyphs.first() else { continue };
            let next_x = layout
                .runs
                .get(ri + 1)
                .and_then(|n| n.glyphs.first())
                .map_or(f32::from(layout.width), |g| f32::from(g.position.x));
            let lo = run.glyphs.iter().map(|g| g.index).min().unwrap_or(0);
            let hi = run.glyphs.iter().map(|g| g.index).max().unwrap_or(0);
            let hi_len = ptext.get(hi..).and_then(|t| t.chars().next()).map_or(1, |c| c.len_utf8());
            let req_family = ts.get_font_for_id(run.font_id).map(|f| f.family.to_string());
            run_recs.push(RunRec {
                font_id: run.font_id.0,
                primary: req_family.as_deref().map_or(false, |f| f.eq_ignore_ascii_case(r.family)),
                req_family,
                utf8_start: (para_base + lo) as u32,
                utf8_len: (hi + hi_len - lo) as u32,
                glyphs: run.glyphs.len() as u32,
                notdef: run.glyphs.iter().filter(|g| glyph_id_of(g) == 0).count() as u32,
                emoji: run.glyphs.iter().any(|g| g.is_emoji),
                advance_px: (next_x - f32::from(first.position.x)) * g,
                ascent_px: f32::from(ts.ascent(run.font_id, layout.font_size)) * g,
                descent_px: f32::from(ts.descent(run.font_id, layout.font_size)) * g,
                first_char: ptext.get(first.index..).and_then(|t| t.chars().next()).map_or(0, |c| c as u32),
                first_gid: glyph_id_of(first),
            });
        }

        // GPUI convention: each wrap-boundary glyph is the first glyph of the next visual line.
        let mut starts = vec![0usize];
        for b in wl.wrap_boundaries.iter() {
            starts.push(layout.runs[b.run_ix].glyphs[b.glyph_ix].index);
        }

        let mut line_first_byte: Vec<usize> = Vec::new();
        let mut line_start_x: Vec<f32> = Vec::new();
        let mut line_end_byte: Vec<usize> = Vec::new();
        let mut line_width: Vec<f32> = Vec::new();
        let mut byte = 0usize;
        for ch in ptext.chars() {
            let len = ch.len_utf8();
            let line = starts.iter().rposition(|&s| s <= byte).unwrap_or(0);
            while line_first_byte.len() <= line {
                line_first_byte.push(byte);
                line_start_x.push(f32::from(layout.x_for_index(byte)));
                line_end_byte.push(byte);
                line_width.push(0.0);
            }
            let xs = line_start_x[line];
            // Tracking: every cluster before this one on the visual line moved by t_px; this cluster's cell includes its own.
            let n_before = cluster_ordinal(&cluster_starts, byte).saturating_sub(cluster_ordinal(&cluster_starts, line_first_byte[line])) as f32;
            let x0 = (f32::from(layout.x_for_index(byte)) - xs) * g + t_px * n_before;
            let x1 = (f32::from(layout.x_for_index(byte + len)) - xs) * g + t_px * (n_before + 1.0);
            if x1 > line_width[line] {
                line_width[line] = x1;
            }
            line_end_byte[line] = byte + len;
            cells.push(CharCell {
                utf8_offset: (para_base + byte) as u32,
                utf8_len: len as u32,
                line: (line_base + line) as u32,
                flags: if ws[char_ix] { CELL_WORD_START } else { 0 },
                x0,
                x1,
            });
            char_ix += 1;
            byte += len;
        }
        if line_first_byte.is_empty() {
            // Empty paragraph: one empty visual line.
            line_first_byte.push(0);
            line_start_x.push(0.0);
            line_end_byte.push(0);
            line_width.push(0.0);
        }
        let n_local = line_first_byte.len();
        let is_last_para = pi + 1 == n_para;
        if !is_last_para {
            // The '\n': a zero-width cell at the end of the paragraph's last visual line.
            let last = n_local - 1;
            cells.push(CharCell {
                utf8_offset: (para_base + ptext.len()) as u32,
                utf8_len: 1,
                line: (line_base + last) as u32,
                flags: CELL_LINE_BREAK,
                x0: line_width[last],
                x1: line_width[last],
            });
            char_ix += 1;
        }
        for k in 0..n_local {
            width = width.max(line_width[k]);
            pend.push(Pending {
                first: para_base + line_first_byte[k],
                end: para_base + line_end_byte[k],
                width: line_width[k],
                is_para_last: k + 1 == n_local,
                has_break: !is_last_para,
            });
        }
        wrapped.push((wl, line_top_px(line_base, line_px, mac)));
        line_base += n_local;
        para_base += ptext.len() + 1;
    }

    // CoreText / SwiftUI Text: the baseline sits at the (DIP-rounded) ascent below the line top and any extra leading goes
    // below the descent. GPUI paints with half-leading above the text, so the paint origin is shifted to compensate.
    let (baseline_in_line, paint_dy) = match asc_desc {
        Some((ascent, descent)) => {
            // CoreText's ascent: the face's hhea ascent for a registered (bundled) font. GPUI/DirectWrite's own ascent differs
            // (Tinos: 17 DIP vs 16.04), so it only describes where GPUI paints, never where the baseline must land.
            let ct_ascent = crate::font::REGISTRY
                .lock()
                .ok()
                .and_then(|reg| reg.hhea_em(r.family))
                .map(|(a, _)| a * r.font_size)
                .unwrap_or(ascent);
            match r.ext.and_then(|e| e.baseline_dip) {
                // A host-supplied baseline is the baseline, not rounded and not derived from the face.
                Some(target) => exact_baseline_placement(lh, ascent, descent, target, scale),
                None => baseline_placement(lh, ascent, descent, ct_ascent, scale),
            }
        }
        None => (r.ext.and_then(|e| e.baseline_dip).map_or(lh * scale * 0.8, |b| b * scale), 0.0),
    };
    if paint_dy != 0.0 {
        for (_, top) in wrapped.iter_mut() {
            *top += paint_dy;
        }
    }
    let n_lines = pend.len().max(1);
    for (k, p) in pend.iter().enumerate() {
        // The '\n' belongs to the line it terminates, so lines partition the text.
        let extra = if p.is_para_last && p.has_break { 1 } else { 0 };
        infos.push(LineInfo {
            utf8_start: p.first as u32,
            utf8_len: (p.end - p.first + extra) as u32,
            width: p.width,
            top: line_top_px(k, line_px, mac),
            baseline: line_top_px(k, line_px, mac) + baseline_in_line,
            reserved: 0.0,
        });
    }
    Ok(Measured {
        text: r.text.to_string(),
        wrapped,
        cells,
        width,
        height: block_height_px(n_lines, line_px, mac),
        first_baseline: baseline_in_line,
        last_baseline: line_top_px(n_lines - 1, line_px, mac) + baseline_in_line,
        lines: infos,
        line_height_dip: lh,
        scale,
        gpui_ratio: k,
        char_count: chars.len() as u32,
        key,
        src: None,
        ext: MeasuredExt {
            runs: run_recs,
            face: face_req(r),
            track_dip: r.ext.map_or(0.0, |e| e.track_dip),
            color: r.color,
            font_size: r.font_size,
            mac_lines: mac,
        },
    })
}

fn face_req(r: &Request) -> FaceReq {
    match r.ext {
        Some(e) => FaceReq { family: r.family.to_string(), weight: e.weight, italic: e.italic, sim: e.sim, fallbacks: e.fallbacks.clone() },
        None => FaceReq { family: r.family.to_string(), weight: r.weight as f32, italic: false, sim: 0, fallbacks: Vec::new() },
    }
}

#[cfg(test)]
mod baseline_tests {
    use super::baseline_placement;

    #[test]
    fn baseline_is_rounded_ascent_from_line_top() {
        // Tinos 18 DIP at 2.5x: asc 16.04, desc 3.89, host line height 20 (round(asc)+round(desc)); CoreText baseline = 16 DIP = 40 px.
        let (b, dy) = baseline_placement(20.0, 16.0400391, 3.8935547, 16.0400391, 2.5);
        assert_eq!(b, 40.0);
        // GPUI baseline = 0.0332 + 16.04 = 16.0732 DIP; the shift lands it on 16 DIP.
        assert!(((16.0732 * 2.5) + dy - 40.0).abs() < 0.01);
    }

    #[test]
    fn font_gap_in_line_height_goes_below_the_text() {
        // Line height with the 0.76 DIP gap included: baseline still at the ascent, not half a gap lower.
        let (b, dy) = baseline_placement(20.698242, 16.0400391, 3.8935547, 16.0400391, 2.5);
        assert_eq!(b, 40.0);
        assert!(dy < 0.0);
        let gpui_baseline_px = ((20.698242 - 19.9335938) / 2.0 + 16.0400391) * 2.5;
        assert!((gpui_baseline_px + dy - 40.0).abs() < 0.01);
    }

    #[test]
    fn rounds_to_nearest_dip() {
        assert_eq!(baseline_placement(15.0, 11.5845, 2.812, 11.5845, 2.5).0, 30.0);
        assert_eq!(baseline_placement(20.0, 38.67, 8.44, 38.67, 1.0).0, 39.0);
    }
}

#[cfg(test)]
mod baseline_gpui_ascent_tests {
    use super::baseline_placement;

    #[test]
    fn gpui_ascent_larger_than_coretext_is_compensated() {
        // DirectWrite/GPUI ascent 17 DIP, CoreText 16.04: the baseline still lands at 16 DIP = 40 px.
        let (b, dy) = baseline_placement(20.0, 17.0, 3.8935547, 16.0400391, 2.5);
        assert_eq!(b, 40.0);
        let gpui_px = ((20.0 - 20.8935547) / 2.0 + 17.0) * 2.5;
        assert!((gpui_px + dy - 40.0).abs() < 0.01);
    }
}

#[cfg(test)]
mod mac_block_tests {
    use super::{block_height_px, line_top_px, paragraph_line_offsets};

    #[test]
    fn mac_block_is_rounded_once_from_the_pitch() {
        // 12 pt system font at 2.5x: pitch 15 DIP = 37.5 px. Mac textH 15.2 / 30.0 / 45.2 pt = 38 / 75 / 113 px.
        let p = 15.0 * 2.5;
        assert_eq!(block_height_px(1, p, true), 38.0);
        assert_eq!(block_height_px(2, p, true), 75.0);
        assert_eq!(block_height_px(3, p, true), 113.0);
        // The Windows stacking of the 38 px single-line height (76, 114) is kept without a host baseline.
        assert_eq!(block_height_px(2, 38.0, false), 76.0);
        assert_eq!(block_height_px(3, 38.0, false), 114.0);
    }

    #[test]
    fn mac_line_tops_are_the_measured_snapped_baseline_advances() {
        // Measured on the Mac (12 pt, 2.5x): lineLimit 2 baselines 15.2 pt = 38 px apart; lineLimit 3 two advances = 30.0 pt = 75 px.
        assert_eq!(line_top_px(0, 37.5, true), 0.0);
        assert_eq!(line_top_px(1, 37.5, true), 38.0);
        assert_eq!(line_top_px(2, 37.5, true), 75.0);
        assert_eq!(line_top_px(3, 37.5, true), 113.0);
        // last baseline = first + round-half-up((n - 1) x pitch): 38 px for 2 lines, 75 px for 3
        // The non-Mac path keeps the plain stacking.
        assert_eq!(line_top_px(1, 38.0, false), 38.0);
        assert_eq!(line_top_px(2, 37.5, false), 75.0);
        assert_eq!(line_top_px(1, 37.5, false), 37.5);
    }

    #[test]
    fn paragraph_offsets_come_from_the_reported_tops() {
        let tops = [0.0, 38.0, 75.0, 113.0];
        assert_eq!(paragraph_line_offsets(&tops, 0, 3, 37.5), vec![0.0, 38.0, 75.0]);
        assert_eq!(paragraph_line_offsets(&tops, 2, 2, 37.5), vec![0.0, 38.0]);   // second paragraph: 113 - 75
        assert_eq!(paragraph_line_offsets(&tops, 3, 2, 37.5), vec![0.0, 37.5]);   // missing top: plain advance
    }
}

#[cfg(test)]
mod text_cache_budget_tests {
    use super::*;

    struct Fake(String);
    impl Retained for Fake {
        fn retained_bytes(&self) -> usize {
            self.0.len() + (self.0.chars().count() + 1) * RETAINED_PER_CHAR
        }
        fn cached_text(&self) -> &str {
            &self.0
        }
    }

    #[test]
    fn a_growing_field_stays_within_the_byte_budget() {
        // One entry per keystroke, each holding the whole field (the R10 workload types 10 chars/s into one field).
        let mut c: TextCacheOf<Fake> = TextCacheOf::new();
        let mut field = String::new();
        let mut peak = 0;
        for i in 0..20_000u64 {
            field.push('x');
            c.put(i, Arc::new(Fake(field.clone())));
            assert!(c.bytes() <= CACHE_BYTES, "bytes {} over budget at {}", c.bytes(), i);
            peak = peak.max(c.bytes());
        }
        assert!(peak > CACHE_BYTES / 2, "the budget is used, not starved: peak {}", peak);
    }

    #[test]
    fn an_oversize_entry_is_not_cached_and_keeps_the_rest() {
        let mut c: TextCacheOf<Fake> = TextCacheOf::new();
        c.put(1, Arc::new(Fake("small".into())));
        let big = "y".repeat(CACHE_ENTRY_MAX / RETAINED_PER_CHAR + 1);
        c.put(2, Arc::new(Fake(big.clone())));
        assert!(c.get(2, &big).is_none());
        assert!(c.get(1, "small").is_some());
    }

    #[test]
    fn the_count_cap_still_applies_and_replacing_a_key_does_not_double_count() {
        let mut c: TextCacheOf<Fake> = TextCacheOf::new();
        for i in 0..(CACHE_CAP as u64 + 3) {
            c.put(i, Arc::new(Fake("ab".into())));
        }
        assert!(c.len() <= CACHE_CAP);
        let before = c.bytes();
        c.put(0, Arc::new(Fake("ab".into())));
        c.put(0, Arc::new(Fake("ab".into())));
        assert!(c.bytes() <= before + Fake("ab".into()).retained_bytes());
        c.clear();
        assert_eq!((c.len(), c.bytes()), (0, 0));
    }
}

#[cfg(test)]
mod max_lines_tests {
    use super::*;

    #[test]
    fn fits_means_no_truncation() {
        assert_eq!(limit_prefix("abc def", &[4, 7], 2), None);
        assert_eq!(limit_prefix("abc def", &[7], 3), None);
        assert_eq!(limit_prefix("abc def", &[4, 7], 0), None);
    }

    #[test]
    fn keeps_whole_lines_and_drops_trailing_space_and_newline() {
        assert_eq!(limit_prefix("abc def ghi", &[4, 8, 11], 1).as_deref(), Some("abc"));
        assert_eq!(limit_prefix("abc def ghi", &[4, 8, 11], 2).as_deref(), Some("abc def"));
        assert_eq!(limit_prefix("ab\ncd\nef", &[3, 6, 8], 2).as_deref(), Some("ab\ncd"));
    }

    #[test]
    fn cut_points_are_char_boundaries_from_lo() {
        assert_eq!(cut_points("ab cd", 3), vec![3, 4, 5]);
        assert_eq!(cut_points("a\u{e9}b", 1), vec![1, 3, 4]);
        assert_eq!(cut_points("abc", 9), vec![3]);
    }

    #[test]
    fn last_fitting_finds_the_boundary() {
        let f = |limit: usize| move |i: usize| -> Result<bool, Status> { Ok(i <= limit) };
        assert_eq!(last_fitting(10, f(6)).unwrap(), Some(6));
        assert_eq!(last_fitting(10, f(0)).unwrap(), Some(0));
        assert_eq!(last_fitting(10, f(99)).unwrap(), Some(9));
        assert_eq!(last_fitting(10, |_| Ok(false)).unwrap(), None);
        assert_eq!(last_fitting(0, f(3)).unwrap(), None);
    }

    #[test]
    fn shrinking_removes_one_char_and_the_space_before_it() {
        assert_eq!(shrink_prefix("abc def"), "abc de");
        assert_eq!(shrink_prefix("abc d"), "abc");
        assert_eq!(shrink_prefix("a"), "");
        assert_eq!(shrink_prefix("\u{e9}\u{e9}"), "\u{e9}");
        assert_eq!(shrink_prefix(""), "");
    }
}
