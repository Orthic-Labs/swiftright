# Foundations: image processing and fonts

Status: design decision, 15 October 2026 (Sage). It answers Adrian's question "better to have proper image processing yeah? and fonts?" Yes. Images and fonts become foundations: each is one pipeline with one owner, one contract and one gate rule. Further per-case blocks build on them instead of adding special cases. The design comes before any ABI or renderer work. Implementation can start now with the blocks in section 4, which are in dependency order.

Inputs read: `docs/architecture.md` §4, §5, §8, §11; `docs/sr1-plan.md` "Foundations"; `factory/abi/abi-0.7-proposal.md`; `docs/sr1-decisions.md` (decisions 1-5, E12, E14, F5-F16); `docs/pulse-hub-windows-port.md` (R1-R12); `packages/SwiftRightHost` (`ImageDecoder`, `PNGDecoder`, `ResolvedNodePainter`, `BridgeTextMeasurer`, `SystemImages`); `probes/sr0-s/fresh-runtime` (`Controls.swift`, `NativeWindowsBodyFont.swift`); `render/swiftright-render/src/{lib,view,text,font}.rs`; `render/swiftright-abi/include/swiftright.h`.

External facts are cited in the "Sources" section with their fetch date. A statement marked **(unverified)** has no fetched source. It is either measured by a block below or must not be relied on.

---

## 0. Where things stand (inspected, not recalled)

- **Image path today.** The renderer has accepted retained RGBA8 images since rev 0.6 (`swr_image_register`). The input is straight alpha, byte order R,G,B,A, limited to 8192 px a side, 64 MiB per image and 4096 live images. `SWR_PRIM_IMAGE` draws an image "scaled to fill rect" with a corner radius. In `lib.rs` the renderer swaps the bytes to BGRA and wraps them in `gpui::RenderImage`; `view.rs` draws them with `window.paint_image(bounds, corners, img, 0, false)`. The GPU sampler then does any scaling. Neither the ABI nor gpui's public documentation says whether gpui expects premultiplied alpha (unverified, see T0).
- **Block 35 (in progress, another lane)** added `RGBAImage` (straight-alpha RGBA8 with an FNV-1a 64-bit `contentID`), `Image(decorative:scale:)`, `resizable(capInsets:resizingMode:)` and `scaledToFit` to the runtime. The host has a pure-Swift PNG and ICO decoder (`ImageDecoder`, `PNGDecoder`, `Inflate`) and a premultiplied box-filter downscale. Its intended client is the hub's `HubPlatformServices.decodeImage(_:maxPixel:)`.
- **Text path today.** The renderer (gpui 0.2.2 DirectWrite) shapes, measures and rasterises text. The host sends a family name, weight, size, line height, locale and colour (`MeasureRequest`). ABI 0.7 added private bundled-font registration (`swr_font_register` / `swr_font_resolve`). The body font is the live Windows message font (`NativeWindowsBodyFont`): Segoe UI at 12 DIP. Its line height uses the CoreText rule round(ascent) + round(descent) over the face's hhea table. The text styles in `TextRequestAdapter.textStyles` are the macOS sizes multiplied by 12/13. `caption2` is listed as Regular, but Apple's table says Medium (see 2.1). Designs other than default are refused. Neither the runtime nor the ABI has tracking or kerning. Only Tinos Regular is bundled. A 28 pt custom-font title is 1-2 px off (E14c).
- **RightKit ownership.** `rightkit owns` found no owner for image, image-decode, image-processing, font, fonts, font-registration, typography, text-rendering or icon (run 15 October 2026). The closest owners do not fit:
  - `media-ui` is a web image viewer published on npm.
  - `media-pipelines` covers FFmpeg artifacts.
  - `disk-cache` (`rightkit-cache`, a Rust disk cache) is relevant only if images ever get a disk cache (not planned, see 1.6).
  - `http-client` (`rightkit-http`) is Rust. `AsyncImage` follows SwiftUI's URLSession semantics instead (1.5).

---

## 1. Images

### 1.1 Ownership and decoder: WIC in the SwiftRight host

**Decision.** Decoding is a SwiftRight platform service in Swift, owned by `SwiftRightHost` (Windows) and backed by the **Windows Imaging Component (WIC)**. On the Mac the same service interface is backed by ImageIO (`CGImageSource`). The renderer stays a pixel sink: it receives decoded, sized pixels and paints them. It never decodes.

Why:
- **Architecture fit.** §4 puts OS-backed services behind Swift platform-service interfaces. The renderer's role is "paint, text measurement, input, AccessKit". Decoding is an OS service on both platforms (ImageIO and WIC). Neither platform needs a new crate.
- **Formats and security.** WIC ships BMP, GIF, ICO, JPEG, PNG, TIFF, DDS, DNG, HD Photo and JPEG XR built in. HEIF, WebP and RAW are extension codecs, and WebP and RAW come from the Store [S1]. Windows Update patches the codecs, so SwiftRight carries no parser code for untrusted network images.
- **No ABI change, no renderer rebuild.** The renderer is built only by CI on this public repository. Putting decoding in the host keeps every image block off the CI loop.
- **Rejected: Rust `image` crate in the renderer.** The renderer already links `image =0.25.10` with default features off. Using it for decoding would need a new export, keep the parsers in our own supply chain, and give no colour management.
- **Rejected: pure Swift for every format.** The block 35 PNG/ICO decoder is fine for the hub's icons. Writing JPEG, GIF and ICC handling by hand would make SwiftRight own image parsers. A malformed file would also trap the process on a bounds check instead of returning an error.
- **Block 35 keeps its decoder.** Its PNG/ICO decoder stays until I1 lands, so the hub is not blocked. I1 then replaces only the decode step behind the same `decode(_:maxPixel:)` API. The ICO entry-selection rule and the `maxPixel` rule move into the policy layer above WIC. After that the Swift decoder is deleted, because two decoders for one format would be two owners of one behaviour.

**Owner check against the workspace rule.** No RightKit owner exists, so this is a gap. Every SwiftRight app gets decoding through the SDK, which makes the SDK the single owner for SwiftRight apps. Creating a RightKit owner would mean a RightKit change, which needs Adrian (see "Choices for Adrian").

**Formats.** Supported means gated (section 4). Recognised means decoded if the OS has the codec, but not gated.

| Format | Status | Notes |
|---|---|---|
| PNG (all bit depths, palette, grey+alpha, Adam7, 16-bit) | supported | lossless, so gated byte-exact against ImageIO |
| JPEG (baseline, progressive, CMYK, EXIF orientation) | supported | IDCTs differ between decoders, so a named, measured tolerance applies (1.4) |
| ICO (PNG and DIB entries) | supported | entry chosen by the block 35 `maxPixel` rule |
| BMP (24/32-bit, alpha) | supported | lossless |
| GIF | supported, first frame only | animation is out of scope; Mac `Image` also shows one frame (unverified, measured in I1) |
| TIFF | recognised | not gated until an app needs it |
| HEIC/HEIF, WebP, AVIF | recognised only when the codec is installed | HEIF is an extension codec [S1]; when no codec is present the decode throws `unsupported`, never returns a blank image |
| SVG, PDF vectors | not supported | needs the vector-path foundation (sr1-plan); refused visibly |

**Public surface.** Shared source must compile on both platforms. The type is therefore `CGImage`-shaped:
- The Windows runtime declares `public final class CGImage` in `SwiftRightUI`, backed by `RGBAImage`, with `width`, `height`, `bitsPerComponent` (8), `alphaInfo` and `colorSpaceName` (sRGB).
- A shared decode entry, `SwiftRightImageIO.makeImage(data:maxPixel:) throws -> CGImage`, maps to `CGImageSource` on the Mac and to WIC on Windows.
- `Image(decorative: CGImage, scale:orientation:)` and `Image(_ cgImage:scale:orientation:label:)` are inventory.
- `Image(nsImage:)` is a Mac-only platform extension. Any other CoreGraphics API on Windows is an unsupported API with a compile diagnostic (§5 categories).
- The hub's `decodeImage` returns `CGImage` on both platforms.

### 1.2 Colour, premultiplied alpha and the transparency bug class

- **One working space.** Pixels are 8-bit sRGB, top-left origin.
  - The decoder converts an embedded ICC profile (for example Display P3 photos) to sRGB with WIC's colour transform. Untagged images are treated as sRGB on both platforms.
  - Out-of-gamut P3 colour is clipped on Windows. Wide-gamut and HDR output are out of scope.
  - The Mac capture path's colour space is not recorded anywhere I could find (**unknown**). I0, the first step of I1, measures it before any colour tolerance is set: a P3-tagged image versus the same image tagged sRGB, captured on the Mac.
  - The rendering intent CoreGraphics uses is also unverified. I1 measures it and sets the WIC transform to match.
- **One conversion point for alpha.** Every host image type carries its alpha mode in the type, so no function has to guess:
  - `RGBAImage` stays straight alpha, as the ABI contract requires.
  - Resampling, compositing (tint, mask, 9-slice) and clipping are done premultiplied in host buffers and converted back once, at registration.
  - A pixel with alpha 0 has RGB 0 after any operation, so a transparent pixel never bleeds colour. Block 35's resampler already follows this rule.
  - If T0 shows that gpui's sprite pipeline expects premultiplied input, the renderer premultiplies in `swr_image_register`. That is an implementation fix under the existing straight-alpha contract, with no ABI change.
- **The transparency bug class.** R12 is the case where `Color.clear` and `opacity(0.001)` reach the screen as opaque black, which is still unexplained. The same class covers alpha-0 bleed, double premultiplication (fringes too dark) and missing premultiplication (fringes too bright).
  - **T0 goes first.** No image pixel gate is trustworthy until the alpha path is proven.
  - Hypotheses to test, all **unverified**: a default `border_color` of `0x000000FF` drawn with a non-zero width; a continuous-shape raster path returning alpha 255; and gpui blending a straight-alpha sprite as if it were premultiplied.

### 1.3 SwiftUI surface and how it is drawn

**Rule: the host produces device-pixel-exact pixels.** For every image node the painter computes the destination rectangle in device pixels, using the existing `DevicePixelSnap` rule. It then builds one buffer at exactly that size, already resampled, tinted, 9-sliced or tiled, and masked, and registers it. The renderer draws that buffer 1:1, so GPU sampling never decides a gated pixel. The resampling filter is ours, chosen to match the Mac (1.4). No ABI change is needed.

| API | How it is delivered |
|---|---|
| `Image(decorative:scale:orientation:)`, `Image(_:scale:orientation:label:)` with `CGImage` | intrinsic size = pixels / scale; orientation applied at decode (EXIF) or at build (the parameter) |
| `Image(_ name:)` from the bundle | I8. The imageset's `Contents.json` gives the @1x/@2x/@3x variants, `template-rendering-intent` and appearance variants. The scale-variant choice at 1.25-2.5x is measured against the Mac, not assumed. Vector imagesets are refused (needs paths). |
| `.resizable(capInsets:resizingMode:)` | 9-slice built on the host: caps copied 1:1 when the scale allows, centre stretched or tiled. The tile phase origin is measured (I4). |
| `.interpolation(.none/.low/.medium/.high)` | chooses the host filter. Each level's filter is fitted to Mac captures (1.4). `.none` is nearest-neighbour and exact. |
| `.antialiased(_:)` | edge coverage of the destination rectangle when it is not pixel-aligned (measured) |
| `.renderingMode(.template/.original)` | template = the image's alpha × the resolved foreground style, composited premultiplied on the host. Symbols keep their own path (decision 3, F5-F16). |
| `.aspectRatio(_:contentMode:)`, `.scaledToFit()`, `.scaledToFill()` | layout in the runtime (already partly there); the painter uses the resolved frame |
| `.clipped()`, `.clipShape(...)`, `.cornerRadius` on images | rectangle clip through the existing `CLIP_PUSH`; shape clips baked into the image as an alpha mask with the existing continuous-shape rasteriser (I5) |
| `AsyncImage(url:scale:transaction:content:)`, `AsyncImage(url:)` with `.empty/.success/.failure` phases | I6. Foundation `URLSession.shared` on both platforms (SwiftUI's own contract), decoded off the main actor, registered on the UI thread |

**Transient path for live resize and animation.** Building a new buffer for every frame of a window resize or a frame animation would break the §11 budget of 2 ms p95 bridge time per frame. During those changes the painter keeps the last registered variant and lets the renderer scale it on the GPU. It rebuilds once the size has been stable for one frame. This is documented as a transient difference. Gated pixels are captured settled.

### 1.4 Pixel parity: exact where possible, otherwise a named and measured resampling tolerance

- **Exact** (byte-equal outside decision-5 edge bands):
  - 1:1 drawing (image pixels = device pixels);
  - `.interpolation(.none)` at integer ratios;
  - template tint on fully covered pixels;
  - 9-slice caps drawn 1:1;
  - every decode of a lossless format (compared as buffers, not captures).
- **Named resampling tolerance** applies to any other scale ratio and to JPEG decode. CoreGraphics' filters are not published, so exact equality would be a false goal.
  1. **Calibration.** A corpus of photo, line-art, text-in-image, alpha-edge and checkerboard images, at ratios 0.33, 0.5, 0.66, 0.8, 1.25, 1.5, 2.5 and 3, with fractional destination origins. The Mac is captured at scale 2.5.
  2. **Filter fit.** For each interpolation level, candidates are box, triangle, Catmull-Rom, Mitchell and Lanczos-3, in premultiplied gamma-encoded space and in linear space. The one with the lowest error against the Mac wins. That filter and its error are recorded as `resampleFilter[level]`.
  3. **Tolerance.** The gate is per pixel ≤ `resampleMaxPerChannel` and mean ≤ `resampleMeanPerChannel`, plus exact frame and edge positions. The numbers are the calibration maxima, rounded up once. Each one appears in `pair.json` with `resampleToleranceReason`, like decisions 12-19. The calibration set and the gating set are different images.
  4. **Negative controls** must fail: nearest-neighbour where `.high` is asked; a straight-alpha resample (a dark fringe on an alpha edge); a 1 px translation; a swapped R/B channel.
- **JPEG** gets its own tolerance, measured the same way between WIC and ImageIO decodes of the corpus. It is stated separately from the resampling tolerance.
- **Measured in I2 (15 October 2026; decisions G50-G59).** The Mac oracle for interpolation is SwiftUI's `ImageRenderer`, not the `NSHostingView` bitmap path: that path draws all four levels with one bilinear filter. On `ImageRenderer` the fit is: `.none` nearest (floor of the pixel centre), `.low` and the default bilinear, point-sampled (not widened on a reduction), `.medium` the same after 2 x 2 box halvings while the reduction is over 2:1, `.high` those halvings then a cubic with Mitchell-Netravali (B, C) = (0.72, 0.12). None of the five named candidates fits `.high` (best named: triangle, max 112); the parametric cubic does (max 8). `.high` at 1:1 smooths (it is not the identity), so only the other levels are exact at 1:1. The Mac does not use the unsnapped frame as the sample scale: the whole source maps onto the snapped rect.

### 1.5 AsyncImage

`URLSession.shared` with default caching, as SwiftUI's `AsyncImage` uses on the Mac. `rightkit-http` is not used: the contract is SwiftUI's, and the app's own HTTP stays the app's choice. Tests use a stub `URLProtocol` with three gates:
- the phase sequence: empty, then success or failure;
- a cancellation test, where the view disappears before completion and no commit follows;
- the transaction animation on the phase change.

### 1.6 Cache and memory budget

- **Level 1, decoded sources.** Keyed by `contentID` plus dimensions. Default budget 64 MiB, LRU. `maxPixel` thumbnailing at decode keeps icons small.
- **Level 2, registered size variants.** Keyed by (contentID, device-pixel size, interpolation, rendering mode and tint, cap insets, clip-mask id). Default budget 96 MiB, LRU, tracked as renderer-side bytes against `SWR_IMAGE_MAX_BYTES` and `SWR_IMAGE_MAX_LIVE`.
- **Eviction rules.** Neither level evicts an entry that the committed tree references. Eviction calls `swr_image_release`.
- **Collision guard.** `RGBAImage` equality uses only the 64-bit hash. A cache hit therefore also compares byte counts and samples pixels, and does a full compare when its cost is under the decode cost. Collisions are improbable, but a wrong image must never be shown silently.
- **No disk cache in v1.** Re-decoding is cheap compared with a cache to keep invalidated. `rightkit-cache` is the owner if one is ever needed.
- **Instrumentation.** Following the workspace rule, the cache emits structured lifecycle events (hit, miss, evict, register, release, bytes) through the host log.
- **Budgets are defaults, not measured results.** I7 measures them against §11's memory limit (steady-state process tree ≤ 110 % of the baseline) on the hub's icon load, and freezes them or records a contract revision.

---

## 2. Fonts

### 2.1 System font mapping

**Decision: point-for-point sizes, Mac vertical metrics, Windows glyphs.**
- `Font.body` is 13 DIP on Windows, as on the Mac. It is no longer the 12 DIP system message font.
- Every text style has the macOS size and weight from Apple's table [S2]: largeTitle 26 Regular, title 22, title2 17, title3 15, headline 13 Bold, body 13, callout 12, subheadline 11, footnote 10, caption 10 Regular, caption2 10 **Medium**. The 12/13 scaling in `TextRequestAdapter.textStyles` is removed, and caption2 is corrected after F1 measures it.
- Line height, ascent, descent and first baseline come from a table measured on the Mac (F1). Apple's table gives the line heights: 32, 26, 22, 20, 16, 16, 15, 14, 13, 13 and 13 [S2].
- Segoe glyphs are placed on the SF baseline.
- Result: `Font.system(size: 13)` and `.body` agree on Windows as they do on the Mac, so layout heights match the Mac exactly. Only advance widths (the glyphs themselves) differ, and decision 2 already judges those semantically.
- This reverses the 12 DIP body. It moves the measured text-origin deltas of decisions 14 and 19, so those cases are rebaselined in F2. It is listed under "Choices for Adrian" because it changes what Windows users see. The default proceeds unless he overrides it.

**Families.**
- **Windows 11 (Segoe UI Variable present).** Segoe UI Variable has a `wght` axis from 100 to 700 and an `opsz` axis from 8 to 36 pt that follows the font size automatically. It has no width axis [S3]. It was added in Windows 11 [S4].
  - SwiftUI weights map to `wght` directly: ultraLight 100, thin 200, light 300, regular 400, medium 500, semibold 600, bold 700.
  - heavy (800) and black (900) have no Variable instance and map to static **Segoe UI Black** (900) [S4]. heavy is therefore an adapted entry: drawn at 900 and reported.
  - Whether gpui 0.2.2 can select continuous `wght` values and the right `opsz` instance is **unverified**: gpui's `Font` has only family, features, fallbacks, weight and style [S5]. F0 decides this. If gpui cannot, the fallback is the static Segoe UI faces below, on Windows 11 too, until the renderer gains axis control (F3).
- **No Segoe UI Variable (Windows 10, or Variable missing).** Static Segoe UI has Light 300, Semilight 350, Regular, Semibold, Bold and Black [S4]. Nearest weights: ultraLight and thin → Light; medium → Semibold; heavy → Black. Each substitution is reported. Windows 10 reached end of support on 14 October 2025 [S6]. Supporting it is Adrian's call (see "Choices for Adrian").
- **Designs.**
  - `.monospaced` → **Cascadia Mono**, which shipped with Windows 11 in ExtraLight to Bold [S4]. **Consolas** is the fallback where Cascadia is absent.
  - `.serif` → **Sitka**, a variable optical-size serif, the closest analogue to New York [S4].
  - `.rounded` → adapted: default design, reported. Windows has no rounded system face, and an app may bundle an open-licensed one and map it through `Font.custom`.
  - `monospacedDigit()` → the OpenType `tnum` feature. Whether Segoe UI's default figures are already tabular is **unverified** (F5).
- **Widths.** `Font.width(.condensed/.compressed/.expanded)` has no Segoe equivalent [S3]. Bahnschrift has weight and width axes [S3], but it is a different (DIN-style) design. Default: the standard width, reported as adapted. This also covers the hub's G14. The alternative is a choice for Adrian.

### 2.2 Bundled and app fonts

- **Registration (ABI 0.7, extended).** At launch the host registers every font file from the app bundle (`Fonts/` and the resource directories the manifest names; the Mac counterpart is `ATSApplicationFontsPath`). Registration is private to the process, through gpui's DirectWrite in-memory font set. DirectWrite's in-memory loader exists from Windows 10 build 15063 [S7]. Fonts are retained for the life of the process, as 0.7 already documents.
- **`Font.custom(name, size:)` lookup** is host-side over the parsed `name` table: PostScript name (ID 6), then full name (ID 4), then typographic family (ID 16, then 1). This is the order to confirm on the Mac in F4 (**unverified**). Parsing stays in Swift. The renderer reports which family each face registered as (0.7) and, from 0.8, the per-run resolved face identity.
- **Weights and italics of a bundled family** select the real face when one is registered. When none is, Windows must do what the Mac does. Whether CoreText synthesises bold or oblique for a missing face is **unverified**, and F4 measures it. DirectWrite can simulate bold and oblique, so the renderer needs a control to allow or forbid simulation: an ABI 0.8 field (2.5).
- **Licences.** Only open-licensed fonts are bundled: Tinos (pilot). Segoe UI, Segoe UI Variable and SF Pro are never bundled. Tanker is not bundled until its licence is confirmed (2.6).

### 2.3 Fallback chains and variable axes

- **Fallback** is DirectWrite's system fallback, steered by the run's locale. The `locale` field already exists in the measure request. Expected chain, from Microsoft's per-script guidance [S3]:
  - Japanese → Yu Gothic UI
  - Simplified Chinese → Microsoft YaHei UI
  - Traditional Chinese → Microsoft JhengHei UI
  - Korean → Malgun Gothic
  - South Asian scripts → Nirmala UI
  - emoji → Segoe UI Emoji
  - symbols → Segoe UI Symbol

  An app can prepend a family list (gpui's `Font.fallbacks` [S5]; exposed in ABI 0.8). Whether gpui 0.2.2 on Windows draws colour emoji glyphs is **unverified** (F0).
- **Mixed-script lines.** What CoreText does to line height when a fallback face is taller is **unverified**. F6 measures it. The Mac number becomes the metric for that case.
- **Variable axes** are requested as numbers (wght, wdth, opsz, ital/slnt) in ABI 0.8, so bundled variable fonts work without one named instance per weight.

### 2.4 Tracking, kerning and bold of bundled fonts

- `.tracking(_:)` adds the value after every glyph cluster. `.kerning(_:)` adjusts the pair kerning. Both match SwiftUI's definitions.
- gpui has no letter-spacing [S5]. The renderer therefore gets a glyph-positioned paint path: shape with gpui, add tracking per cluster, paint the glyphs at the adjusted positions. `kern` on and off goes through OpenType features.
- This is renderer work behind ABI 0.8 (F3). The runtime adds the modifiers and passes the values through.
- System-font tracking is semantic (different glyphs). Bundled-font tracking is metric-gated, because the font bytes are the same on both sides (2.5).
- Default SF tracking, which CoreText applies per size, is not copied: Segoe has its own spacing, and the width stays semantic.

### 2.5 How text is judged under decision 2 (refined)

Source of truth: SwiftUI and CoreText on the Mac oracle of record (macOS 27 today), measured by F1's tool and stored as data. These are numbers about layout, not font software, as with the symbol tables of F5 and F14.

| Kind | System font (Segoe stands in for SF) | Bundled font (same bytes both sides) |
|---|---|---|
| Line height, Text frame height, first and last baseline, `firstTextBaseline` alignment | **metric-gated, exact in points** (from the F1 table) | metric-gated, exact |
| Ink top and baseline in pixels | gated within the decision 14/19 tolerances (to be re-measured at 13 DIP) | ink box within 1 px per edge (E12) |
| Advance, string width, glyph x positions | **semantic** (reported as a width ratio) | **gated within 1 px** per glyph, including tracking and kerning |
| Line count, truncation, ellipsis, alignment, colour | semantic (decision 2) | semantic plus pixel |
| Glyph shapes | reported, excluded and named | exact outside edge bands (decision 5) |
| Fallback | semantic: no `.notdef` glyphs (count from the renderer's per-run info); the resolved family is in the declared chain for the locale | same |
| Face identity | the resolved family and face hash per run are recorded in the run log | the per-run face hash must equal the registered file's SHA-256 |

No tolerance is applied silently. Every excluded region and every non-zero tolerance is named in `pair.json` with a reason.

### 2.6 What stays as is

- Decision 3 (symbols → Segoe Fluent Icons) and the symbol tables (F5-F16) are unchanged. Symbols are drawn by the text pipeline and inherit F2's sizes.
- The ABI 0.7 font subset is unchanged. 0.8 appends after the 0.7 entries and before the held frame and readback entries, keeping their order.

---

## 3. ABI shape: additive 0.8 versus host-side

**Images: no ABI change.** Decoding, colour conversion, resampling, 9-slice, tiling, tint, shape masks and caching all live in the host. The existing `swr_image_register` (straight alpha) and `SWR_PRIM_IMAGE` are enough. Two items are **held** for the affine-transform foundation, where GPU scaling becomes the normal path: a per-primitive sampling filter (nearest or linear) and a source rectangle. They are not added now.

**Fonts: ABI 0.8, additive.** New `_v08` bootstrap and API exports follow 0.7's pattern of symbol-name negotiation, `struct_size`-versioned structs and refusal of a half-exported renderer. 0.6 and 0.7 hosts run unchanged.

| Entry | Purpose |
|---|---|
| `swr_measure_text_v08(const swr_measure_request_v08 *, …)` | adds to the 0.6 request: `weight_f` (float wght), `width` (wdth), `opsz` (0 = automatic), `italic`/`slant`, `tracking_dip`, `kerning_dip`, an OpenType feature list (tag, value; at most 16), a `simulations` policy (allow or forbid bold and oblique), a fallback family list (at most 8), and `baseline_offset_dip` (puts the face's baseline on the host-supplied baseline inside the line box) |
| `swr_text_run_faces(run, swr_run_face *, n)` | per sub-run: resolved family, PostScript name, face SHA-256 (bundled) or file name and version (system), simulation flags applied, `.notdef` count, ascent, descent, advance |
| `swr_font_face_metrics(family, weight, width, style, swr_face_metrics *)` | unitsPerEm, hhea ascent, descent and lineGap, OS/2 typo and win metrics, capHeight, xHeight, axis ranges. The renderer becomes the single text authority. The host stops reading GDI face data in `NativeWindowsBodyFont` for anything other than the system message-font identity. |
| `swr_system_font_info(swr_system_fonts *)` | whether Segoe UI Variable, Cascadia Mono and Sitka are present, with versions (feeds the 2.1 family choice and the tuple record) |

Host-side, not ABI: the system-font mapping table, the Mac metric table, `Font.custom` name lookup, bundle font discovery, adapted-entry reporting, and the choice of baseline offset.

**Sequencing.** Decision 1 still holds: no renderer build while a qualification depends on pinned renderer bytes. Every renderer change goes through `.github/workflows/render-windows.yml`; local cargo is blocked.

---

## 4. Blocks, in dependency order

Each block is one case family at N=20 on a Mac pair, plus unit tests. The lead assigns round and block numbers. "Gate" names the deciding gate. Blocks in the same wave are independent and run in parallel.

**Wave 0 (start now, no dependencies)**

- **T0: Transparency and alpha contract (R12).** Root-cause the opaque-black transparent fill first. Then prove the alpha path end to end.
  - Cases: `Color.clear` and alpha 0.001 rectangles over colour; an alpha ramp (0, 1, 64, 128, 192, 254 and 255 /255) of rectangles and of registered images over white, black and a colour; an image whose alpha-0 pixels carry non-zero RGB; a 50 % red over white.
  - Gate: exact. Composites are compared with the analytic value within ±1/255, alpha-0 draws nothing, and probe patch P9 is removed.
  - May need a renderer fix (premultiply in `swr_image_register`, or the R12 path) with no ABI change.
- **F0: Renderer text facts (probe, no product change).** On the CI-built renderer, run on the Dell. Answers whether gpui 0.2.2 can:
  - select Segoe UI Variable at wght 500 and 100, and at opsz 9 versus 28;
  - turn DirectWrite simulations off;
  - draw colour emoji;
  - use `Font.fallbacks` with private fonts;
  - paint individual glyphs at chosen positions (for tracking);
  - honour `kern`=0 and `tnum`.

  It also starts on E14c (the 28 pt ink box): the rendering mode, grid-fitting and the vertical snapping of the line origin.
  - Output: a facts note with the measured rasters.
  - Gate: each answer comes with a raster or an API trace, or is marked unknown.
- **F1: Mac font metric table.** A Mac tool, `factory/tools/font-metrics`, measures in SwiftUI and CoreText, in an offscreen `NSHostingView` at scale 1 and 2.5:
  - one-line `Text` frame height, first and last baseline, ascent, descent, leading, capHeight, xHeight;
  - for every text style, the emphasized weights, `Font.system(size:)` at 9-40 pt including half points, all nine weights, and the four designs;
  - how `.bold()` and `.italic()` behave on a bundled single-face family (Tinos);
  - which `Font.custom` name forms resolve (PostScript, full, family);
  - the line height of mixed Latin, Japanese, Chinese, Korean and emoji lines.

  Output: a generated table in `SwiftRightHost` plus decisions for caption2, synthesis and lookup order.
  - Gate: the tool is deterministic (20 repeats identical).
- **I1: Decode service (WIC) and `CGImage` surface.**
  - Starts with I0, the Mac capture colour-space measurement.
  - Covers WIC decode in Swift (COM through `WinSDK`), ICC to sRGB, EXIF orientation 1-8, `maxPixel` thumbnailing, typed errors, the `CGImage` shim and `SwiftRightImageIO`, and replaces block 35's decode step.
  - Corpus: PNG 1/2/4/8/16-bit, palette with tRNS, grey+alpha, Adam7; JPEG baseline, progressive and CMYK; EXIF orientations; P3-tagged PNG and JPEG; ICO multi-size and DIB; BMP 32-bit with alpha; GIF (multi-frame, first frame only); truncated and corrupt negative controls.
  - Gate (buffer comparison, no capture):
    - lossless formats byte-exact against ImageIO-to-sRGB dumps from the Mac;
    - JPEG and P3 within the named tolerances, measured here;
    - orientation exact;
    - corrupt input throws, never returns a blank image.

**Wave 1**

- **I2: Image layout, scaling and interpolation** (depends on T0, I1).
  - Covers device-pixel-exact buffers, the four interpolation levels with fitted filters, `antialiased`, `aspectRatio` and `scaledToFit`/`scaledToFill`, `clipped`, and the live-resize transient path.
  - Cases: 1:1; `.none` 2x/3x; the 1.4 calibration ratios with fractional origins; fit and fill in wide and tall frames.
  - Gate: frame exact; 1:1 and `.none` exact; others within the named resampling tolerance; the 1.4 negative controls fail.
- **F2: System font mapping** (depends on F0, F1).
  - Covers body 13 DIP, the text styles per [S2] corrected by F1, the weight and family policy of 2.1, the designs, adapted-entry reporting, and baselines placed from the F1 table.
  - The decision 12/14/16/19 text-origin and label cases are rebaselined.
  - Cases: all 11 styles × regular and emphasized; `Font.system` at 9-32 pt × 9 weights; monospaced, serif and rounded; a `firstTextBaseline` HStack mixing sizes; the hub theme fonts (F15).
  - Gate: Text frame and baselines exact in points; ink within the re-measured tolerances; width reported; R2 closed without probe patch P2.
- **F3: ABI 0.8 text extension** (depends on F0; renderer CI).
  - Covers the four entries of section 3, the glyph-positioned paint path, and the Swift bridge.
  - Gate:
    - struct sizes and offsets checked at compile time on both sides (as in `abi-0.7-layout-mock.c`);
    - a 0.7 host on a 0.8 renderer and a 0.8 host on a 0.7 renderer behave as specified (refusal or fallback, never silent);
    - renderer unit tests in CI;
    - `swr_text_run_faces` names the registered hash for Tinos and reports `.notdef` for an unmapped code point (negative control).

**Wave 2**

- **I3: Rendering mode and tint** (depends on I2). Template versus original, `foregroundStyle` tint, opacity, an image inside a Button label. Gate: tint exact on covered pixels; edge-aa 32 on alpha edges.
- **I4: Cap insets and tiling** (depends on I2). Stretch and tile, caps at 1:1 and scaled, tile phase. Gate: caps exact; tile phase exact; stretched centre within the resampling tolerance.
- **I5: Image shape clips** (depends on I2). `clipShape` with RoundedRectangle (circular and continuous), Circle and Capsule; `cornerRadius`. Gate: edge-aa 32, interior exact.
- **I8: Named bundle images** (depends on I2). Imageset parsing, scale-variant choice (measured at 1, 1.25, 1.5, 2 and 2.5), template intent, dark appearance variant. Gate: frame exact; the chosen variant equals the Mac's; pixels per I2.
- **F4: Bundled fonts complete** (depends on F3 and F1's synthesis and lookup facts).
  - Covers bundle discovery and registration of every face, lookup in the measured order, real weight and italic faces, a synthesis policy equal to the Mac's, variable bundled fonts by axis, and E14c closed (28 pt).
  - Tinos Regular, Bold, Italic and Bold Italic are bundled (Apache 2.0).
  - Gate: ink box within 1 px; glyph x within 1 px; the per-run face hash equals the file; a missing face behaves as on the Mac, and its identity is reported.
- **F5: Tracking, kerning, `monospacedDigit`** (depends on F3). Gated on bundled Tinos: glyph x positions within 1 px for tracking −1 to +5 and kerning on and off. System fonts: semantic, plus the `tnum` advance equality check.
- **F6: Fallback chains** (depends on F2, F3). Locale cases ja, zh-Hans, zh-Hant, ko, hi, and emoji and symbol runs inside body text. Gate: `.notdef` = 0; the family is in the declared chain; mixed-line height equals F1's Mac value; emoji pixels contain non-grey colour (a colour glyph was drawn).

**Wave 3**

- **I6: AsyncImage** (depends on I1, I2). Phases, cancellation, transaction animation, scale parameter, through a stub `URLProtocol`. Gate: semantic phase sequence and no commit after disappear; pixels per I2.
- **I7: Image cache and memory budget** (depends on I1, I2; best after I6).
  - Covers the two LRU levels, the eviction rules, the collision guard and the lifecycle events.
  - Workload: the hub's app-icon grid at 200 icons, scroll there and back, then live resize.
  - Gate: zero re-decodes on scrolling back; evictions never release a committed image; steady-state memory within the frozen budget; bridge time per frame p95 ≤ 2 ms and p99 ≤ 4 ms (§11) during scroll and resize.
- **F7: Windows without Segoe UI Variable** (depends on F2; only if Adrian keeps Windows 10). Forced static-Segoe path on a Windows 11 host as a stand-in. A real Windows 10 host is a qualification gap unless one exists.

Critical path to the hub's needs: T0 → I1 → I2 (app icons) runs in parallel with F0 + F1 → F2 (R2 system fonts). Block 35 keeps the hub moving meanwhile.

---

## 5. Risks

- **Licensing.**
  - Windows fonts may not be redistributed, copied or converted, including to bitmaps. Segoe UI Variable is not licensable outside Microsoft products [S8]. So no Segoe face, and no pre-rendered Segoe glyph atlas, is ever shipped, cached to disk or committed as a resource. Runtime drawing and screenshots are allowed uses [S8].
  - SF Pro and SF Symbols stay Apple-only (decisions 2 and 3). Only measured numbers are stored.
  - Tanker's licence is pending, so it is not bundled. The hub's display font falls back to F2's mapping, standard width unless Adrian chooses otherwise.
  - Bundled fonts must be OFL or Apache and record their licence file next to the font.
- **Windows versions.** Segoe UI Variable, Cascadia and Segoe Fluent Icons were added in Windows 11 [S4]. On Windows 10 (out of support since 14 October 2025 [S6]) the static mapping applies and symbols have no Fluent glyphs. Fonts are updated through Windows Update [S8], so the tuple records font file versions and hashes (via `swr_system_font_info`). A metric drift after an update becomes a candidate baseline (§11 change control), never a silent pass.
- **arm64.** Windows arm64 is unsupported by scope revision 1 (architecture.md §9). WIC and DirectWrite are OS components, so this design adds no architecture-specific code. The Mac oracle is arm64.
- **gpui limits.** Variable-axis selection, simulation control, colour emoji, glyph-level painting and alpha mode are all unverified [S5]. F0 and T0 retire them first. If gpui cannot select axes or paint positioned glyphs, F3 needs a DirectWrite path inside the renderer for text runs that use those features. That is larger renderer work and the main cost risk.
- **Resampling tolerance credibility.** A fitted tolerance can hide a wrong filter. The negative controls in 1.4 and the separate calibration and gating sets are what make it meaningful.
- **Rebaselining.** Body 13 DIP moves every text-origin and label measurement from decisions 12-19. F2 re-measures them; the old values are not edited by hand.
- **WIC from Swift.** COM vtable calls through `WinSDK` are verbose. Errors are mapped to `ImageDecodeError` cases. A decode on a background task must initialise COM on that thread (COINIT_MULTITHREADED), so decode happens off the UI thread and registration on it.
- **Hash identity.** `RGBAImage` equality is a 64-bit FNV hash. `ViewEquality` and the caches could confuse two images in a collision. The I7 guard covers the caches. `ViewEquality` keeps the hash, and that residual risk is accepted and stated here.
- **Mac oracle drift.** The F1 table and the filter fits bind to macOS 27. A macOS upgrade reopens them as a candidate baseline.

---

## Choices for Adrian

Each has a default that work proceeds on. He can override any of them.

1. **Body size.** Default: 13 DIP point-for-point with Mac vertical metrics (2.1), instead of the 12 DIP Windows message font. It reverses current behaviour and rebaselines text cases.
2. **Condensed and expanded widths** (the hub's display-font fallback, G14). Default: standard width, reported as adapted. Alternatives: Bahnschrift's width axis (a different design), or bundling an open-licensed variable font with a width axis.
3. **Windows 10 support.** Default: Windows 11 is the qualified target and Windows 10 gets only the static-Segoe mapping, unqualified. Making Windows 10 a target adds F7 with a real host.
4. **RightKit owner for image decoding.** Default: SwiftRight owns it, because no RightKit owner exists and SwiftRight apps are the only Swift consumers. A RightKit owner would need his approval for the RightKit change.
5. **Tanker.** Still waiting on the licence. Nothing in this design bundles it.

---

## Sources (fetched 15 October 2026)

- [S1] Microsoft Learn, "WIC codecs from Microsoft", https://learn.microsoft.com/en-us/windows/win32/wic/native-wic-codecs (codec table read from the page source, MicrosoftDocs/win32 `desktop-src/wic/native-wic-codecs.md`): BMP, DDS, DNG, GIF, HD Photo, ICO, JPEG, JPEG XR, PNG, TIFF built in; HEIF extension codec; Raw and WebP Store extensions.
- [S2] Apple Human Interface Guidelines, Typography, macOS built-in text styles table (https://developer.apple.com/design/human-interface-guidelines/typography, read through its JSON data endpoint): Large Title Regular 26/32 … Caption 2 Medium 10/13; emphasized weights.
- [S3] Microsoft Learn, "Typography in Windows", https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography: Segoe UI Variable has two axes, weight (wght) 100-700 and optical size (opsz), automatic, 8-36 pt; Bahnschrift has weight and width; per-script UI fonts; Segoe UI Emoji and Segoe UI Symbol.
- [S4] Microsoft Learn, "Font List Windows 11", https://learn.microsoft.com/en-us/typography/fonts/windows_11_font_list: Segoe UI Variable (Display, Small, Text; Light to Bold), Cascadia Code and Mono, and Segoe Fluent Icons marked "Added in Windows 11"; static Segoe UI Light to Black; Sitka; Consolas; Bahnschrift.
- [S5] docs.rs, gpui 0.2.2, `gpui::Font` (https://docs.rs/gpui/0.2.2/gpui/struct.Font.html) and `Window::paint_image` (https://docs.rs/gpui/0.2.2/gpui/struct.Window.html): Font fields are family, features, fallbacks, weight and style, with no letter-spacing or axis field; `paint_image(bounds, corner_radii, data, frame_index, grayscale)`, with the pixel format and alpha mode undocumented.
- [S6] Microsoft Learn, Lifecycle, Windows 10 Home and Pro, https://learn.microsoft.com/en-us/lifecycle/products/windows-10-home-and-pro: "Windows 10 will reach end of support on October 14, 2025."
- [S7] Microsoft Learn, `IDWriteFactory5::CreateInMemoryFontFileLoader`, https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefactory5-createinmemoryfontfileloader: minimum client Windows 10 build 15063.
- [S8] Microsoft Learn, "Font redistribution FAQ", https://learn.microsoft.com/en-us/typography/fonts/font-faq: "you may not redistribute the Windows fonts … you may not convert them to other formats, including bitmap formats"; "Segoe UI Variable is not available for licensing or use outside of Microsoft products or on non-Windows platforms"; graphic files and screenshots are allowed; fonts are updated with Windows.
- `rightkit owns` (local CLI, 15 October 2026): no image or font owner; `media-ui`, `media-pipelines`, `disk-cache` and `http-client` exist and do not cover this need.
