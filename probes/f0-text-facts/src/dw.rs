//! DirectWrite half of the F0 probe (`--dw`): what DirectWrite itself can do, measured the way gpui 0.2.2 calls it
//! (platform/windows/direct_write.rs: GetMatchingFonts on the font set, CreateFontFace of the first match,
//! GetRecommendedRenderingMode + CreateGlyphRunAnalysis(NATURAL_SYMMETRIC unless OUTLINE, grayscale)). Output: DW lines on
//! stdout and BMP contact sheets in `out`. Every section prints its own error and carries on.

use windows::core::{Interface, BOOL, HSTRING};
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::DirectWrite::*;

macro_rules! say {
    ($($a:tt)*) => {{
        println!($($a)*);
    }};
}

pub fn run(out: &str) {
    let _ = std::fs::create_dir_all(out);
    unsafe {
        if let Err(e) = run_inner(out) {
            say!("DWERR top-level {e:?}");
        }
    }
}

struct Cell {
    rect: RECT,
    alpha: Vec<u8>,
    sum: u64,
    /// half-coverage (alpha >= 128) box relative to the baseline origin: [left, top, right, bottom)
    half: Option<[i32; 4]>,
}

struct Sheet {
    w: usize,
    h: usize,
    px: Vec<u8>,
}

impl Sheet {
    fn new(w: usize, h: usize) -> Sheet {
        Sheet {
            w,
            h,
            px: vec![255u8; w * h],
        }
    }

    /// Alpha mask drawn black on white, glyph-run origin (baseline start) at (ox, oy).
    fn blit(&mut self, ox: i32, oy: i32, c: &Cell) {
        let cw = (c.rect.right - c.rect.left).max(0) as usize;
        let ch = (c.rect.bottom - c.rect.top).max(0) as usize;
        for y in 0..ch {
            for x in 0..cw {
                let a = c.alpha.get(y * cw + x).copied().unwrap_or(0) as u32;
                let dx = ox + c.rect.left + x as i32;
                let dy = oy + c.rect.top + y as i32;
                if dx < 0 || dy < 0 || dx as usize >= self.w || dy as usize >= self.h {
                    continue;
                }
                let i = dy as usize * self.w + dx as usize;
                let cur = self.px[i] as u32;
                self.px[i] = (cur * (255 - a) / 255) as u8;
            }
        }
    }

    fn save_bmp(&self, path: &str) {
        let row = (self.w * 3 + 3) & !3;
        let size = 54 + row * self.h;
        let mut b: Vec<u8> = Vec::with_capacity(size);
        b.extend_from_slice(b"BM");
        b.extend_from_slice(&(size as u32).to_le_bytes());
        b.extend_from_slice(&[0, 0, 0, 0]);
        b.extend_from_slice(&54u32.to_le_bytes());
        b.extend_from_slice(&40u32.to_le_bytes());
        b.extend_from_slice(&(self.w as i32).to_le_bytes());
        b.extend_from_slice(&(self.h as i32).to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&24u16.to_le_bytes());
        b.extend_from_slice(&[0u8; 24]);
        for y in (0..self.h).rev() {
            for x in 0..self.w {
                let v = self.px[y * self.w + x];
                b.extend_from_slice(&[v, v, v]);
            }
            for _ in 0..(row - self.w * 3) {
                b.push(0);
            }
        }
        match std::fs::write(path, &b) {
            Ok(()) => say!("DWFILE {path} {}x{}", self.w, self.h),
            Err(e) => say!("DWERR write {path}: {e}"),
        }
    }
}

fn tag_str(t: DWRITE_FONT_AXIS_TAG) -> String {
    String::from_utf8_lossy(&t.0.to_le_bytes()).to_string()
}

unsafe fn first_string(s: &IDWriteLocalizedStrings) -> String {
    let n = s.GetStringLength(0).unwrap_or(0) as usize;
    let mut v = vec![0u16; n + 1];
    if s.GetString(0, &mut v).is_err() {
        return String::new();
    }
    String::from_utf16_lossy(&v[..n])
}

unsafe fn ps_name(face: &IDWriteFontFace3) -> String {
    let mut info = None;
    let mut exists = BOOL(0);
    if face
        .GetInformationalStrings(
            DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME,
            &mut info,
            &mut exists,
        )
        .is_err()
        || !exists.as_bool()
    {
        return "?".to_string();
    }
    match info {
        Some(s) => first_string(&s),
        None => "?".to_string(),
    }
}

/// What gpui sees for `Font { family, weight, style Normal/Italic }`: the first face of GetMatchingFonts.
unsafe fn describe(set: &IDWriteFontSet, fam: &str, w: i32, style: DWRITE_FONT_STYLE) -> String {
    let fonts = match set.GetMatchingFonts(
        &HSTRING::from(fam),
        DWRITE_FONT_WEIGHT(w),
        DWRITE_FONT_STRETCH_NORMAL,
        style,
    ) {
        Ok(f) => f,
        Err(e) => {
            return format!(
                "DWMATCH family=[{fam}] req_weight={w} style={} ERROR {e:?}",
                style.0
            )
        }
    };
    let n = fonts.GetFontCount();
    let mut s = format!(
        "DWMATCH family=[{fam}] req_weight={w} style={} count={n}",
        style.0
    );
    for i in 0..n.min(2) {
        let Ok(r) = fonts.GetFontFaceReference(i) else {
            continue;
        };
        let ref_sim = r.GetSimulations().0;
        let Ok(face) = r.CreateFontFace() else {
            continue;
        };
        let mut axes = String::new();
        if let Ok(f5) = face.cast::<IDWriteFontFace5>() {
            let n = f5.GetFontAxisValueCount() as usize;
            let mut v = vec![DWRITE_FONT_AXIS_VALUE::default(); n];
            if f5.GetFontAxisValues(&mut v).is_ok() {
                axes = v
                    .iter()
                    .map(|a| format!("{}={}", tag_str(a.axisTag), a.value))
                    .collect::<Vec<_>>()
                    .join(",");
            }
            axes = format!(" variations={} axes=[{axes}]", f5.HasVariations().as_bool());
        }
        s.push_str(&format!(
            " | face{i}: weight={} style={} face_sim={} ref_sim={ref_sim} ps={}{axes}",
            face.GetWeight().0,
            face.GetStyle().0,
            face.GetSimulations().0,
            ps_name(&face)
        ));
    }
    s
}

unsafe fn render_text(
    factory: &IDWriteFactory5,
    face: &IDWriteFontFace,
    text: &str,
    size_dip: f32,
    scale: f32,
) -> windows::core::Result<Cell> {
    let cps: Vec<u32> = text.chars().map(|c| c as u32).collect();
    let n = cps.len();
    let mut gi = vec![0u16; n];
    face.GetGlyphIndices(cps.as_ptr(), n as u32, gi.as_mut_ptr())?;
    let mut gm = vec![DWRITE_GLYPH_METRICS::default(); n];
    face.GetDesignGlyphMetrics(gi.as_ptr(), n as u32, gm.as_mut_ptr(), false)?;
    let mut fm = DWRITE_FONT_METRICS::default();
    face.GetMetrics(&mut fm);
    let upem = fm.designUnitsPerEm.max(1) as f32;
    let adv: Vec<f32> = gm
        .iter()
        .map(|m| m.advanceWidth as f32 * size_dip / upem)
        .collect();
    let off = vec![DWRITE_GLYPH_OFFSET::default(); n];
    let glyph_run = DWRITE_GLYPH_RUN {
        fontFace: std::mem::transmute_copy(face),
        fontEmSize: size_dip,
        glyphCount: n as u32,
        glyphIndices: gi.as_ptr(),
        glyphAdvances: adv.as_ptr(),
        glyphOffsets: off.as_ptr(),
        isSideways: BOOL(0),
        bidiLevel: 0,
    };
    let transform = DWRITE_MATRIX {
        m11: scale,
        m12: 0.0,
        m21: 0.0,
        m22: scale,
        dx: 0.0,
        dy: 0.0,
    };
    let mut rendering_mode = DWRITE_RENDERING_MODE1::default();
    let mut grid_fit_mode = DWRITE_GRID_FIT_MODE::default();
    face.cast::<IDWriteFontFace3>()?
        .GetRecommendedRenderingMode(
            size_dip,
            96.0,
            96.0,
            Some(&transform),
            false,
            DWRITE_OUTLINE_THRESHOLD_ANTIALIASED,
            DWRITE_MEASURING_MODE_NATURAL,
            None,
            &mut rendering_mode,
            &mut grid_fit_mode,
        )?;
    let rendering_mode = match rendering_mode {
        DWRITE_RENDERING_MODE1_OUTLINE => DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC,
        m => m,
    };
    if let Some(g) = gf_override {
        grid_fit_mode = g;
    }
    let analysis = factory.CreateGlyphRunAnalysis(
        &glyph_run,
        Some(&transform),
        rendering_mode,
        DWRITE_MEASURING_MODE_NATURAL,
        grid_fit_mode,
        DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE,
        0.0,
        0.0,
    )?;
    let rect = analysis.GetAlphaTextureBounds(DWRITE_TEXTURE_ALIASED_1x1)?;
    let w = (rect.right - rect.left).max(0) as usize;
    let h = (rect.bottom - rect.top).max(0) as usize;
    let mut alpha = vec![0u8; w * h];
    if w > 0 && h > 0 {
        analysis.CreateAlphaTexture(DWRITE_TEXTURE_ALIASED_1x1, &rect, &mut alpha)?;
    }
    let sum = alpha.iter().map(|a| *a as u64).sum();
    let mut half: Option<[i32; 4]> = None;
    for y in 0..h {
        for x in 0..w {
            if alpha[y * w + x] >= 128 {
                let (px, py) = (rect.left + x as i32, rect.top + y as i32);
                half = Some(match half {
                    None => [px, py, px + 1, py + 1],
                    Some(b) => [
                        b[0].min(px),
                        b[1].min(py),
                        b[2].max(px + 1),
                        b[3].max(py + 1),
                    ],
                });
            }
        }
    }
    Ok(Cell {
        rect,
        alpha,
        sum,
        half,
    })
}

fn cell_line(tag: &str, c: &Cell) -> String {
    format!(
        "DWRASTER {tag} bounds=[{},{},{},{}] size={}x{} alpha_sum={}",
        c.rect.left,
        c.rect.top,
        c.rect.right,
        c.rect.bottom,
        c.rect.right - c.rect.left,
        c.rect.bottom - c.rect.top,
        c.sum
    )
}

unsafe fn first_face(set: &IDWriteFontSet, fam: &str, w: i32) -> Option<IDWriteFontFace3> {
    let fonts = set
        .GetMatchingFonts(
            &HSTRING::from(fam),
            DWRITE_FONT_WEIGHT(w),
            DWRITE_FONT_STRETCH_NORMAL,
            DWRITE_FONT_STYLE_NORMAL,
        )
        .ok()?;
    if fonts.GetFontCount() == 0 {
        return None;
    }
    fonts.GetFontFaceReference(0).ok()?.CreateFontFace().ok()
}

unsafe fn run_inner(out: &str) -> windows::core::Result<()> {
    let factory: IDWriteFactory5 = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)?;
    let mut sys = std::mem::zeroed();
    factory.GetSystemFontCollection(false, &mut sys, true)?;
    let sys: IDWriteFontCollection1 = sys.unwrap();
    let sys_set = sys.GetFontSet()?;
    say!("DWSTART system font set faces={}", sys_set.GetFontCount());

    // Private font collection exactly like gpui's add_fonts (in-memory loader, builder, collection from the set).
    let loader = factory.CreateInMemoryFontFileLoader()?;
    factory.RegisterFontFileLoader(&loader)?;
    let builder = factory.CreateFontSetBuilder()?;
    let fonts_dir = std::env::var("F0_FONTS").unwrap_or_else(|_| "fonts".to_string());
    for name in [
        "Tinos-Regular.ttf",
        "SRProbeLatin-Regular.ttf",
        "SRProbeGreek-Regular.ttf",
    ] {
        match std::fs::read(std::path::Path::new(&fonts_dir).join(name)) {
            Ok(bytes) => {
                let data: &'static [u8] = Box::leak(bytes.into_boxed_slice());
                let file = loader.CreateInMemoryFontFileReference(
                    &factory,
                    data.as_ptr() as _,
                    data.len() as _,
                    None,
                )?;
                builder.AddFontFile(&file)?;
                say!("DWPRIVATE added {name} ({} bytes)", data.len());
            }
            Err(e) => say!("DWERR cannot read {name}: {e}"),
        }
    }
    let priv_set0 = builder.CreateFontSet()?;
    let priv_coll = factory.CreateFontCollectionFromFontSet(&priv_set0)?;
    let priv_set = priv_coll.GetFontSet()?;

    // 1. What gpui's face selection returns, family by family and weight by weight (select_font -> find_font_id).
    say!("DWSECTION 1 face selection as gpui does it (GetMatchingFonts, first face)");
    for fam in [
        "Segoe UI Variable",
        "Segoe UI Variable Text",
        "Segoe UI Variable Display",
        "Segoe UI Variable Small",
        "Segoe UI",
        "Cascadia Mono",
        "Consolas",
    ] {
        for w in [100, 200, 300, 350, 400, 500, 600, 700, 800, 900] {
            say!("{}", describe(&sys_set, fam, w, DWRITE_FONT_STYLE_NORMAL));
        }
    }
    for w in [400, 700] {
        say!(
            "{}",
            describe(&sys_set, "Segoe UI", w, DWRITE_FONT_STYLE_ITALIC)
        );
        say!(
            "{}",
            describe(&sys_set, "Segoe UI Variable", w, DWRITE_FONT_STYLE_ITALIC)
        );
        say!(
            "{}",
            describe(&sys_set, "Cascadia Mono", w, DWRITE_FONT_STYLE_ITALIC)
        );
    }
    for w in [100, 400, 700, 900] {
        say!(
            "{}",
            describe(&priv_set, "Tinos", w, DWRITE_FONT_STYLE_NORMAL)
        );
    }
    for w in [400, 700] {
        say!(
            "{}",
            describe(&priv_set, "Tinos", w, DWRITE_FONT_STYLE_ITALIC)
        );
    }
    // is a private family visible in the SYSTEM set (gpui's fallback builder only looks there)?
    say!(
        "{}",
        describe(&sys_set, "Tinos", 400, DWRITE_FONT_STYLE_NORMAL)
    );
    say!(
        "{}",
        describe(&sys_set, "SRProbeGreek", 400, DWRITE_FONT_STYLE_NORMAL)
    );
    say!(
        "{}",
        describe(&priv_set, "SRProbeGreek", 400, DWRITE_FONT_STYLE_NORMAL)
    );

    // 2. Variable-font axes and what a direct DirectWrite face can do (IDWriteFontResource::CreateFontFace with axis values).
    say!("DWSECTION 2 variable axes and rasters");
    let scale = 2.5f32;
    let size = 20.0f32;
    let text = "Hamburg";
    let mut sheet = Sheet::new(1100, 640);
    let mut row_y = 40;
    for fam in [
        "Segoe UI Variable Text",
        "Segoe UI Variable Display",
        "Segoe UI Variable Small",
        "Segoe UI Variable",
    ] {
        let Some(face) = first_face(&sys_set, fam, 400) else {
            say!("DWAXES family=[{fam}] not found");
            continue;
        };
        let f5: IDWriteFontFace5 = match face.cast() {
            Ok(f) => f,
            Err(e) => {
                say!("DWERR cast FontFace5 [{fam}] {e:?}");
                continue;
            }
        };
        let has = f5.HasVariations().as_bool();
        let res = match f5.GetFontResource() {
            Ok(r) => r,
            Err(e) => {
                say!("DWERR GetFontResource [{fam}] {e:?}");
                continue;
            }
        };
        let n = res.GetFontAxisCount() as usize;
        let mut ranges = vec![DWRITE_FONT_AXIS_RANGE::default(); n];
        let mut defs = vec![DWRITE_FONT_AXIS_VALUE::default(); n];
        let _ = res.GetFontAxisRanges(&mut ranges);
        let _ = res.GetDefaultFontAxisValues(&mut defs);
        let desc: Vec<String> = ranges
            .iter()
            .zip(defs.iter())
            .map(|(r, d)| {
                format!(
                    "{}:{}..{} default {}",
                    tag_str(r.axisTag),
                    r.minValue,
                    r.maxValue,
                    d.value
                )
            })
            .collect();
        say!(
            "DWAXES family=[{fam}] has_variations={has} axis_count={n} axes=[{}]",
            desc.join("; ")
        );
        // wght sweep at default opsz
        let has_axis = |t: DWRITE_FONT_AXIS_TAG| ranges.iter().find(|r| r.axisTag == t).copied();
        let mut col_x = 8;
        for w in [100.0f32, 300.0, 400.0, 500.0, 600.0, 700.0] {
            let mut vals: Vec<DWRITE_FONT_AXIS_VALUE> = Vec::new();
            if let Some(r) = has_axis(DWRITE_FONT_AXIS_TAG_WEIGHT) {
                vals.push(DWRITE_FONT_AXIS_VALUE {
                    axisTag: DWRITE_FONT_AXIS_TAG_WEIGHT,
                    value: w.clamp(r.minValue, r.maxValue),
                });
            }
            match res.CreateFontFace(DWRITE_FONT_SIMULATIONS_NONE, &vals) {
                Ok(fv) => match render_text(&factory, &fv, text, size, scale, None) {
                    Ok(c) => {
                        say!("{}", cell_line(&format!("family=[{fam}] wght={w} opsz=default text={text:?} size={size}dip scale={scale}"), &c));
                        sheet.blit(col_x, row_y + 40, &c);
                    }
                    Err(e) => say!("DWERR render [{fam}] wght={w}: {e:?}"),
                },
                Err(e) => say!("DWERR CreateFontFace(axes) [{fam}] wght={w}: {e:?}"),
            }
            col_x += 180;
        }
        row_y += 56;
        // opsz sweep at wght 400 (only where the face has the axis)
        if let Some(r) = has_axis(DWRITE_FONT_AXIS_TAG_OPTICAL_SIZE) {
            let mut col_x = 8;
            for o in [9.0f32, 28.0] {
                let vals = [
                    DWRITE_FONT_AXIS_VALUE {
                        axisTag: DWRITE_FONT_AXIS_TAG_WEIGHT,
                        value: 400.0,
                    },
                    DWRITE_FONT_AXIS_VALUE {
                        axisTag: DWRITE_FONT_AXIS_TAG_OPTICAL_SIZE,
                        value: o.clamp(r.minValue, r.maxValue),
                    },
                ];
                match res.CreateFontFace(DWRITE_FONT_SIMULATIONS_NONE, &vals) {
                    Ok(fv) => match render_text(&factory, &fv, text, size, scale, None) {
                        Ok(c) => {
                            say!("{}", cell_line(&format!("family=[{fam}] wght=400 opsz={o} text={text:?} size={size}dip scale={scale}"), &c));
                            sheet.blit(col_x, row_y + 40, &c);
                        }
                        Err(e) => say!("DWERR render [{fam}] opsz={o}: {e:?}"),
                    },
                    Err(e) => say!("DWERR CreateFontFace(axes) [{fam}] opsz={o}: {e:?}"),
                }
                col_x += 180;
            }
            row_y += 56;
        }
        if row_y > 560 {
            break;
        }
    }
    sheet.save_bmp(&format!("{out}\\dw-axes.bmp"));

    // 3. Simulations: the same Tinos Regular face with bold / oblique simulation on and off.
    say!("DWSECTION 3 simulations on a private Regular-only face");
    let mut sheet = Sheet::new(1100, 200);
    if let Some(face) = first_face(&priv_set, "Tinos", 400) {
        let fonts = priv_set.GetMatchingFonts(
            &HSTRING::from("Tinos"),
            DWRITE_FONT_WEIGHT(400),
            DWRITE_FONT_STRETCH_NORMAL,
            DWRITE_FONT_STYLE_NORMAL,
        )?;
        let r = fonts.GetFontFaceReference(0)?;
        let _ = face;
        let mut col_x = 8;
        for (name, sim) in [
            ("none", DWRITE_FONT_SIMULATIONS_NONE),
            ("bold", DWRITE_FONT_SIMULATIONS_BOLD),
            ("oblique", DWRITE_FONT_SIMULATIONS_OBLIQUE),
            ("bold+oblique", DWRITE_FONT_SIMULATIONS(3)),
        ] {
            match r.CreateFontFaceWithSimulations(sim) {
                Ok(f) => match render_text(&factory, &f, "Hamburg", 20.0, 2.5, None) {
                    Ok(c) => {
                        say!(
                            "{}",
                            cell_line(
                                &format!(
                                    "Tinos simulations={name} (flags {}) face_reports_sim={}",
                                    sim.0,
                                    f.GetSimulations().0
                                ),
                                &c
                            )
                        );
                        sheet.blit(col_x, 100, &c);
                    }
                    Err(e) => say!("DWERR render sim {name}: {e:?}"),
                },
                Err(e) => say!("DWERR CreateFontFaceWithSimulations {name}: {e:?}"),
            }
            col_x += 260;
        }
    }
    sheet.save_bmp(&format!("{out}\\dw-sims.bmp"));

    // 4. Rendering mode and grid fit gpui's create_glyph_run_analysis gets, by font, size and scale.
    say!("DWSECTION 4 GetRecommendedRenderingMode (gpui parameters: dpi 96, transform scale, NATURAL, outline threshold ANTIALIASED)");
    let mut faces: Vec<(String, IDWriteFontFace3)> = Vec::new();
    if let Some(f) = first_face(&priv_set, "Tinos", 400) {
        faces.push(("Tinos".to_string(), f));
    }
    for (name, fam, w) in [
        ("Segoe UI", "Segoe UI", 400),
        ("Segoe UI Variable Text", "Segoe UI Variable Text", 400),
        (
            "Segoe UI Variable Display",
            "Segoe UI Variable Display",
            400,
        ),
    ] {
        if let Some(f) = first_face(&sys_set, fam, w) {
            faces.push((name.to_string(), f));
        }
    }
    for (name, face) in faces.iter() {
        for sc in [1.0f32, 1.5, 2.0, 2.5] {
            let mut line = String::new();
            for pt in [
                9.0f32, 12.0, 13.0, 16.0, 18.0, 20.0, 24.0, 28.0, 31.0, 32.0, 36.0, 40.0,
            ] {
                let transform = DWRITE_MATRIX {
                    m11: sc,
                    m12: 0.0,
                    m21: 0.0,
                    m22: sc,
                    dx: 0.0,
                    dy: 0.0,
                };
                let mut rm = DWRITE_RENDERING_MODE1::default();
                let mut gf = DWRITE_GRID_FIT_MODE::default();
                let r = face.GetRecommendedRenderingMode(
                    pt,
                    96.0,
                    96.0,
                    Some(&transform),
                    false,
                    DWRITE_OUTLINE_THRESHOLD_ANTIALIASED,
                    DWRITE_MEASURING_MODE_NATURAL,
                    None,
                    &mut rm,
                    &mut gf,
                );
                match r {
                    Ok(()) => {
                        line.push_str(&format!(" {pt}pt(ppem {})=rm{}/gf{}", pt * sc, rm.0, gf.0))
                    }
                    Err(e) => line.push_str(&format!(" {pt}pt=ERR {e:?}")),
                }
            }
            say!("DWMODE font=[{name}] scale={sc}:{line}");
        }
    }
    say!("DWLEGEND rendering mode: 0 default 1 aliased 2 gdi_classic 3 gdi_natural 4 natural 5 natural_symmetric 6 outline 7 natural_symmetric_downsampled; grid fit: 0 default 1 disabled 2 enabled");

    // 5. Tinos 28 pt at 2.5 vertical placement: ink rows for baseline origins at fractional y (DirectWrite level, CreateGlyphRunAnalysis(baselineOriginY)).
    say!("DWSECTION 5 raster rows of Tinos 'H' at 28 dip, scale 2.5, baseline origin y = 0.0 .. 0.9 dip");
    if let Some(face) = first_face(&priv_set, "Tinos", 400) {
        let base: IDWriteFontFace = face.cast()?;
        let cps = ['H' as u32];
        let mut gi = [0u16; 1];
        base.GetGlyphIndices(cps.as_ptr(), 1, gi.as_mut_ptr())?;
        for k in 0..10 {
            let oy = k as f32 * 0.1;
            let adv = [0.0f32];
            let off = [DWRITE_GLYPH_OFFSET::default()];
            let glyph_run = DWRITE_GLYPH_RUN {
                fontFace: std::mem::transmute_copy(&base),
                fontEmSize: 28.0,
                glyphCount: 1,
                glyphIndices: gi.as_ptr(),
                glyphAdvances: adv.as_ptr(),
                glyphOffsets: off.as_ptr(),
                isSideways: BOOL(0),
                bidiLevel: 0,
            };
            let transform = DWRITE_MATRIX {
                m11: 2.5,
                m12: 0.0,
                m21: 0.0,
                m22: 2.5,
                dx: 0.0,
                dy: 0.0,
            };
            let mut rm = DWRITE_RENDERING_MODE1::default();
            let mut gf = DWRITE_GRID_FIT_MODE::default();
            face.GetRecommendedRenderingMode(
                28.0,
                96.0,
                96.0,
                Some(&transform),
                false,
                DWRITE_OUTLINE_THRESHOLD_ANTIALIASED,
                DWRITE_MEASURING_MODE_NATURAL,
                None,
                &mut rm,
                &mut gf,
            )?;
            let rm = if rm == DWRITE_RENDERING_MODE1_OUTLINE {
                DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC
            } else {
                rm
            };
            let an = factory.CreateGlyphRunAnalysis(
                &glyph_run,
                Some(&transform),
                rm,
                DWRITE_MEASURING_MODE_NATURAL,
                gf,
                DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE,
                0.0,
                oy / 2.5,
            )?;
            let r = an.GetAlphaTextureBounds(DWRITE_TEXTURE_ALIASED_1x1)?;
            say!("DWSNAP baseline_origin_y_dip={oy:.1} (phys {:.2}) rm={} gf={} bounds_top={} bounds_bottom={} height={}", oy, rm.0, gf.0, r.top, r.bottom, r.bottom - r.top);
        }
    }
    // 6. Does hinting explain the 28 pt ink box? "Pulse Hub" at scale 2.5: gpui's grid-fit mode (recommended) against grid fit DISABLED,
    // for the original Tinos, a copy with the hinting program removed and a copy whose gasp table asks for no grid fit.
    say!("DWSECTION 6 ink box of 'Pulse Hub' by grid-fit mode (half = alpha >= 128, rows relative to the baseline; height = bottom - top)");
    for fam in ["Tinos", "SRProbeTinosNoHint", "SRProbeTinosGasp"] {
        let Some(face) = first_face(&priv_set, fam, 400) else {
            say!("DWINK family=[{fam}] not found");
            continue;
        };
        for sz in [
            20.0f32, 24.0, 26.0, 27.0, 28.0, 29.0, 30.0, 31.0, 32.0, 36.0,
        ] {
            for (name, gf) in [
                ("recommended", None),
                ("disabled", Some(DWRITE_GRID_FIT_MODE_DISABLED)),
            ] {
                match render_text(&factory, &face, "Pulse Hub", sz, 2.5, gf) {
                    Ok(c) => {
                        let h = c.half.map(|b| b[3] - b[1]);
                        say!("DWINK family=[{fam}] size={sz} grid_fit={name} half={:?} half_height={:?} any=[{},{}] any_height={}", c.half, h, c.rect.top, c.rect.bottom, c.rect.bottom - c.rect.top);
                    }
                    Err(e) => say!("DWERR ink {fam} {sz} {name}: {e:?}"),
                }
            }
        }
    }
    say!("DWDONE");
    Ok(())
}
