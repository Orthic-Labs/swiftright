# F0: renderer text facts (gpui 0.2.2, DirectWrite) and E14c

Wave 0 lane F0 of the image and font foundations (`docs/foundations-images-fonts.md` section 4, F0). Probe only: no product behaviour changed. Decisions G10-G19 in `docs/sr1-decisions.md`.
Measured 15 October 2026 on the Dell through the Windows Sandbox (Windows 11 build 26100, "Microsoft Basic Render Driver", window scale 2.5, DPI 240), with a probe exe built in CI.

## How it was measured

- **Probe exe.** `probes/f0-text-facts` (standalone crate, same `gpui =0.2.2` pins as the renderer; workflow `.github/workflows/probe-f0-text.yml`, artifact `f0-text-facts-<sha>`). It is not a renderer and never replaces one. Final build: commit `1dc3502bc`, CI run 38688573898, exe sha256 `f3313af3959e6b6074067d1f9e39eaf41f01edd0f5a99fb6698535e410b08952` (earlier builds: runs 38685130216 `1045199e3`, 38687758296 `fcca05693`, 38688474485 `1e4b2e968`; one failed run 38687477561 was a compile error in my own code, fixed in the next commit).
- **Two halves.** `gp.rs` opens a real gpui window and paints one page (`F0_PAGE`) with `ShapedLine::paint` / `Window::paint_glyph`, exactly the renderer's calls, and writes an API trace (glyph ids, positions, resolved fonts, gpui's own log lines). `dw.rs` (`--dw`) calls DirectWrite directly, the way gpui does (`GetMatchingFonts`, `CreateFontFace`, `GetRecommendedRenderingMode`, `CreateGlyphRunAnalysis`) and then with the calls gpui does not make (axis values, simulations, grid-fit mode).
- **Capture.** The pipeline's own `factory/tools/pair/capture.ps1` (PrintWindow flags 3) through a Sandbox `command` job; staged under new names `D:\Claude\swiftright\.factory-work\inputs\probes\f0-<sha9>\` (no renderer or pinned DLL touched). Every page was captured 3 times in the final pass: 18 of 19 pages are byte-identical across the 3 runs; `e1` (emoji) differs in run 3. An earlier 2-run pass differed on `f1`, `g1`, `w1` by at most 18 pixels at most 21/255 (WARP rasteriser). No answer below depends on those pixels.
- **Evidence in this folder** (`docs/probes/f0-renderer-text-facts/`): `gpui-pages/<page>.png` + `.trace.txt` + `.runs.txt` (run digests), `directwrite/dw-trace.txt`, `dw-axes.png`, `dw-sims.png`, `e14c/*.ink-rows.json`, `e14c/pair-run.log`.
- **gpui source** (crate fetched 15 Oct 2026 from `https://static.crates.io/crates/gpui/gpui-0.2.2.crate`; paths relative to `gpui-0.2.2/src/`): `platform/windows/direct_write.rs` (DW), `window.rs`, `text_system.rs`, `text_system/line.rs`.
- **Microsoft sources** (fetched 15 Oct 2026): `IDWriteFontFallbackBuilder::AddMapping` (https://learn.microsoft.com/en-us/windows/win32/api/dwrite_2/nf-dwrite_2-idwritefontfallbackbuilder-addmapping): `fontCollection` is "optional explicit font collection for this mapping"; `gasp` table (https://learn.microsoft.com/en-us/typography/opentype/spec/gasp): `GASP_GRIDFIT` 0x0001, `GASP_DOGRAY` 0x0002, `GASP_SYMMETRIC_GRIDFIT` 0x0004, `GASP_SYMMETRIC_SMOOTHING` 0x0008.

## Answers, per capability

Each answer has a raster or an API trace; "gpui" = what the renderer can reach through gpui 0.2.2; "DW" = what DirectWrite itself does (proved by `--dw`).

### 1. Segoe UI Variable at wght 500 and 100, opsz 9 versus 28

- **gpui: NO for continuous axes. It snaps to named instances.**
  - Source: `Font` has family, features, fallbacks, weight, style only (`text_system.rs:787-804`). `get_font_id_from_font_collection` asks the font set `GetMatchingFonts(family, weight, NORMAL, style)` and takes the first face (`direct_write.rs:405-421`); the weight is cast to an integer (`direct_write.rs:1633-1636`); the layout then asks for the matched face's own weight (`direct_write.rs:578, 641`). Nothing passes axis values.
  - Trace (`directwrite/dw-trace.txt`, DWMATCH): `Segoe UI Variable Text` request 500 -> face weight 600 (Semibold; 400 is second); request 100/200 -> Light 300; 800/900 -> Bold 700. Raster/trace in gpui (`gpui-pages/w2.png`, `w2.trace.txt`): Text w500 and w600 have the same width (250.542 at 17 px) and look identical; w300 is the thinnest row; no row is thinner for 100.
  - Named instances on this build (family `Segoe UI Variable Text`): Light 300, Semilight 350, Regular 400, Semibold 600, Bold 700. The same for `Display` and `Small`. `Segoe UI` (static) additionally has Black 900 (so 800/900 map to Black there, `DWMATCH family=[Segoe UI] req_weight=800`).
- **opsz: NO, except by choosing a family.** The three families are named instances of one variable file with opsz 10.5 (`Text`), 36 (`Display`), 8 (`Small`) (DWMATCH axes). Same text at 9, 16 and 28 px gives a constant width per px in each family (`o2.trace.txt`: Text 7.64258, Display 7.63428 at all three sizes; `Small` 7.96533), so gpui does no automatic optical sizing.
- **Family name.** The bare family `Segoe UI Variable` does not exist in the system font set (`DWMATCH family=[Segoe UI Variable] count=0`); gpui logs `Segoe UI Variable not found, use Segoe UI instead` (`w1.trace.txt`) and draws static Segoe UI. F2 must name `Segoe UI Variable Text|Display|Small`.
- **Axis range on this build.** `wght` 300..700, `opsz` 5..36 (default 10.5), `wdth` 100..100 (`DWAXES`). The Microsoft page quoted in the design says wght 100-700; on this Windows build 100 and 200 do not exist even to DirectWrite (a request for 100 clamps to 300: identical rasters, `DWRASTER ... wght=100` = `wght=300`, alpha_sum 316623).
- **DW: YES.** `IDWriteFontResource::CreateFontFace(simulations, axisValues)` gives distinct rasters at wght 300/400/500/600/700 (alpha_sum 316623, 532576, 624621, 709209, 915271) and at opsz 9 vs 28 (558995 vs 535262, bounds 205 vs 200 px wide) (`dw-trace.txt`, `dw-axes.png`: columns wght 100..700, second row of each pair opsz 9 and 28).

### 2. Turn DirectWrite simulations (bold/oblique) off

- **gpui: NO switch, and simulations are ON by default.** `GetMatchingFonts` on the font set returns simulated faces when the requested weight or style has no real face: Tinos (Regular only) request 700 -> face weight 700 with `face_sim=1` (BOLD); italic -> `face_sim=2` (OBLIQUE); bold italic -> 3; Cascadia Mono italic -> sim 2; Consolas 600+ lists a simulated bold second (`dw-trace.txt` DWMATCH). gpui takes the first face and rasterises that face, simulation included (`direct_write.rs:415-421` then `create_glyph_run_analysis` with `font.font_face`, line 700+). Raster: `gpui-pages/s1.png`: Tinos w700 is visibly bolder and wider than w400, italic rows are slanted, bold italic is both; Tinos w100 equals w400 (no thin simulation).
- **Consequence.** The Mac does not synthesise (F1 decision G27: bundled single-face `.bold()`/`.italic()` draw the regular face). On Windows through gpui they would. 
- **Avoidable without a new text path:** request only weights and styles for which a real face exists (clamp weight/style before calling gpui). That needs the face list (real or simulated per entry: `face_sim`), which gpui does not expose (see 7). So: switch NO, avoidance YES with DirectWrite font-set enumeration in the renderer.
- **DW: YES** (`CreateFontFaceWithSimulations`; `DWRASTER Tinos simulations=none/bold/oblique/bold+oblique`: alpha_sum 492004 / 580489 / 490366 / 578772, `dw-sims.png`; `IDWriteFontSet4::GetMatchingFonts(familyName, axisValues, allowedSimulations)` exists).

### 3. Colour emoji

- **gpui: YES.** `gpui-pages/e1.png`: Segoe UI Emoji glyphs draw in full colour in a Segoe UI line, in a Tinos line (system fallback face), alone and at 40 px; Segoe UI Symbol glyphs stay black. Chroma>40 pixel counts: 5939, 6062, 6597, 12310 for the four emoji rows, 144 for the symbol row. Trace: `RUN ... emoji=N` per run; `ShapedGlyph.is_emoji` is set from `IsColorFont` + `TranslateColorGlyphRun` (`direct_write.rs:1689, 1845-1880`), drawn through `paint_emoji` and a COLR layer renderer (`direct_write.rs:853-1000`, "todo: support formats other than COLR").
- Limits seen: regional-indicator flags draw as the letters ("IN", no flag glyph on Windows); only COLR is handled.

### 4. `Font.fallbacks` with private (bundled) fonts

- **gpui: NO.** Source: `generate_font_fallbacks` looks every fallback family up in `self.system_font_collection.GetFontSet()` only (`direct_write.rs:324-376`, line 333) and skips a family it does not find. Trace: `GPUILOG ERROR gpui::platform::windows::direct_write: No matching font found for SRProbeGreek` (`f1.trace.txt`). Run trace: with the private fallback the Greek glyphs come from the same system face and glyph ids as with no fallback (font_id 0 "Segoe UI", glyphs 452 453); with `Times New Roman` (system) they come from another face (glyphs 533 534); Japanese with `MS Gothic` comes from another face (2102, 8334) while `Yu Gothic UI` and the private font give the default (23644, 1535). So `Font.fallbacks` works for system families (control) and is ignored for private ones. Raster `f1.png`.
- The fallback list is also applied only from the first run's font (`direct_write.rs:585`).
- DW can do it: `IDWriteFontFallbackBuilder::AddMapping` takes an optional explicit `IDWriteFontCollection` (Microsoft doc above), which gpui never passes.
- Workaround inside gpui (not tried): split the text by the primary face's cmap coverage and give each part its own `TextRun` font (gpui shapes per-run fonts). Needs coverage of the primary face.
- Negative control for "missing glyph": an unassigned code point (U+0378) in the Latin-only private font gives glyph id 0 (`notdef=1`, `f1.trace.txt`), so `.notdef` counts are available from gpui; but system fallback hides most missing glyphs before that.

### 5. Paint individual glyphs at chosen positions (tracking)

- **gpui: YES.** `Window::paint_glyph` and `paint_emoji` are public and take font id, glyph id, size and an arbitrary origin (`window.rs:2948-3050`); `ShapedGlyph.id/position/index/is_emoji` and `LineLayout.runs` are public (`text_system/line_layout.rs`). Raster `g1.png`: row B (every glyph painted by hand at the layout position) is the same picture as row A (`ShapedLine::paint`); row C (+4 px per glyph), row D (-1 px) and row E (Tinos +2 px) show tracking, the emoji glyph moves with them. Positions are per glyph, so `.tracking` per cluster works; subpixel x is kept (4 variants), y is not (see E14c).

### 6. `kern`=0 and `tnum`

- **gpui passes OpenType features through** (`apply_font_features`, `direct_write.rs:1725-1766`, to `IDWriteTypography`). Trace widths at 14 px (`k2.trace.txt`, `k2.png`): `Segoe UI Variable Text` default 188.624, `tnum=1` 202.077 (digits widen), `pnum=1` 188.624; `Sitka Text` default 208.351, `tnum=1` 214.996; so `tnum` and `pnum` are honoured. (On the static Segoe UI that the bare "Segoe UI Variable" name falls back to, digits are already tabular: `tnum=1` is a no-op there and `pnum=1` narrows, `k1.trace.txt`.)
- **Kerning is OFF by default in gpui 0.2.2 and `kern`=1 turns it on.** Tinos "AVAWAY To Wa 1111 0000 1010" at 14 px: default 200.245 = `kern=0` 200.245 (A->V advance equals A's natural advance, glyph x 10.11 apart); `kern=1` 187.995 (x 8.31). Segoe UI Variable Text: 188.624 default and `kern=0`, 182.472 with `kern=1`. Tinos's GPOS has real pairs (AV -264/2048 em). So `kern`=0 is honoured trivially (it is the default), and the Mac's default pair kerning needs an explicit `kern=1` in every run. Today's renderer passes no features, so Windows text is unkerned where the Mac's is kerned. Not isolated: why DirectWrite with an empty typography object omits `kern`.

### 7. What gpui cannot tell the renderer

- Which face a request resolved to. `TextSystem::get_font_for_id` returns the requested `Font`, not the face, and fallback faces return nothing (`request=(not a resolved request: fallback face)`, `f1.trace.txt`). `swr_text_run_faces` (face identity, simulation flags applied) therefore needs DirectWrite lookups in the renderer that repeat gpui's selection.

## E14c: the 28 pt custom-font ink box (1-2 px off the Mac)

Cases `factory/pipeline/blocks-f0/swiftui.font-custom/{title-28-extra-v1,title-sweep-a-v1,title-sweep-b-v1}` (Witness text `Pulse Hub`, bundled Tinos Regular, ScalePin-pinned Mac host, stage `9080b3139-e685b237`, pinned 0.7 baseline renderer, N=20 each, Sandbox). The half-coverage ink box (luminance <= 127, the text gate's rule) of every row is identical in all 20 runs on both sides. Windows minus Mac, pixels at scale 2.5 (l, t, r, b):

| size pt | row top pt | frame pt | delta (l,t,r,b) |
|---|---|---|---|
| 20 | 180 | 26 | 1, -1, 1, 0 |
| 24 | 20 | 30 | 0, 0, 0, -1 |
| 26 | 50 | 33 | 0, -1, 0, -1 |
| 27 | 83 | 34 | 0, 0, 1, -1 |
| 28 | 117 | 35 | 0, 0, 0, -1 |
| 28 | 20, 51, 83, 116, 150 | 31, 32, 33, 34, 35 | 0, -1, 0, -2 (all five) |
| 29 | 152 | 36 | 0, -1, 0, -1 |
| 30 | 20 | 37 | 0, 0, 0, -2 |
| 31 | 57 | 39 | 0, 1, 0, 1 |
| 32 | 96 | 40 | 0, -1, 0, -1 |
| 36 | 136 | 44 | 1, 0, 0, 0 |

So 28 pt is not the only size over the 1 px gate: 30 pt (bottom -2) is too; 28 pt fails on every frame height of line height + 0..4 pt (the layout-rule remainder is not the cause).

**Measured mechanism** (probe pages `e14a|b|c`, which repeat the product's arithmetic: Text at the frame top + (frame - lh)/2, paint origin shifted so the baseline lands on round(hhea ascent) from the line top as `text.rs baseline_placement` does; the Tinos column reproduces the pair's Windows boxes exactly in 13 of 15 rows, the other two by 1 px: `gpui-pages/e14a|b|c.png`, traces `E14 ...`):

1. **Rendering mode.** DirectWrite's recommended mode for Tinos is NATURAL_SYMMETRIC (5) with grid fit ENABLED (2) at every size 9-36 pt and every scale 1-2.5 (ppem up to 90); at ppem 100 (40 pt at 2.5) it is outline (6) with grid fit disabled, which gpui maps to NATURAL_SYMMETRIC without grid fit (`direct_write.rs:731-752`). Segoe UI Variable turns grid fit off from ppem 56. 28 pt (70 ppem) is not a mode boundary. Tinos' `gasp` is {65535: 0x000F} (grid fit + grayscale + symmetric), its outlines carry a ttfautohint program. (`dw-trace.txt` DWMODE.)
2. **Grid fitting contributes up to 1 px per edge.** Same outlines, only the `gasp` flags changed to 0x000A (no grid fit; derivative font `SRProbeTinosGasp`, family renamed, OFL): the 28 pt rows change from (-1,-2) to (0,-1) against the Mac, and over the ten sizes the worst edge error falls from 2 px to 1 px. A copy with the hinting program removed as well (`SRProbeTinosNoHint`) gives identical rasters to the gasp-only copy: the gasp flag alone decides it. Per size, unhinted Windows minus Mac: 24: (-1,-1), 26: (0,0), 27: (-1,-1), 28: (+1,0) at row 117, 29: (0,0), 30: (0,-1), 31: (0,0), 32: (0,-1), 36: (+1,0), 20: (0,0); 28 pt at the five frame heights: (0,-1) each.
3. **Vertical snapping of the line origin.** `SUBPIXEL_VARIANTS_Y` is 1 on Windows (`text_system.rs:44-51`) and the glyph origin is floored (`window.rs:2985`), so the baseline is a whole device pixel. The probe `snap.png` (28 px `H` at origin y 12.0 .. 12.9 step 0.1) steps at fractional offsets 0.4 and 0.8 exactly where `floor(baseline_phys)` changes (`SNAP` lines: 105,105,105,105,106,106,106,106,107,107). The renderer's baseline lands on `round(hhea ascent) * 2.5` below the line top, a half pixel when that number is odd (25 pt = 62.5 px): the `E14` lines show baselines at x.5 or x.25 ties for 11 of the 15 rows (e.g. 112.5, 191.25, 272.5, 356.25, 442.5 for the five 28 pt frames), all floored. DirectWrite honours fractional y (`DWSNAP`: bounds change at 0.2 px) but gpui never passes it.
4. **Remaining difference (not isolated).** With grid fit off the 28 pt Windows ink is still 1 px short at the bottom against the Mac (the Mac ink is 50 px tall, Windows 49; the raw DirectWrite alpha at half coverage is 50, `DWINK ... half_height=50`). gpui applies DirectWrite's gamma ratios and enhanced contrast to grayscale glyphs in its pixel shader (`platform/windows/shaders.hlsl:1118`, `alpha_correction.hlsl`), which shifts what counts as half coverage; I did not separate that from rounding.
- **What fixes what, not applied:** (a) a `gasp` patch on bundled OFL fonts (grid fit off) removes the hinting part (worst edge 2 -> 1 px) at no renderer change, but cannot touch Windows system fonts or a font whose licence forbids modification; (b) rounding the baseline to nearest instead of floor would move the half-pixel ties by 0.5 px (probe data allow this estimate only; changes every text origin and is F2's rebaseline); (c) own DirectWrite raster with grid fit disabled would bypass gpui's atlas. None reaches 0 px on all sizes: the best measured state is max 1 px per edge (G10).

## Verdict for F3 (ABI 0.8 text extension)

| Capability | gpui 0.2.2 | needs DirectWrite in the renderer? |
|---|---|---|
| Continuous wght / opsz / wdth, bundled variable fonts by axis | NO (named instances; opsz by family; wght 500 -> 600, 100 -> 300) | **yes, for runs that use an axis value off the named instances** |
| Simulation control | no switch, implicit | **a face resolver (font-set enumeration) to clamp requests to real faces**; own face creation only with the axis path |
| Colour emoji | YES | no |
| Fallback with private fonts | NO | **yes** (`IDWriteFontFallbackBuilder` with the private collection), or renderer-side run splitting by cmap coverage |
| Glyph-positioned paint (tracking) | YES | no |
| `kern`, `tnum`, `pnum` features | YES (kern must be set to 1: default off) | no |
| Per-run face identity, `.notdef` count | glyph id 0 yes; face identity NO | **resolver** |
| Hinting / grid-fit mode (E14c) | no control (font `gasp` only) | optional |

**F3 does not need its own DirectWrite text-run pipeline for tracking, kerning, features or emoji: gpui shapes and paints those.** F3 does need DirectWrite inside the renderer in two sizes: (1) a small **face resolver** (font-set enumeration, named instances, axis ranges, simulation flag per face, PostScript name and version) that feeds `swr_font_face_metrics`, `swr_system_font_info`, `swr_text_run_faces`, the simulation clamp and the weight mapping; this does not replace gpui's text path. (2) An **own DirectWrite run path (layout + raster)** only for runs that ask for a wght/opsz/wdth value off the named instances or for fallback chains containing private fonts. Defaults that keep (2) out of F3: F2 maps SwiftUI weights to the named instances (medium -> Semibold or Regular, by decision), ultraLight/thin -> Light 300 (the axis does not go below 300 on this build), heavy/black -> `Segoe UI` Black; bundled variable fonts are instanced to static files at build time (open licences only; Windows fonts must not be converted, design source S8); private fallback by run splitting. If Adrian wants exact 500, bundled variable fonts at run time, or private fallback chains inside one run, (2) is a separate renderer block (F3b), larger than the rest of F3.

## UNKNOWN or not measured

- A private **variable** font through gpui (none bundled; the API has no axis field either way).
- Why DirectWrite with gpui's empty typography object does not kern by default (observed, cause not isolated); whether gpui's gamma/contrast shift explains the last 1 px of E14c.
- Other scales than 2.5 for rasters (`DWMODE` covers 1, 1.5, 2, 2.5 for the mode only); other Windows builds (Segoe UI Variable axis ranges differ from the Microsoft page: wght 300..700 here).
- No Mac probe was run for the text facts (they are Windows facts); the Mac side of E14c is the pair runs' offscreen host.
- The probe pages were captured at N=3; E14c pair cases at N=20.
