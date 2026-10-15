//! Rev 0.8 face policy: pure and DirectWrite-free, so everything here is unit-tested without a window.
//!
//! * `pick_face`: maps a requested (weight, italic) onto the REAL faces of a family (named instances), applies the
//!   simulation policy, and says what it did (`ignored` bits). gpui 0.2.2 snaps to named instances and simulates bold or
//!   oblique when no real face exists (F0 facts G11, G12); the renderer makes that decision itself, deterministically,
//!   and hands gpui a weight that selects the face it chose.
//! * sfnt table metrics (`head`, `hhea`, `OS/2`) for `swr_font_face_metrics`.
//! * OpenType tag helpers and request validation.

use crate::abi::*;
use crate::font;

/// One REAL (non-simulated) face of a family.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FaceEntry {
    pub weight: u32,
    pub italic: bool,
}

/// What the policy decided for one request.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pick {
    /// The family has at least one real face (else the request passes through to gpui unchanged).
    pub found: bool,
    /// Weight of the named instance drawn (0 when not found).
    pub weight: u32,
    /// Italic requested of gpui (true: a real italic face, or a simulated oblique).
    pub italic: bool,
    /// SIMFLAG_* the shaper will apply (predicted: bold when the request is >= 600 and no real face is).
    pub sim: u32,
    /// SWR_M08_IGN_* bits decided here.
    pub ignored: u32,
    /// The weight to give gpui so that it selects the face chosen here.
    pub weight_for_gpui: f32,
}

/// DirectWrite simulates bold for a request at or above semi-bold when no real face is that heavy.
pub const BOLD_SIM_THRESHOLD: u32 = 600;

pub fn pick_face(faces: &[FaceEntry], want_weight: u32, want_italic: bool, forbid_bold: bool, forbid_oblique: bool) -> Pick {
    let want = want_weight.clamp(1, 1000);
    if faces.is_empty() {
        return Pick { found: false, weight: 0, italic: want_italic, sim: 0, ignored: 0, weight_for_gpui: want as f32 };
    }
    let mut ignored = 0u32;
    let mut sim = 0u32;
    let any_italic = faces.iter().any(|f| f.italic);
    let any_upright = faces.iter().any(|f| !f.italic);
    // Style first: a request for italic takes an italic face; without one it is simulated or dropped by policy.
    let (pool_italic, italic_out) = if want_italic {
        if any_italic {
            (true, true)
        } else if forbid_oblique {
            ignored |= M08_IGN_SIM_OBLIQUE_DROPPED;
            (false, false)
        } else {
            sim |= SIMFLAG_OBLIQUE;
            (false, true)
        }
    } else if any_upright {
        (false, false)
    } else {
        (true, true) // an italic-only family
    };
    // Weight: the nearest real instance of that style; a tie goes to the heavier one (500 -> 600, as DirectWrite does).
    let mut best: Option<u32> = None;
    for f in faces.iter().filter(|f| f.italic == pool_italic) {
        let better = match best {
            None => true,
            Some(b) => {
                let (db, df) = (b.abs_diff(want), f.weight.abs_diff(want));
                df < db || (df == db && f.weight > b)
            }
        };
        if better {
            best = Some(f.weight);
        }
    }
    let resolved = best.unwrap_or(faces[0].weight);
    let wants_sim_bold = want >= BOLD_SIM_THRESHOLD && resolved < BOLD_SIM_THRESHOLD;
    let weight_for_gpui;
    if wants_sim_bold && !forbid_bold {
        sim |= SIMFLAG_BOLD;
        weight_for_gpui = want as f32; // let DirectWrite simulate, as before
    } else {
        if wants_sim_bold {
            ignored |= M08_IGN_SIM_BOLD_DROPPED;
        }
        weight_for_gpui = resolved as f32;
    }
    if resolved != want && !(sim & SIMFLAG_BOLD != 0) {
        ignored |= M08_IGN_WEIGHT_SNAPPED;
    }
    Pick { found: true, weight: resolved, italic: italic_out, sim, ignored, weight_for_gpui }
}

// ------------------------------------------------------------- tags, features

/// "kern" <-> SWR_TAG('k','e','r','n'): first character in the high byte.
pub fn tag_string(tag: u32) -> Option<String> {
    let b = tag.to_be_bytes();
    b.iter().all(|c| (0x20..0x7F).contains(c)).then(|| String::from_utf8_lossy(&b).to_string())
}

pub fn tag_from(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    (b.len() == 4 && b.iter().all(|c| (0x20..0x7F).contains(c))).then(|| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
}

/// Feature list of a request: at most FEATURES_MAX entries, every tag four printable ASCII bytes.
pub fn features_from(raw: &[Feature]) -> Result<Vec<(String, u32)>, Status> {
    if raw.len() > FEATURES_MAX {
        return Err(E_TOO_LARGE);
    }
    raw.iter().map(|f| tag_string(f.tag).map(|t| (t, f.value)).ok_or(E_BAD_ARG)).collect()
}

// -------------------------------------------------------------- sfnt metrics

/// Vertical and size metrics read from the sfnt tables, in font units.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RawMetrics {
    pub units_per_em: i32,
    pub hhea_ascent: i32,
    pub hhea_descent: i32,
    pub hhea_line_gap: i32,
    pub typo_ascent: i32,
    pub typo_descent: i32,
    pub typo_line_gap: i32,
    pub win_ascent: i32,
    pub win_descent: i32,
    pub cap_height: i32,
    pub x_height: i32,
}

fn s16(b: &[u8], o: usize) -> Option<i32> {
    Some(i16::from_be_bytes(b.get(o..o.checked_add(2)?)?.try_into().ok()?) as i32)
}
fn u16_(b: &[u8], o: usize) -> Option<i32> {
    Some(u16::from_be_bytes(b.get(o..o.checked_add(2)?)?.try_into().ok()?) as i32)
}

/// From the three tables themselves (offset 0 = table start). `os2` may be absent.
pub fn metrics_from_tables(head: &[u8], hhea: &[u8], os2: Option<&[u8]>) -> Option<RawMetrics> {
    let mut m = RawMetrics {
        units_per_em: u16_(head, 18)?,
        hhea_ascent: s16(hhea, 4)?,
        hhea_descent: s16(hhea, 6)?,
        hhea_line_gap: s16(hhea, 8)?,
        ..Default::default()
    };
    if m.units_per_em <= 0 {
        return None;
    }
    if let Some(o) = os2 {
        m.typo_ascent = s16(o, 68).unwrap_or(0);
        m.typo_descent = s16(o, 70).unwrap_or(0);
        m.typo_line_gap = s16(o, 72).unwrap_or(0);
        m.win_ascent = u16_(o, 74).unwrap_or(0);
        m.win_descent = u16_(o, 76).unwrap_or(0);
        // sxHeight / sCapHeight exist from OS/2 version 2.
        if u16_(o, 0).unwrap_or(0) >= 2 && o.len() >= 90 {
            m.x_height = s16(o, 86).unwrap_or(0);
            m.cap_height = s16(o, 88).unwrap_or(0);
        }
    }
    Some(m)
}

/// From a whole font file (first face of a collection).
pub fn file_metrics(b: &[u8]) -> Option<RawMetrics> {
    let first = if b.get(0..4)? == b"ttcf" { u32::from_be_bytes(b.get(12..16)?.try_into().ok()?) as usize } else { 0 };
    let slice = |tag: &[u8; 4]| font::table(b, first, tag).map(|(o, l)| &b[o..o + l]);
    metrics_from_tables(slice(b"head")?, slice(b"hhea")?, slice(b"OS/2"))
}

// --------------------------------------------------------------- fixed strings

/// Copies `s` into a NUL padded fixed field, truncating on a character boundary so the NUL always fits.
pub fn fill_cstr(dst: &mut [u8], s: &str) {
    dst.fill(0);
    let mut n = s.len().min(dst.len().saturating_sub(1));
    while n > 0 && !s.is_char_boundary(n) {
        n -= 1;
    }
    dst[..n].copy_from_slice(&s.as_bytes()[..n]);
}

#[cfg(test)]
mod tests {
    use super::*;

    const TINOS: &[u8] = include_bytes!("../testdata/fonts/Tinos-Regular.ttf");

    fn f(weight: u32, italic: bool) -> FaceEntry {
        FaceEntry { weight, italic }
    }

    /// Segoe UI Variable Text on the measured build (G11): Light 300, Semilight 350, Regular 400, Semibold 600, Bold 700.
    fn variable_text() -> Vec<FaceEntry> {
        vec![f(300, false), f(350, false), f(400, false), f(600, false), f(700, false)]
    }

    #[test]
    fn weights_snap_to_named_instances_like_the_measured_directwrite_matches() {
        let v = variable_text();
        // G11: request 500 gives Semibold, 100 and 200 give Light, 800 and 900 give Bold.
        for (want, got) in [(500, 600), (100, 300), (200, 300), (800, 700), (900, 700), (400, 400), (350, 350), (649, 600), (650, 700), (449, 400)] {
            let p = pick_face(&v, want, false, false, false);
            assert!(p.found);
            assert_eq!(p.weight, got, "request {want}");
            assert_eq!(p.sim, 0, "a real face exists: no simulation for {want}");
        }
        // The weight handed to gpui is the instance itself, so gpui selects the same face.
        assert_eq!(pick_face(&v, 500, false, false, false).weight_for_gpui, 600.0);
    }

    #[test]
    fn inexact_weight_is_reported_and_exact_is_not() {
        let v = variable_text();
        assert_eq!(pick_face(&v, 500, false, false, false).ignored & M08_IGN_WEIGHT_SNAPPED, M08_IGN_WEIGHT_SNAPPED);
        assert_eq!(pick_face(&v, 600, false, false, false).ignored, 0);
        assert_eq!(pick_face(&v, 400, false, false, false).ignored, 0);
    }

    #[test]
    fn heavy_request_takes_a_real_black_when_the_family_has_one() {
        // Static Segoe UI has Black 900 (G11): 800 and 900 map to Black there.
        let segoe = vec![f(300, false), f(350, false), f(400, false), f(600, false), f(700, false), f(900, false)];
        assert_eq!(pick_face(&segoe, 800, false, false, false).weight, 900);
        assert_eq!(pick_face(&segoe, 900, false, false, false).weight, 900);
        assert_eq!(pick_face(&segoe, 900, false, false, false).sim, 0);
    }

    #[test]
    fn bold_is_simulated_only_when_no_real_face_is_heavy_enough_and_allowed() {
        // Tinos Regular only: request 700 is simulated by DirectWrite (G12).
        let tinos = vec![f(400, false)];
        let p = pick_face(&tinos, 700, false, false, false);
        assert_eq!((p.weight, p.sim), (400, SIMFLAG_BOLD));
        assert_eq!(p.weight_for_gpui, 700.0, "allowed: gpui is asked for 700 and simulates, as in 0.6");
        assert_eq!(p.ignored & M08_IGN_WEIGHT_SNAPPED, 0, "a simulated bold is not a snap");
        // Forbidden: the real face is drawn and the dropped simulation is reported (the Mac does not synthesise, G27).
        let q = pick_face(&tinos, 700, false, true, false);
        assert_eq!((q.weight, q.sim), (400, 0));
        assert_eq!(q.weight_for_gpui, 400.0);
        assert_eq!(q.ignored & M08_IGN_SIM_BOLD_DROPPED, M08_IGN_SIM_BOLD_DROPPED);
        // A light request never triggers bold simulation.
        assert_eq!(pick_face(&tinos, 300, false, false, false).sim, 0);
        // With a real Bold registered nothing is simulated.
        let both = vec![f(400, false), f(700, false)];
        let r = pick_face(&both, 700, false, true, false);
        assert_eq!((r.weight, r.sim, r.ignored), (700, 0, 0));
    }

    #[test]
    fn oblique_is_simulated_dropped_or_real_by_policy() {
        let tinos = vec![f(400, false)];
        let allow = pick_face(&tinos, 400, true, false, false);
        assert!(allow.italic);
        assert_eq!(allow.sim, SIMFLAG_OBLIQUE);
        let forbid = pick_face(&tinos, 400, true, false, true);
        assert!(!forbid.italic, "upright face drawn instead");
        assert_eq!(forbid.sim, 0);
        assert_eq!(forbid.ignored & M08_IGN_SIM_OBLIQUE_DROPPED, M08_IGN_SIM_OBLIQUE_DROPPED);
        let with_italic = vec![f(400, false), f(400, true)];
        let real = pick_face(&with_italic, 400, true, true, true);
        assert!(real.italic);
        assert_eq!((real.sim, real.ignored), (0, 0));
        // Bold italic with only Regular and Bold registered: bold is real, italic is dropped when forbidden.
        let rb = vec![f(400, false), f(700, false)];
        let bi = pick_face(&rb, 700, true, true, true);
        assert_eq!((bi.weight, bi.italic, bi.sim), (700, false, 0));
        assert_eq!(bi.ignored, M08_IGN_SIM_OBLIQUE_DROPPED);
    }

    #[test]
    fn unknown_family_passes_through_untouched() {
        let p = pick_face(&[], 500, true, true, true);
        assert!(!p.found);
        assert_eq!((p.weight, p.sim, p.ignored), (0, 0, 0));
        assert_eq!(p.weight_for_gpui, 500.0);
        assert!(p.italic);
    }

    #[test]
    fn italic_only_family_still_resolves() {
        let p = pick_face(&[f(400, true)], 400, false, false, false);
        assert!(p.found && p.italic);
    }

    #[test]
    fn tags_round_trip_and_reject_non_printable() {
        assert_eq!(tag_from("kern"), Some(0x6B65726E));
        assert_eq!(tag_string(0x6B65726E).as_deref(), Some("kern"));
        assert_eq!(tag_from("ker"), None);
        assert_eq!(tag_from("kérn"), None);
        assert_eq!(tag_string(0x6B650001), None);
    }

    #[test]
    fn feature_list_limits() {
        let ok: Vec<Feature> = (0..16).map(|_| Feature { tag: 0x6B65726E, value: 1 }).collect();
        assert_eq!(features_from(&ok).unwrap().len(), 16);
        let many: Vec<Feature> = (0..17).map(|_| Feature { tag: 0x6B65726E, value: 1 }).collect();
        assert_eq!(features_from(&many), Err(E_TOO_LARGE));
        assert_eq!(features_from(&[Feature { tag: 0x01020304, value: 1 }]), Err(E_BAD_ARG));
        assert_eq!(features_from(&[Feature { tag: 0x6B65726E, value: 1 }]).unwrap(), vec![("kern".to_string(), 1)]);
    }

    #[test]
    fn tinos_table_metrics() {
        // Values read from the Tinos Regular tables (head, hhea, OS/2 v4) independently of this code.
        let m = file_metrics(TINOS).unwrap();
        assert_eq!(m.units_per_em, 2048);
        assert_eq!((m.hhea_ascent, m.hhea_descent, m.hhea_line_gap), (1825, -443, 87));
        assert_eq!((m.typo_ascent, m.typo_descent, m.typo_line_gap), (1420, -442, 307));
        assert_eq!((m.win_ascent, m.win_descent), (1825, 443));
        assert_eq!((m.x_height, m.cap_height), (940, 1341));
    }

    #[test]
    fn metrics_reject_short_tables_and_tolerate_a_missing_os2() {
        assert_eq!(metrics_from_tables(&[0; 4], &[0; 10], None), None);
        let mut head = [0u8; 54];
        head[18] = 0x08; // 2048
        let mut hhea = [0u8; 36];
        hhea[4] = 0x07;
        hhea[5] = 0x21;
        let m = metrics_from_tables(&head, &hhea, None).unwrap();
        assert_eq!((m.units_per_em, m.hhea_ascent, m.typo_ascent, m.cap_height), (2048, 1825, 0, 0));
        assert_eq!(file_metrics(&[1, 2, 3]), None);
    }

    #[test]
    fn fixed_strings_truncate_on_a_character_boundary_and_keep_the_nul() {
        let mut b = [0xFFu8; 8];
        fill_cstr(&mut b, "abc");
        assert_eq!(&b, b"abc\0\0\0\0\0");
        fill_cstr(&mut b, "abcdefghijkl");
        assert_eq!(&b, b"abcdefg\0");
        fill_cstr(&mut b, "abcdef\u{e9}"); // 'é' is 2 bytes: 6 + 2 = 8 > 7
        assert_eq!(&b, b"abcdef\0\0");
    }
}
