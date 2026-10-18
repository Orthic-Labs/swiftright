//! Synchronous text measurement over GPUI's text system, retained shaped runs and the
//! cache. Measurement is read-only: it never calls the host, never touches GPUI app or
//! window borrows (it uses an independently retained `Arc<WindowTextSystem>`), and runs
//! on the UI thread only.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering::SeqCst};
use std::sync::Arc;

use gpui::{font, px, FontWeight, Hsla, Rgba, SharedString, TextRun, WindowTextSystem, WrappedLine};

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
    pub char_count: u32,
    pub key: u64,
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

pub struct Request<'a> {
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
    r.max_width.max(0.0).to_bits().hash(&mut h);
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
        &self.text
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

/// Shapes `r.text` with GPUI's text system. Rev 0.6: '\n' splits paragraphs.
pub fn shape(ts: &WindowTextSystem, r: &Request, key: u64) -> Result<Measured, Status> {
    let scale = r.scale;
    let lh = r.line_height;
    let line_px = lh * scale;
    let chars: Vec<char> = r.text.chars().collect();

    if r.text.is_empty() {
        return Ok(Measured {
            text: String::new(),
            wrapped: Vec::new(),
            cells: Vec::new(),
            lines: vec![LineInfo {
                utf8_start: 0,
                utf8_len: 0,
                width: 0.0,
                top: 0.0,
                baseline: lh * scale * 0.8,
                reserved: 0.0,
            }],
            width: 0.0,
            height: lh * scale,
            first_baseline: lh * scale * 0.8,
            last_baseline: lh * scale * 0.8,
            line_height_dip: lh,
            scale,
            char_count: 0,
            key,
        });
    }

    let mut f = font(r.family.to_string());
    f.weight = FontWeight(r.weight as f32);
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
        Some(px(r.max_width / scale))
    } else {
        None
    };
    let shaped = ts
        .shape_text(SharedString::from(r.text.to_string()), px(r.font_size), &[run], wrap, None)
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

    for (pi, wl) in shaped.into_iter().enumerate() {
        let ptext = paragraph_texts[pi];
        let layout = wl.unwrapped_layout.clone();
        if asc_desc.is_none() && !ptext.is_empty() {
            asc_desc = Some((f32::from(layout.ascent), f32::from(layout.descent)));
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
            let x0 = (f32::from(layout.x_for_index(byte)) - xs) * scale;
            let x1 = (f32::from(layout.x_for_index(byte + len)) - xs) * scale;
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
        wrapped.push((wl, line_base as f32 * line_px));
        line_base += n_local;
        para_base += ptext.len() + 1;
    }

    let baseline_in_line = match asc_desc {
        // GPUI places the baseline at half-leading + ascent inside each line box.
        Some((ascent, descent)) => ((lh - (ascent + descent)) / 2.0 + ascent) * scale,
        None => lh * scale * 0.8,
    };
    let n_lines = pend.len().max(1);
    for (k, p) in pend.iter().enumerate() {
        // The '\n' belongs to the line it terminates, so lines partition the text.
        let extra = if p.is_para_last && p.has_break { 1 } else { 0 };
        infos.push(LineInfo {
            utf8_start: p.first as u32,
            utf8_len: (p.end - p.first + extra) as u32,
            width: p.width,
            top: k as f32 * line_px,
            baseline: k as f32 * line_px + baseline_in_line,
            reserved: 0.0,
        });
    }
    Ok(Measured {
        text: r.text.to_string(),
        wrapped,
        cells,
        width,
        height: n_lines as f32 * line_px,
        first_baseline: baseline_in_line,
        last_baseline: (n_lines as f32 - 1.0) * line_px + baseline_in_line,
        lines: infos,
        line_height_dip: lh,
        scale,
        char_count: chars.len() as u32,
        key,
    })
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
