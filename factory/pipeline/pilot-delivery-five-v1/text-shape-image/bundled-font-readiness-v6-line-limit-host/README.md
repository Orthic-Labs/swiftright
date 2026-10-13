# Windows Tinos host package (source only)

`package/` copies current measured Text host geometry/retention and binds the exact `Font.custom("Tinos-Regular", size: 18)` witness to the ABI 0.7 renderer's bundled-font registration. Host derives provider line metrics from the staged Tinos `head`/`hhea` tables; optional metric flags remain diagnostic overrides, with source units logged. No default font or invented line height is used.

`lineLimit(1)` is handled in `FactorySingleLineText.swift`: host first measures original text with the same bundled-font `MeasureRequest`, then performs bounded prefix-plus-ellipsis selection against physical `maxWidth`. Each rejected `TextMeasurement.run` is released immediately; only the selected run enters the retained cache. Requests with other line limits, or multiline text without a positive width bound, fail closed.

Registration (ABI 0.7, `render/swiftright-abi/include/swiftright.h` "REVISION 0.7"): in `ready`, before the first measurement, the host verifies the resource (extension, size, SHA-256), proves `swr_font_resolve("Tinos")` and an unknown family both report FALLBACK, registers the bytes through `BundledFontLibrary` (`swr_font_register`, process lifetime; GPUI cannot unregister), then proves `Tinos` resolves BUNDLED with the registered handle and SHA while the unknown family still reports FALLBACK. The measured family is the registered family `Tinos`, found from the `Font.custom` name `Tinos-Regular`. The host requires ABI 0.7 (`Bridge.load(..., minimumRevision: .v07)`) and loads the NEW renderer `D:\Claude\swiftright\.factory-work\inputs\renderer-0.7\swiftright_render.dll`; the pinned ABI 0.6 renderer under `inputs\renderer\` is untouched. The package depends on the 0.7 bridge staged at `inputs\SwiftRightBridge-0.7`.

The font file is found by `--tinos-font`, beside the exe, or in `package/Resources` above the exe (the pair tool builds under `package/scratch/...`).

Resource: `package/Resources/Tinos-Regular.ttf`, 521588 bytes, SHA-256 `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61` (identical to `factory/resources/fonts/Tinos-Regular.ttf`).

Mac reference: `mac-source/` renders the unchanged witness through SwiftUI `ImageRenderer` at scale 2.5, top-leading in 320x240 DIP, with Tinos registered process-scope by `CTFontManagerRegisterFontsForURL` from the same bytes (copy `factory/resources/fonts/Tinos-Regular.ttf` to `~/Library/Caches/SwiftRightFactory/sr1/` first; the host verifies the SHA-256 and never reads `/Volumes/D` at run time).

Run: `python3 factory/tools/pair.py <this case dir> --runs N`.

## Result (2026-10-13, ABI 0.7 renderer from CI run 38363295035, commit `4b97b6ba`)

Renderer `swiftright_render.dll` SHA-256 `b5390cd27362f18d2e4f88b74c464aae8e71612f63b74aa07e392dfef01448b2` (rustc 1.98.1, GitHub `windows-2025`; local Cargo is not permitted on this public repository), staged for the factory at `inputs\renderer-0.7\`. The pinned 0.6 DLL under `inputs\renderer\` (`e280f4a9...`) is untouched.

- `pair.py <case> --runs 20`: `runs/20261013-132136`, 20/20 windows and mac captures, 20/20 `exact` outside the named text line box `[0,0,300,52)`; N=1 `runs/20261013-131313` first measured the unexcluded frame: 4267 differing pixels, all inside that box, max channel diff 224.
- Text semantics (every one of 20 runs identical): 1 line, `lineLimit(1)` truncation to `SwiftRight bu…` on both sides (13 UTF-8 bytes + the ellipsis; host selection `displayUTF8=16 candidateCount=6`), measured `widthPX=298.78418 heightPX=51.745605`, ink right edge x=294 on both, frame/background pixels outside the box exact. Mac ink bbox `[2,7,294,50]`, Windows `[3,10,294,51]`.
- Font identity (every run): ABI `revision=0.7 minor=7 fnCount=18`; before registration `resolve(Tinos)=fallback` and `resolve(SwiftRightNoSuchFamily)=fallback`; after `swr_font_register` (handle `4294967297`, family `Tinos`, weight 400, 1 face, SHA-256 equal to the pinned resource) `resolve(Tinos)=bundled` with the same handle and SHA, unknown family still `fallback`.
- Residual (reported, not gated; same bytes, different rasterizer): Windows glyphs sit about 1 to 3 px lower and ink is slightly lighter-edged (min luminance 31 vs 39). A rigid 2 px shift lowers the diff only from 4267 to 3696, so it is rasterizer AA (DirectWrite grayscale in GPUI vs CoreText) plus baseline placement. Baseline cause: `render/swiftright-render/src/text.rs:376-377` places the baseline at half-leading + ascent inside the line box, while the host's line height (`package/Sources/FactoryProbe/main.swift:130`) includes the font's `lineGap` (87/2048 em = 0.76 DIP = 1.9 px at 2.5x), whereas CoreText puts the leading below the descent. A renderer-side leading-below option would need an ABI addition; not done.
- Compatibility proofs on real binaries: an unchanged 0.6 host (old staged bridge, `continuous-observation-delivery-v5` package, DLL path pointed at the 0.7 DLL) loads, commits and renders a frame (22 colours) on the 0.7 renderer; the 0.7 bridge on the pinned 0.6 DLL reports `revision=0.6 minor=6 fnCount=16 fonts=false` and a font call fails with `SWR_E_UNSUPPORTED (-15)`.

## Update 2026-10-13: baseline matches CoreText (renderer commit 22ad719b, CI run 38379835773)

Root cause (measured on SwiftUI ImageRenderer, Tinos 13/18/31 pt and SF/Helvetica/Times at 1x/2x/2.5x): SwiftUI Text puts the baseline at round(CTFont ascent) DIP below the line top, and its line height is round(ascent)+round(descent) (leading/lineGap is dropped). The host line height included the 0.76 DIP gap, and GPUI/DirectWrite reports its own ascent (Tinos 17 DIP, not 16.04) and paints with half-leading above, so Windows sat 2 px low at 2.5x. A first attempt using GPUI's ascent (commit 427dc6cc, `runs/20261013-144150`, firstBaselinePX=42.5) changed nothing; hence hhea.
Fix: `text.rs` `baseline_placement()` puts the baseline at round(hhea ascent) (hhea read from the registered font bytes; GPUI's ascent only computes the paint shift); host line height = round(asc)+round(desc). Renderer staged at `inputs\renderer-0.7-baseline-22ad719b\` (SHA-256 `82513ae0c1e29f30ea4efe27d84869cd6b3c3fbce7951d78083f9647226bc05d`); the pinned 0.6 DLL and `renderer-0.7` are untouched.
Gate (`factory/tools/pair_text_report.py`, pair.json `textGate`): exact outside the glyph region, half-coverage ink bbox within 1 px per edge, AA diff reported. Result `runs/20261013-152842` (N=20, `--shared`): 20/20 gate; ink bbox mac [3,8,293,50] windows [3,8,294,49]; AA differing pixels 3696 (was 4267); host heightPX=50.0 (Mac 50), firstBaselinePX=40.0 (Mac 40).

## Earlier root-owned staging (historical, superseded by pair.py for new evidence)

Root-owned bounded compile request:

```text
swift.exe build --package-path D:\Claude\swiftright\.factory-work\hosts\bundled-font-readiness-v6-line-limit-host\windows-host\package --scratch-path D:\Claude\swiftright\.factory-work\hosts\bundled-font-readiness-v6-line-limit-host\windows-host\package\build-tinos-r6\scratch -c release --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1
```

Copy exact resource beside fresh `FactoryProbe.exe`, then launch with `--tinos-font <staged-Tinos-Regular.ttf> (metric flags optional diagnostic overrides)`. Root owns 1 GiB RSS/job supervision, native capture, & all qualification receipts.

Paint-canary source is staged with same retained-handle Job Object helper. Root invocation for fresh revision:

```text
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host/tools/stage-bundled-font-v1.py --revision 2 --remote --run-canary --timeout 300
```

This archives compile, executable, positive RGBA/metadata/receipt, & expected failing `--fault-empty-coverage` receipt under stage transport archive. Renderer selection remains unproven.


## MSVC VCTIP admission

Paint canary compile records Microsoft Build Tools VSCEIP registry state read-only as diagnostic (Microsoft Learn: https://learn.microsoft.com/en-us/visualstudio/ide/visual-studio-experience-improvement-program): `OptIn=0` may appear under documented `HKLM\SOFTWARE\Policies\Microsoft\VisualStudio\SQM`, `HKLM\SOFTWARE\Wow6432Node\Microsoft\VSCommon\17.0\SQM`, or `HKLM\SOFTWARE\Microsoft\VSCommon\17.0\SQM`. It never mutates or gates on host-wide telemetry preference. `VSCMD_SKIP_SENDTELEMETRY=1` is set before & after `vcvars64.bat`; after original compiler exit 0 & sealed streams, only one exact pinned `vctip.exe` Job descendant may be stopped through retained handle. Wrong path, nonmembership, ambiguous child, or missing retained handle fails closed.

Bridge width convention: adapter encodes `proposedWidth == nil` as physical `maxWidth == 0`; zero therefore means unbounded/no-wrap. Single-line helper accepts original one-line result under this convention, rejects multiline without positive bound, & never treats zero as finite fitting width.
