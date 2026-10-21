//! Rev 0.8 DirectWrite face resolver: enumerates the REAL faces of an installed family (named instances, simulation
//! excluded), reads a face's identity (PostScript name, version, file name), its axis ranges and its sfnt table metrics.
//! It does NOT shape or paint anything: gpui 0.2.2 still does both (decisions G14, G17). It exists because gpui does not
//! expose which face a request resolved to (G18) nor a way to turn simulations off (G12).
//!
//! DirectWrite objects are not shared between threads: the resolver lives in a thread local and every public function
//! takes the thread's instance once (no nesting). Calls are cheap after the first: faces are cached per family.

use std::cell::RefCell;
use std::collections::HashMap;

use windows::core::{Interface, BOOL, HSTRING};
use windows::Win32::Graphics::DirectWrite::*;

use crate::abi::*;
use crate::faces::{self, FaceEntry, RawMetrics};

struct SysFace {
    entry: FaceEntry,
    face: IDWriteFontFace3,
}

struct Dw {
    set: IDWriteFontSet,
    collection: IDWriteFontCollection1,
    families: HashMap<String, Vec<SysFace>>,
}

thread_local! {
    static DW: RefCell<Option<Dw>> = const { RefCell::new(None) };
}

fn init() -> Option<Dw> {
    unsafe {
        let factory: IDWriteFactory5 = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED).ok()?;
        let mut sys: Option<IDWriteFontCollection1> = None;
        factory.GetSystemFontCollection(false, &mut sys, true).ok()?;
        let collection = sys?;
        let set = collection.GetFontSet().ok()?;
        Some(Dw { set, collection, families: HashMap::new() })
    }
}

fn with_dw<R>(f: impl FnOnce(&mut Dw) -> R) -> Option<R> {
    DW.with(|c| {
        let mut g = c.borrow_mut();
        if g.is_none() {
            *g = init();
        }
        g.as_mut().map(f)
    })
}

impl Dw {
    /// The real faces of `family`, cached (also when empty: an absent family stays absent).
    fn family(&mut self, family: &str) -> &[SysFace] {
        let key = family.to_lowercase();
        if !self.families.contains_key(&key) {
            let v = unsafe { load_family(&self.set, family) };
            self.families.insert(key.clone(), v);
        }
        &self.families[&key]
    }
}

unsafe fn load_family(set: &IDWriteFontSet, family: &str) -> Vec<SysFace> {
    let mut out: Vec<SysFace> = Vec::new();
    // One query returns every face of the family, the matching ones first (F0 DWMATCH counts); a simulated face the
    // request would need is appended with a non-zero simulation flag and is skipped here.
    let Ok(fonts) = set.GetMatchingFonts(
        &HSTRING::from(family),
        DWRITE_FONT_WEIGHT(400),
        DWRITE_FONT_STRETCH_NORMAL,
        DWRITE_FONT_STYLE_NORMAL,
    ) else {
        return out;
    };
    for i in 0..fonts.GetFontCount() {
        let Ok(r) = fonts.GetFontFaceReference(i) else { continue };
        if r.GetSimulations().0 != 0 {
            continue;
        }
        let Ok(face) = r.CreateFontFace() else { continue };
        let entry = FaceEntry { weight: face.GetWeight().0.max(0) as u32, italic: face.GetStyle().0 != 0 };
        if out.iter().any(|f| f.entry == entry) {
            continue;
        }
        out.push(SysFace { entry, face });
    }
    out
}

unsafe fn first_string(s: &IDWriteLocalizedStrings) -> String {
    let n = s.GetStringLength(0).unwrap_or(0) as usize;
    let mut v = vec![0u16; n + 1];
    if s.GetString(0, &mut v).is_err() {
        return String::new();
    }
    String::from_utf16_lossy(&v[..n])
}

unsafe fn info_string(face: &IDWriteFontFace3, id: DWRITE_INFORMATIONAL_STRING_ID) -> String {
    let mut info: Option<IDWriteLocalizedStrings> = None;
    let mut exists = BOOL(0);
    if face.GetInformationalStrings(id, &mut info, &mut exists).is_err() || !exists.as_bool() {
        return String::new();
    }
    info.map(|s| first_string(&s)).unwrap_or_default()
}

unsafe fn read_table(face: &IDWriteFontFace3, tag: &[u8; 4]) -> Option<Vec<u8>> {
    let f: IDWriteFontFace = face.cast().ok()?;
    let mut data: *mut core::ffi::c_void = std::ptr::null_mut();
    let mut size = 0u32;
    let mut ctx: *mut core::ffi::c_void = std::ptr::null_mut();
    let mut exists = BOOL(0);
    f.TryGetFontTable(u32::from_le_bytes(*tag), &mut data, &mut size, &mut ctx, &mut exists).ok()?;
    let out = if exists.as_bool() && !data.is_null() {
        Some(std::slice::from_raw_parts(data as *const u8, size as usize).to_vec())
    } else {
        None
    };
    if !ctx.is_null() {
        f.ReleaseFontTable(ctx);
    }
    out
}

/// Full path of the local file behind a face (None for a non-local loader, e.g. an in-memory font).
unsafe fn file_path(face: &IDWriteFontFace3) -> Option<String> {
    let f: IDWriteFontFace = face.cast().ok()?;
    let mut n = 0u32;
    if f.GetFiles(&mut n, None).is_err() || n == 0 {
        return None;
    }
    let mut files: Vec<Option<IDWriteFontFile>> = vec![None; n as usize];
    if f.GetFiles(&mut n, Some(files.as_mut_ptr())).is_err() {
        return None;
    }
    let file = files.first()?.as_ref()?;
    let mut key: *mut core::ffi::c_void = std::ptr::null_mut();
    let mut ksz = 0u32;
    if file.GetReferenceKey(&mut key, &mut ksz).is_err() {
        return None;
    }
    let loader = file.GetLoader().ok()?;
    let local = loader.cast::<IDWriteLocalFontFileLoader>().ok()?;
    let len = local.GetFilePathLengthFromKey(key, ksz).ok()?;
    let mut buf = vec![0u16; len as usize + 1];
    if local.GetFilePathFromKey(key, ksz, &mut buf).is_err() {
        return None;
    }
    Some(String::from_utf16_lossy(&buf[..len as usize]))
}

unsafe fn file_name(face: &IDWriteFontFace3) -> String {
    match file_path(face) {
        Some(path) => path.rsplit(['\\', '/']).next().unwrap_or("").to_string(),
        None => String::new(),
    }
}

/// Where the outlines of a face live: its font file, the face index inside it (a collection) and the variation axis values of
/// the instance (axis tag characters in order, value). Rev 0.14 glyph outlines read the file with ttf-parser.
#[derive(Clone, Debug, PartialEq)]
pub struct FaceSource {
    pub path: String,
    pub index: u32,
    pub axes: Vec<([u8; 4], f32)>,
}

unsafe fn face_source(face: &IDWriteFontFace3) -> Option<FaceSource> {
    let path = file_path(face)?;
    let base: IDWriteFontFace = face.cast().ok()?;
    let index = base.GetIndex();
    let mut axes: Vec<([u8; 4], f32)> = Vec::new();
    if let Ok(f5) = face.cast::<IDWriteFontFace5>() {
        if f5.HasVariations().as_bool() {
            let n = f5.GetFontAxisValueCount() as usize;
            let mut vals = vec![DWRITE_FONT_AXIS_VALUE::default(); n];
            if f5.GetFontAxisValues(&mut vals).is_ok() {
                // DirectWrite packs the tag little-endian: its bytes are the tag characters in order.
                axes = vals.iter().map(|v| (v.axisTag.0.to_le_bytes(), v.value)).collect();
            }
        }
    }
    Some(FaceSource { path, index, axes })
}

unsafe fn axes_of(face: &IDWriteFontFace3) -> (bool, Vec<AxisRange>) {
    let Ok(f5) = face.cast::<IDWriteFontFace5>() else { return (false, Vec::new()) };
    if !f5.HasVariations().as_bool() {
        return (false, Vec::new());
    }
    let Ok(res) = f5.GetFontResource() else { return (true, Vec::new()) };
    let n = res.GetFontAxisCount() as usize;
    let mut ranges = vec![DWRITE_FONT_AXIS_RANGE::default(); n];
    let mut defs = vec![DWRITE_FONT_AXIS_VALUE::default(); n];
    let _ = res.GetFontAxisRanges(&mut ranges);
    let _ = res.GetDefaultFontAxisValues(&mut defs);
    let axes = ranges
        .iter()
        .zip(defs.iter())
        .take(FACE_AXES_MAX)
        .map(|(r, d)| AxisRange {
            // DirectWrite packs the tag little-endian; the ABI's first character is the high byte.
            tag: u32::from_be_bytes(r.axisTag.0.to_le_bytes()),
            min_value: r.minValue,
            max_value: r.maxValue,
            default_value: d.value,
        })
        .collect();
    (true, axes)
}

/// Identity and metrics of one real face of an installed family.
#[derive(Clone, Debug)]
pub struct FaceDesc {
    pub family: String,
    pub weight: u32,
    pub italic: bool,
    pub style: u32,
    pub ps_name: String,
    pub version: String,
    pub file_name: String,
    pub variable: bool,
    pub axes: Vec<AxisRange>,
    pub metrics: Option<RawMetrics>,
    pub cap_height_dw: i32,
    pub x_height_dw: i32,
}

unsafe fn describe_face(family: &str, f: &SysFace) -> FaceDesc {
    let (variable, axes) = axes_of(&f.face);
    let head = read_table(&f.face, b"head");
    let hhea = read_table(&f.face, b"hhea");
    let os2 = read_table(&f.face, b"OS/2");
    let metrics = match (head, hhea) {
        (Some(h), Some(a)) => faces::metrics_from_tables(&h, &a, os2.as_deref()),
        _ => None,
    };
    let mut dm = DWRITE_FONT_METRICS::default();
    if let Ok(base) = f.face.cast::<IDWriteFontFace>() {
        base.GetMetrics(&mut dm);
    }
    let style = f.face.GetStyle().0;
    FaceDesc {
        family: family.to_string(),
        weight: f.entry.weight,
        italic: f.entry.italic,
        style: match style {
            1 => STYLE_OBLIQUE,
            2 => STYLE_ITALIC,
            _ => STYLE_NORMAL,
        },
        ps_name: info_string(&f.face, DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME),
        version: info_string(&f.face, DWRITE_INFORMATIONAL_STRING_VERSION_STRINGS),
        file_name: file_name(&f.face),
        variable,
        axes,
        metrics,
        cap_height_dw: dm.capHeight as i32,
        x_height_dw: dm.xHeight as i32,
    }
}

// ------------------------------------------------------------------ public

/// The real faces of an installed family: `Some(empty)` when the family is not installed, `None` when DirectWrite itself is
/// unavailable (the caller treats that as "unknown", never as "installed").
pub fn system_faces(family: &str) -> Option<Vec<FaceEntry>> {
    with_dw(|d| d.family(family).iter().map(|f| f.entry).collect())
}

pub fn family_present(family: &str) -> bool {
    system_faces(family).map_or(false, |v| !v.is_empty())
}

/// Identity of the real face `(weight, italic)` of an installed family. An italic request with no real italic face
/// describes the upright face of that weight (the face a simulation would be applied to).
pub fn describe(family: &str, weight: u32, italic: bool) -> Option<FaceDesc> {
    with_dw(|d| {
        let list = d.family(family);
        let hit = list
            .iter()
            .find(|f| f.entry.weight == weight && f.entry.italic == italic)
            .or_else(|| list.iter().find(|f| f.entry.weight == weight))
            .or_else(|| list.first())?;
        Some(unsafe { describe_face(family, hit) })
    })
    .flatten()
}

/// Names the system face that drew `gid` for code point `ch`, among `candidates` (gpui does not expose fallback faces, G18).
/// A match needs the face to map `ch` to exactly `gid` (and `gid != 0`); first candidate that does wins.
pub fn identify(candidates: &[String], ch: u32, gid: u32) -> Option<FaceDesc> {
    if gid == 0 {
        return None;
    }
    with_dw(|d| {
        for fam in candidates {
            let list = d.family(fam);
            let order = list.iter().filter(|f| f.entry.weight == 400 && !f.entry.italic).chain(list.iter().take(1));
            for f in order {
                let Ok(base) = f.face.cast::<IDWriteFontFace>() else { continue };
                let mut g = 0u16;
                if unsafe { base.GetGlyphIndices(&ch, 1, &mut g) }.is_ok() && g as u32 == gid {
                    return Some(unsafe { describe_face(fam, f) });
                }
            }
        }
        None
    })
    .flatten()
}

/// Outline source of the real face `(weight, italic)` of an installed family: the nearest real instance, as `faces::pick_face`
/// chooses it (no simulation), so a simulated bold or oblique is drawn from its upright or regular base face.
pub fn source_of(family: &str, weight: u32, italic: bool) -> Option<FaceSource> {
    with_dw(|d| {
        let list = d.family(family);
        let entries: Vec<FaceEntry> = list.iter().map(|f| f.entry).collect();
        if entries.is_empty() {
            return None;
        }
        let p = faces::pick_face(&entries, weight, italic, true, true);
        let hit = list.iter().find(|f| f.entry.weight == p.weight && f.entry.italic == p.italic).or_else(|| list.first())?;
        unsafe { face_source(&hit.face) }
    })
    .flatten()
}

/// `identify`, answering with the outline source of the face that drew `gid` for `ch`.
pub fn identify_source(candidates: &[String], ch: u32, gid: u32) -> Option<FaceSource> {
    if gid == 0 {
        return None;
    }
    with_dw(|d| {
        for fam in candidates {
            let list = d.family(fam);
            let order = list.iter().filter(|f| f.entry.weight == 400 && !f.entry.italic).chain(list.iter().take(1));
            for f in order {
                let Ok(base) = f.face.cast::<IDWriteFontFace>() else { continue };
                let mut g = 0u16;
                if unsafe { base.GetGlyphIndices(&ch, 1, &mut g) }.is_ok() && g as u32 == gid {
                    return unsafe { face_source(&f.face) };
                }
            }
        }
        None
    })
    .flatten()
}

/// The system families the host's font mapping asks about, in the order of `swr_system_font_entry`.
pub const SYSTEM_FAMILIES: [&str; SYSFONT_ENTRIES] = [
    "Segoe UI",
    "Segoe UI Variable Text",
    "Segoe UI Variable Display",
    "Segoe UI Variable Small",
    "Cascadia Mono",
    "Sitka Text",
    "Segoe UI Emoji",
    "Segoe Fluent Icons",
];

pub struct SystemEntry {
    pub name: &'static str,
    pub version: String,
    pub faces: u32,
}

/// (families in the system set, one entry per `SYSTEM_FAMILIES`). None when DirectWrite is unavailable.
pub fn system_summary() -> Option<(u32, Vec<SystemEntry>)> {
    with_dw(|d| {
        let count = unsafe { d.collection.GetFontFamilyCount() };
        let mut out = Vec::new();
        for name in SYSTEM_FAMILIES {
            let list = d.family(name);
            let faces = list.len() as u32;
            let version = list
                .iter()
                .find(|f| f.entry.weight == 400 && !f.entry.italic)
                .or_else(|| list.first())
                .map(|f| unsafe { info_string(&f.face, DWRITE_INFORMATIONAL_STRING_VERSION_STRINGS) })
                .unwrap_or_default();
            out.push(SystemEntry { name, version, faces });
        }
        (count, out)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segoe_ui_has_real_regular_and_bold_and_no_simulated_entries() {
        let faces = system_faces("Segoe UI").expect("DirectWrite available");
        assert!(faces.contains(&FaceEntry { weight: 400, italic: false }), "{faces:?}");
        assert!(faces.contains(&FaceEntry { weight: 700, italic: false }), "{faces:?}");
        // Every entry is unique: the enumeration does not list simulated duplicates.
        for (i, a) in faces.iter().enumerate() {
            assert!(!faces[i + 1..].contains(a), "duplicate {a:?}");
        }
    }

    #[test]
    fn family_lookup_is_case_insensitive_and_unknown_is_empty_not_none() {
        assert!(family_present("segoe ui"));
        assert_eq!(system_faces("No Such Family SRProbe"), Some(Vec::new()));
        assert!(!family_present("No Such Family SRProbe"));
        // The bare name 'Segoe UI Variable' does not exist as a family (F0, G11).
        assert!(!family_present("Segoe UI Variable"));
    }

    #[test]
    fn segoe_ui_regular_describes_itself() {
        let d = describe("Segoe UI", 400, false).expect("Segoe UI Regular");
        assert_eq!(d.weight, 400);
        assert!(!d.italic);
        assert!(!d.ps_name.is_empty(), "PostScript name");
        assert!(!d.version.is_empty(), "version string");
        let m = d.metrics.expect("sfnt metrics");
        assert_eq!(m.units_per_em, 2048);
        assert!(m.hhea_ascent > 0 && m.hhea_descent < 0 && m.win_ascent > 0);
        assert!(!d.variable, "static Segoe UI has no axes");
    }

    #[test]
    fn missing_family_does_not_describe() {
        assert!(describe("No Such Family SRProbe", 400, false).is_none());
    }

    #[test]
    fn system_summary_lists_the_fixed_families_in_order() {
        let (count, entries) = system_summary().expect("DirectWrite available");
        assert!(count > 10);
        assert_eq!(entries.len(), SYSFONT_ENTRIES);
        assert_eq!(entries[0].name, "Segoe UI");
        assert!(entries[0].faces >= 2 && !entries[0].version.is_empty());
        assert_eq!(entries[7].name, "Segoe Fluent Icons");
    }

    #[test]
    fn identify_matches_only_the_face_that_maps_the_code_point_to_that_glyph() {
        let segoe = describe("Segoe UI", 400, false).unwrap();
        let _ = segoe;
        // Glyph id 0 never identifies a face (it is the .notdef of every font).
        assert!(identify(&["Segoe UI".to_string()], 'A' as u32, 0).is_none());
        // A wrong glyph id for 'A' matches nothing (negative control).
        assert!(identify(&["Segoe UI".to_string()], 'A' as u32, 65000).is_none());
    }
}
