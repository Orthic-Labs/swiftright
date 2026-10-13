//! Rev 0.7 bundled-font registry (swr_font_register / swr_font_resolve).
//!
//! Pure and GPUI-free on purpose: sfnt parsing, SHA-256 identity, handle minting,
//! de-duplication and the resolve decision are unit-tested here; lib.rs does the one
//! GPUI-specific step (`TextSystem::add_fonts`).
//!
//! Lifetime: GPUI 0.2.2's DirectWrite text system keeps a growing `IDWriteFontSetBuilder`
//! and has no remove call, and `add_fonts` with `Cow::Borrowed` wraps the caller's memory
//! in an in-memory font file reference WITHOUT copying it. So registered bytes are copied
//! once, leaked (`'static`) and retained for the life of the process; there is no release.

use std::sync::Mutex;

use crate::abi::*;

pub const MAX_FACES: u32 = 64;

/// What the sfnt header and tables tell us about a font file.
#[derive(Clone, Debug, PartialEq)]
pub struct FontMeta {
    pub family: String,
    pub weight: u32,
    pub face_count: u32,
}

fn be16(b: &[u8], o: usize) -> Option<u16> {
    Some(u16::from_be_bytes(b.get(o..o.checked_add(2)?)?.try_into().ok()?))
}

fn be32(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(o..o.checked_add(4)?)?.try_into().ok()?))
}

/// Finds `tag` in the table directory of the face at `face_off`; returns (offset, length), bounds-checked.
fn table(b: &[u8], face_off: usize, tag: &[u8; 4]) -> Option<(usize, usize)> {
    let n = be16(b, face_off.checked_add(4)?)? as usize;
    for i in 0..n {
        let rec = face_off.checked_add(12)?.checked_add(i.checked_mul(16)?)?;
        if b.get(rec..rec.checked_add(4)?)? == tag {
            let off = be32(b, rec + 8)? as usize;
            let len = be32(b, rec + 12)? as usize;
            if off.checked_add(len)? <= b.len() {
                return Some((off, len));
            }
            return None;
        }
    }
    None
}

fn decode_name(raw: &[u8], platform: u16) -> Option<String> {
    match platform {
        0 | 3 => {
            if raw.len() % 2 != 0 {
                return None;
            }
            let u: Vec<u16> = raw.chunks_exact(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect();
            String::from_utf16(&u).ok()
        }
        1 => Some(raw.iter().map(|&c| if c < 0x80 { c as char } else { '?' }).collect()),
        _ => None,
    }
}

/// Family name from the `name` table: typographic family (ID 16) else family (ID 1);
/// Windows/Unicode records preferred over Macintosh ones.
fn family_name(b: &[u8], face_off: usize) -> Option<String> {
    let (off, len) = table(b, face_off, b"name")?;
    let t = &b[off..off + len];
    let count = be16(t, 2)? as usize;
    let str_off = be16(t, 4)? as usize;
    let mut best: Option<(u8, String)> = None; // lower rank wins
    for i in 0..count {
        let r = 6 + i * 12;
        let platform = be16(t, r)?;
        let lang = be16(t, r + 4)?;
        let name_id = be16(t, r + 6)?;
        let slen = be16(t, r + 8)? as usize;
        let soff = be16(t, r + 10)? as usize;
        if name_id != 16 && name_id != 1 {
            continue;
        }
        let s_start = str_off.checked_add(soff)?;
        let Some(raw) = t.get(s_start..s_start.checked_add(slen)?) else { continue };
        let Some(s) = decode_name(raw, platform) else { continue };
        if s.is_empty() {
            continue;
        }
        let rank = (if name_id == 16 { 0 } else { 4 })
            + (match platform { 3 => if lang == 0x409 { 0 } else { 1 }, 0 => 2, _ => 3 });
        if best.as_ref().map_or(true, |(r0, _)| rank < *r0) {
            best = Some((rank, s));
        }
    }
    best.map(|(_, s)| s)
}

/// Validates the sfnt container and extracts the family, weight class and face count.
/// Anything that is not a TrueType/OpenType font (or a TrueType collection of them) is `E_BAD_ARG`.
pub fn parse(b: &[u8]) -> Result<FontMeta, Status> {
    let tag = be32(b, 0).ok_or(E_BAD_ARG)?;
    let (first, faces) = if tag == 0x7474_6366 {
        // 'ttcf'
        let n = be32(b, 8).ok_or(E_BAD_ARG)?;
        if n == 0 || n > MAX_FACES {
            return Err(E_BAD_ARG);
        }
        (be32(b, 12).ok_or(E_BAD_ARG)? as usize, n)
    } else if tag == 0x0001_0000 || tag == 0x4F54_544F || tag == 0x7472_7565 {
        // 0x00010000, 'OTTO', 'true'
        (0usize, 1)
    } else {
        return Err(E_BAD_ARG);
    };
    let n_tables = be16(b, first.checked_add(4).ok_or(E_BAD_ARG)?).ok_or(E_BAD_ARG)?;
    if n_tables == 0 {
        return Err(E_BAD_ARG);
    }
    // A usable face has head and name, and outlines (glyf or CFF).
    if table(b, first, b"head").is_none() || table(b, first, b"name").is_none() {
        return Err(E_BAD_ARG);
    }
    if table(b, first, b"glyf").is_none() && table(b, first, b"CFF ").is_none() && table(b, first, b"CFF2").is_none() {
        return Err(E_BAD_ARG);
    }
    let family = family_name(b, first).ok_or(E_BAD_ARG)?;
    if family.len() > FONT_FAMILY_MAX {
        return Err(E_TOO_LARGE);
    }
    let weight = table(b, first, b"OS/2")
        .and_then(|(o, l)| if l >= 6 { be16(b, o + 4) } else { None })
        .map(|w| w as u32)
        .filter(|w| (1..=1000).contains(w))
        .unwrap_or(400);
    Ok(FontMeta { family, weight, face_count: faces })
}

// ------------------------------------------------------------------ SHA-256

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v = [t1.wrapping_add(t2), v[0], v[1], v[2], v[3].wrapping_add(t1), v[4], v[5], v[6]];
        }
        for i in 0..8 {
            h[i] = h[i].wrapping_add(v[i]);
        }
    }
    let mut out = [0u8; 32];
    for i in 0..8 {
        out[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

// ----------------------------------------------------------------- registry

#[derive(Clone, Debug)]
pub struct Entry {
    pub handle: u64,
    pub meta: FontMeta,
    pub sha256: [u8; 32],
}

#[derive(Default)]
pub struct Registry {
    entries: Vec<Entry>,
    /// Lower-cased families that were shaped (measured) at least once, bundled or not.
    shaped: Vec<String>,
}

pub fn key(family: &str) -> String {
    family.to_lowercase()
}

impl Registry {
    pub const fn new() -> Registry {
        Registry { entries: Vec::new(), shaped: Vec::new() }
    }

    pub fn find_sha(&self, sha: &[u8; 32]) -> Option<&Entry> {
        self.entries.iter().find(|e| &e.sha256 == sha)
    }

    pub fn find_family(&self, family: &str) -> Option<&Entry> {
        let k = key(family);
        self.entries.iter().find(|e| key(&e.meta.family) == k)
    }

    /// Records a measured family (so a later registration can report SWR_FONT_LATE).
    pub fn note_shaped(&mut self, family: &str) {
        let k = key(family);
        if !self.shaped.contains(&k) && self.shaped.len() < 4096 {
            self.shaped.push(k);
        }
    }

    pub fn was_shaped(&self, family: &str) -> bool {
        self.shaped.contains(&key(family))
    }

    /// Adds a new entry (the caller has already handed the bytes to the text system). Handles
    /// are slot + 1 in the low 32 bits with generation 1 in the high 32 bits; they never go stale.
    pub fn add(&mut self, meta: FontMeta, sha256: [u8; 32]) -> Entry {
        let handle = (1u64 << 32) | (self.entries.len() as u64 + 1);
        let e = Entry { handle, meta, sha256 };
        self.entries.push(e.clone());
        e
    }

    /// Where `family` will be shaped from. `system_listed` asks the text system whether it lists the family.
    pub fn resolve(&self, family: &str, system_listed: impl Fn(&str) -> bool) -> (u32, Option<&Entry>) {
        if let Some(e) = self.find_family(family) {
            (FONT_SRC_BUNDLED, Some(e))
        } else if system_listed(family) {
            (FONT_SRC_SYSTEM, None)
        } else {
            (FONT_SRC_FALLBACK, None)
        }
    }
}

pub static REGISTRY: Mutex<Registry> = Mutex::new(Registry::new());

pub fn fill_info(out: &mut FontInfo, e: &Entry, flags: u32) {
    let mut fam = [0u8; FONT_FAMILY_MAX];
    let b = e.meta.family.as_bytes();
    fam[..b.len()].copy_from_slice(b);
    *out = FontInfo {
        struct_size: std::mem::size_of::<FontInfo>() as u32,
        flags,
        font: e.handle,
        family_len: b.len() as u32,
        weight: e.meta.weight,
        face_count: e.meta.face_count,
        reserved: 0,
        sha256: e.sha256,
        family: fam,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Tinos Regular (Apache-2.0), same bytes the factory and the Mac side use (testdata/fonts/README.md).
    const TINOS: &[u8] = include_bytes!("../testdata/fonts/Tinos-Regular.ttf");
    const TINOS_SHA: &str = "60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61";

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    #[test]
    fn sha256_known_vectors() {
        assert_eq!(hex(&sha256(b"")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(hex(&sha256(b"abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let two_blocks = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
        assert_eq!(hex(&sha256(two_blocks)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    }

    #[test]
    fn tinos_bytes_are_the_pinned_resource() {
        assert_eq!(TINOS.len(), 521_588);
        assert_eq!(hex(&sha256(TINOS)), TINOS_SHA);
    }

    #[test]
    fn parses_tinos_family_weight_faces() {
        let m = parse(TINOS).unwrap();
        assert_eq!(m.family, "Tinos");
        assert_eq!(m.weight, 400);
        assert_eq!(m.face_count, 1);
    }

    #[test]
    fn rejects_non_fonts_and_truncations() {
        assert_eq!(parse(b""), Err(E_BAD_ARG));
        assert_eq!(parse(b"not a font at all"), Err(E_BAD_ARG));
        assert_eq!(parse(&[0, 1, 0, 0]), Err(E_BAD_ARG));
        // Table directory cut short: tables run past the end.
        assert_eq!(parse(&TINOS[..200]), Err(E_BAD_ARG));
        // Flip the sfnt version.
        let mut bad = TINOS.to_vec();
        bad[0] = 0x7f;
        assert_eq!(parse(&bad), Err(E_BAD_ARG));
    }

    #[test]
    fn registry_dedupes_by_bytes_and_resolves_families() {
        let mut r = Registry::new();
        let sha = sha256(TINOS);
        let meta = parse(TINOS).unwrap();
        assert!(r.find_sha(&sha).is_none());
        let e = r.add(meta, sha);
        assert_ne!(e.handle, 0);
        assert_eq!(r.find_sha(&sha).unwrap().handle, e.handle);
        // Bundled wins over any system listing, case-insensitively.
        let (src, hit) = r.resolve("tINOS", |_| true);
        assert_eq!(src, FONT_SRC_BUNDLED);
        assert_eq!(hit.unwrap().sha256, sha);
        // Negative control: an unregistered family is never reported bundled.
        let (src, hit) = r.resolve("Tinos Bold Italic Condensed", |_| false);
        assert_eq!(src, FONT_SRC_FALLBACK);
        assert!(hit.is_none());
        let (src, _) = r.resolve("Segoe UI", |f| f == "Segoe UI");
        assert_eq!(src, FONT_SRC_SYSTEM);
    }

    #[test]
    fn late_registration_is_reported() {
        let mut r = Registry::new();
        assert!(!r.was_shaped("Tinos"));
        r.note_shaped("Tinos");
        assert!(r.was_shaped("tinos"));
    }

    #[test]
    fn info_layout_and_fill() {
        let mut r = Registry::new();
        let e = r.add(parse(TINOS).unwrap(), sha256(TINOS));
        let mut out: FontInfo = unsafe { std::mem::zeroed() };
        fill_info(&mut out, &e, FONT_NEW);
        assert_eq!(out.struct_size, 128);
        assert_eq!(&out.family[..out.family_len as usize], b"Tinos");
        assert_eq!(out.family[5], 0);
        assert_eq!(out.flags, FONT_NEW);
    }
}
