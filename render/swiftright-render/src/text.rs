//! Synchronous text measurement over GPUI's text system, retained shaped runs and the
//! cache. Measurement is read-only: it never calls the host, never touches GPUI app or
//! window borrows (it uses an independently retained `Arc<WindowTextSystem>`), and runs
//! on the UI thread only.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use gpui::{font, px, FontWeight, Hsla, Rgba, SharedString, TextRun, WindowTextSystem, WrappedLine};

use crate::abi::*;
use crate::rt::*;

pub const MAX_RUNS: usize = 65536;
pub const CACHE_CAP: usize = 512;

/// A shaped, wrapped single-paragraph run plus plain per-character geometry.
/// Geometry is physical px (logical shaping x `scale`).
pub struct Measured {
    pub text: String,
    pub wrapped: Option<WrappedLine>,
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

pub struct RunSlab {
    slots: Vec<(u32, Option<Arc<Measured>>)>,
}

impl RunSlab {
    pub fn new() -> RunSlab {
        RunSlab { slots: Vec::new() }
    }

    pub fn insert(&mut self, m: Arc<Measured>) -> Result<u64, Status> {
        let slot = match self.slots.iter().position(|s| s.1.is_none()) {
            Some(i) => i,
            None => {
                if self.slots.len() >= MAX_RUNS {
                    return Err(E_TOO_LARGE);
                }
                self.slots.push((1, None));
                self.slots.len() - 1
            }
        };
        self.slots[slot].1 = Some(m);
        LIVE_RUNS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
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

    pub fn get(&self, h: u64) -> Option<Arc<Measured>> {
        self.locate(h).and_then(|s| self.slots[s].1.clone())
    }

    pub fn release(&mut self, h: u64) -> Status {
        match self.locate(h) {
            None => E_STALE_HANDLE,
            Some(s) => {
                self.retire(s);
                SWR_OK
            }
        }
    }

    /// Drops every live run (window closed: the owner died). Each dropped handle's
    /// generation advances, so a later release fails with SWR_E_STALE_HANDLE.
    pub fn clear(&mut self) {
        for s in 0..self.slots.len() {
            if self.slots[s].1.is_some() {
                self.retire(s);
            }
        }
    }

    fn retire(&mut self, s: usize) {
        self.slots[s].1 = None;
        let mut g = self.slots[s].0.wrapping_add(1);
        if g == 0 {
            g = 1;
        }
        self.slots[s].0 = g;
        LIVE_RUNS.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
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

pub struct TextCache {
    map: HashMap<u64, Arc<Measured>>,
}

impl TextCache {
    pub fn new() -> TextCache {
        TextCache { map: HashMap::new() }
    }

    pub fn get(&self, key: u64, text: &str) -> Option<Arc<Measured>> {
        self.map.get(&key).filter(|m| m.text == text).cloned()
    }

    pub fn put(&mut self, key: u64, m: Arc<Measured>) {
        if self.map.len() >= CACHE_CAP {
            self.map.clear();
        }
        self.map.insert(key, m);
    }
}

/// Shapes `r.text` (single paragraph) with GPUI's text system.
pub fn shape(ts: &WindowTextSystem, r: &Request, key: u64) -> Result<Measured, Status> {
    let scale = r.scale;
    let lh = r.line_height;
    let chars: Vec<char> = r.text.chars().collect();

    if r.text.is_empty() {
        return Ok(Measured {
            text: String::new(),
            wrapped: None,
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
    let lines = ts
        .shape_text(SharedString::from(r.text.to_string()), px(r.font_size), &[run], wrap, None)
        .map_err(|_| E_PLATFORM)?;
    let wrapped = lines.into_iter().next().ok_or(E_PLATFORM)?;
    let layout = wrapped.unwrapped_layout.clone();

    // GPUI convention: each wrap-boundary glyph is the first glyph of the next visual line.
    let mut starts = vec![0usize];
    for b in wrapped.wrap_boundaries.iter() {
        starts.push(layout.runs[b.run_ix].glyphs[b.glyph_ix].index);
    }

    let ws = word_starts_of(&chars);
    let mut cells: Vec<CharCell> = Vec::with_capacity(chars.len());
    let mut line_first_byte: Vec<usize> = Vec::new();
    let mut line_start_x: Vec<f32> = Vec::new();
    let mut line_end_byte: Vec<usize> = Vec::new();
    let mut line_width: Vec<f32> = Vec::new();
    let mut byte = 0usize;
    for (i, ch) in chars.iter().enumerate() {
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
            utf8_offset: byte as u32,
            utf8_len: len as u32,
            line: line as u32,
            flags: if ws[i] { CELL_WORD_START } else { 0 },
            x0,
            x1,
        });
        byte += len;
    }

    let ascent = f32::from(layout.ascent);
    let descent = f32::from(layout.descent);
    // GPUI places the baseline at half-leading + ascent inside each line box.
    let baseline_in_line = ((lh - (ascent + descent)) / 2.0 + ascent) * scale;
    let n_lines = line_first_byte.len().max(1);
    let line_px = lh * scale;
    let mut infos = Vec::with_capacity(n_lines);
    for k in 0..n_lines {
        let first = line_first_byte.get(k).copied().unwrap_or(0);
        let end = line_end_byte.get(k).copied().unwrap_or(first);
        infos.push(LineInfo {
            utf8_start: first as u32,
            utf8_len: (end - first) as u32,
            width: line_width.get(k).copied().unwrap_or(0.0),
            top: k as f32 * line_px,
            baseline: k as f32 * line_px + baseline_in_line,
            reserved: 0.0,
        });
    }
    let width = line_width.iter().cloned().fold(0f32, f32::max);
    Ok(Measured {
        text: r.text.to_string(),
        wrapped: Some(wrapped),
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
