# Segoe Fluent Icons provider raster plan

This producer is factory-owned Windows evidence. It keeps original `Image(systemName: "star.fill")` witness unchanged & leaves SwiftRight runtime, bridge, renderer, & ABI untouched.

1. Use `DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)` & read-only `GetSystemFontCollection(FALSE)`.
2. Resolve exact family `Segoe Fluent Icons`; obtain its normal `IDWriteFontFace`; resolve Unicode `U+E735` (`FavoriteStarFill`). Reject missing family, face, or glyph.
3. Root supplies measured `fontEmSize` from Mac source geometry. Build one `DWRITE_GLYPH_RUN`; call `CreateGlyphRunAnalysis` with `DWRITE_RENDERING_MODE_NATURAL`, `DWRITE_MEASURING_MODE_NATURAL`, & matching `DWRITE_TEXTURE_CLEARTYPE_3X1`. Read `GetAlphaTextureBounds`, then `CreateAlphaTexture`; collapse three coverage channels by per-pixel maximum into straight RGBA alpha.
4. Convert coverage into straight RGBA bytes using exact semantic yellow `system.yellow` (`FF CC 00`, alpha from DirectWrite). Preserve returned texture bounds as intrinsic width/height; reject clipping, empty bounds, zero alpha coverage, nonfinite dimensions, or bytes above 64 MiB.
5. Hash raw RGBA bytes with SHA-256 & emit `FactorySystemImageAssets.json` beside produced `FactoryProbe.exe`: identity `star.fill`, provider `Segoe Fluent Icons`, glyph `E735`, provider version from `IDWriteFontFace` metadata, dimensions, base64 bytes, `rgbaSha256`, `status=provider-raster-ready`, & `licenseStatus=unverified`.

Producer output is an ignored host asset under `.factory-work/hosts/system-star-fill/package`; archive raw bytes, producer stdout, map, provider/font identity, & hashes before any cleanup. Registry then performs existing ABI 0.6 `registerImage`/release lifecycle. Successful DirectWrite rasterization alone does not prove SwiftUI parity; root still needs native layout, paint, screenshot, UIA, & paired source joins.

Existing `bundled-font-readiness-v1/windows-source/FontProbe.cpp` contains bounded DirectWrite family/face resolution patterns. Do not use `AddFontResourceEx`, install fonts, substitute glyph text primitive, or reuse named RGBA fixture.

## Root execution packet

`GlyphRasterProducer.cpp` is a DirectWrite producer. It compares supplied font-file reference key against selected system face files before rasterization. It resolves `Segoe Fluent Icons` from read-only system collection, selects normal face, resolves `U+E735`, records glyph/font metrics, calls `CreateGlyphRunAnalysis` & `CreateAlphaTexture`, then writes straight yellow RGBA bytes. It accepts raw font SHA-256 as an argument; runner hashes exact font file before process launch & records both identity hashes.

`ProviderOwnedJobProcess.cs` is packet-local owned-process boundary. `produce-provider-raster-v1.ps1` writes a packet-local compile command that sets `VSCMD_SKIP_SENDTELEMETRY=1` around measured `vcvars64.bat`, then invokes measured `cl.exe` under one 1 GiB Job Object. Microsoft Build Tools VSCEIP registry state is recorded read-only as diagnostic per Microsoft Learn (`https://learn.microsoft.com/en-us/visualstudio/ide/visual-studio-experience-improvement-program`); no host-wide registry preference gates admission or is mutated. After original compiler exit 0 & sealed stream hashes, runner inspects every remaining Job Object PID. Only one exact `vctip.exe` descendant with caller-pinned image path/hash, Job membership, start identity, & retained process handle may be terminated; any foreign, ambiguous, wrong-path, non-member, or unretained-handle case fails. Producer runs under its own 1 GiB Job Object. Each receipt retains original process handle through exit, stream drain, sealed stdout/stderr, helper stop proof, & active-process count zero. Runner never installs fonts, opens windows, deletes files, or overwrites existing stage.

Root must locate exact installed Segoe Fluent Icons font file on Windows & pass it explicitly; runner does not guess or substitute. Source-only compiler admission:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-system-star-fill-v1\windows-source\provider-raster\produce-provider-raster-v1.ps1 `
  -CompilerPath C:\Path\To\cl.exe -VcVars64Path C:\Path\To\vcvars64.bat `
  -VctipPath C:\Path\To\vctip.exe -VctipSha256 <measured-64-hex> `
  -FontPath C:\Windows\Fonts\<measured-segoe-fluent-file>.ttf `
  -Repo D:\Claude\swiftright -PreflightOnly
```

After reviewing preflight JSON, root may rerun same command without `-PreflightOnly`. Outputs stay under `.factory-work\hosts\system-star-fill\provider-raster-r1`; revision2 & revision3 use fresh input/output roots, preserving prior receipts. Expected files are `FactorySystemImageAssets.json`, `provider-raster-manifest.json`, raw RGBA, provider metadata, compile receipt, producer receipt, & bounded streams. Root must archive those bytes before any later native capture. `FactorySystemImageAssets.json` uses `status=provider-raster-ready` so existing registry can consume exact RGBA; manifest/metadata remain `held-until-root-native-render`, & raster production does not establish SwiftUI parity by itself. `-FaultMode empty-coverage` is a negative control: producer zeroes alpha before validation & must fail with no accepted map; default `none` requires `nonZeroAlphaPixels > 0`.

Packet source hashes at authoring time:

- `GlyphRasterProducer.cpp`: `sha256:8ab5ca92fe0771406b4fa70c786e39773c389cbf4cc90abdd5249cb03d9b4e1c`
- `ProviderOwnedJobProcess.cs`: `sha256:0ed9cec5f361faa1f8a7cf7308435f2ffb0c01232e1e0532825d65b9a24fab86`
- `produce-provider-raster-v1.ps1`: `sha256:79397e336b8e5a1039392e05a741f519b72b24361d8689e793776a54a30a7f36`

Those hashes are source hashes only; produced font/RGBA/EXE hashes remain unmeasured until root Windows execution.

## Root staging/transport wrapper

`stage-provider-raster-v1.py` verifies discovered compiler, `vcvars64.bat`, & Segoe font path/bytes/SHA-256 from `root-execution/system-image-tools-actual-r1/transport.json.stdout.bin`, then seals exact producer sources under `.factory-work/hosts/system-star-fill/provider-raster-inputs-r1`. `--revision 2` selects fresh `provider-raster-inputs-r2` & `provider-raster-r2` roots, preserving revision1. It emits `input-manifest.json` & `remote-request.json` without compiler/native/SSH actions. Root run passes `-InnerDeadlineSeconds 120` to each owned producer/compile child.

Root can stage, then transport/run serially:

```text
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v1/windows-source/provider-raster/stage-provider-raster-v1.py
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v1/windows-source/provider-raster/stage-provider-raster-v1.py --revision 2
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v1/windows-source/provider-raster/stage-provider-raster-v1.py --revision 2 --remote --run
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v1/windows-source/provider-raster/stage-provider-raster-v1.py --revision 3 --remote --run --timeout 300
```

Before compile, runner records documented VSCEIP registry state read-only as diagnostic. `VSCMD_SKIP_SENDTELEMETRY=1` covers DevShell setup only. Root passes measured `-VctipPath` & `-VctipSha256`; `--remote --run` creates remote input directories, SCPs sealed source files, runs mandatory preflight then producer, & fetches raw RGBA, provider metadata, map, EXE, streams, & compile/producer receipts into local `archive/`. It never sends remote deletion. Archive admission requires both owned process receipts to show original handle retention, sealed/drained streams, exact helper stop proof when present, exit, & active/cleanup Job Object count zero. Negative controls `vctip-wrong-path`, `vctip-nonmembership`, & `vctip-retained-handle` must fail closed.
