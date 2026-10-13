# Tinos provider boundary investigation v1

## Evidence

`package/Sources/FactoryProbe/main.swift` validates staged `Tinos-Regular.ttf` bytes (521588 bytes, SHA `60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`), registers it process privately with `AddFontResourceExW(..., FR_PRIVATE, ...)`, derives `head`/`hhea` metrics, forwards family `Tinos`, size, weight, line height, scale, and width through existing ABI 0.6 `MeasureRequest`, then unregisters after shutdown. Logs retain `rendererSelection=unproven`.

Existing ABI bridge path carries `MeasureRequest.fontFamily` and numeric metrics. No font bytes, private `HFONT`, DirectWrite collection, glyph map, or renderer-owned resource handle crosses ABI 0.6. Existing `TextRunHandle` is created by `bridge.measure` and painted by `.text`; host has no API to attach a font resource to that run.

`image-system-star-fill-v9/package/Sources/FactoryProbe/FactorySystemImageProvider.swift` proves reusable process-private GDI coverage route: `CreateFontW`, `GetTextFaceW`, `GetTextMetricsW`, `GetGlyphOutlineW(GGO_GRAY8_BITMAP)`, bounded bottom-up coverage, tint composition, and `Bridge.registerImage`. Runtime `SystemImageRasterProvider` performs bounded coverage-to-RGBA conversion, then ABI 0.6 accepts registered RGBA image handles.

## Smallest feasible route

For diagnostic glyph coverage only, reuse that provider shape with the validated Tinos resource: register `FR_PRIVATE`; select exact `Tinos`; resolve Unicode through `GetGlyphIndicesW`; rasterize each glyph with `GetGlyphOutlineW`; use actual `gmCellIncX`, origin, font metrics, and current requested size; compose bounded RGBA; register image; release image/run handles on replacement and shutdown. This observes provider identity and coverage from pinned bytes without Mac pixels or fixture data.

This route cannot deliver original `Text` semantics. It lacks ABI support for font resources and shaping/ellipsis runs; replacing `.text` with `.image` would bypass renderer text shaping, lineLimit behavior, and `TextRunHandle` ownership. Scaling a GDI image to bridge-measured bounds would mask provider differences. Therefore it is an observational fallback until renderer/ABI gains a font-resource or DirectWrite-collection binding.

## Hold

Keep current custom-font path source identity, TTF metrics, lineLimit selection, and `rendererSelection=unproven` evidence. A true product fix requires protected renderer/ABI support for exact font resource selection, or a renderer-owned provider API. No runtime, ABI, renderer, witness, or native packet was changed by this note.

## Renderer selection check & bounded disconfirming probe

Current host source shows exact boundary. `factory/native/windows/RendererHostAdditive.swift.in:44-60` rejects `Font.Metadata.isCustom`, maps metadata to family/size/weight, then `:80-83` sends only `MeasureRequest.fontFamily`, numeric metrics, scale, and width. Text paint repeats same family-only request at `:139-145`. ABI design records renderer flow as borrowed `font_family` into `font(r.family.to_string())` in `factory/abi/abi-0.7-proposal.md:90`; no font bytes, collection, face handle, or resolved face identity crosses ABI 0.6.

Existing source separates both providers in one process. `bundled-font-readiness-v2/windows-source/FontProbe.cpp:71-86` calls `AddFontResourceExW(..., FR_PRIVATE, ...)`, then builds an isolated DirectWrite collection from exact Tinos bytes; `:88-95` queries `GetSystemFontCollection(FALSE)` separately. `resources/directwrite-private-font.cpp:104-110` creates text format/layout from custom collection, proving private DirectWrite rendering only. Existing host still rejects custom metadata at `RendererHostAdditive.swift.in:44-45`.

Root can run one bounded disconfirming probe before any renderer change. `windows-source/FontCollectionVisibilityProbe.cpp` records `FindFamilyName(L"Tinos")` from one shared factory's system collection before registration, after `AddFontResourceExW(..., 0, ...)` with `checkForUpdates=FALSE`, and after `checkForUpdates=TRUE`; it then repeats both checks after paired cleanup with `FR_PRIVATE`, while creating an isolated collection positive control. Expected diagnostic is `isolatedPositive=true`; system visibility after nonprivate flags `0` remains unresolved until root runs probe. Any system-family transition must be treated as new evidence, then bind selected face/resource hash through renderer-owned API before changing hold.

This probe tests session-visible registration without install, registry mutation, prompt, or admin access. It cannot establish `Font.custom` selection unless renderer's own DirectWrite collection reports Tinos identity. Current evidence supports provider hold, while exact Windows registration semantics remain experimentally open.

## Nonprivate session-registration probe

`windows-source/FontCollectionVisibilityProbe.cpp` is one bounded source-only control for unresolved `AddFontResourceExW(path, 0, ...)` behavior. Root should run it with `Tinos-Regular.ttf`, expected family `Tinos`, PostScript `Tinos-Regular`, and pinned SHA `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`.

Probe records shared DirectWrite `GetSystemFontCollection(FALSE/TRUE)` family visibility before registration, after temporary nonprivate flags `0`, after paired cleanup plus `FR_PRIVATE` negative control, then verifies isolated `CreateFontCollectionFromFontSet` positive control. Both registrations use RAII cleanup & explicit `RemoveFontResourceExW` success fields (`nonPrivateRemoved`, `privateRemoved`) before probe JSON is emitted; no file copy, install, registry edit, prompt, or admin operation is requested. `nonPrivateSystemTrue=true` would establish only session registration visibility; renderer selection still needs own collection/face identity evidence. `privateSystem*` remains diagnostic negative control, while `isolatedPositive=true` verifies exact Tinos bytes reached DirectWrite private collection.

Root may copy this source into fresh ignored stage `D:\Claude\swiftright\.factory-work\hosts\bundled-font-readiness-v6-line-limit-host\font-visibility-probe-r1\` & compile through existing paint-canary vcvars route: `cmd.exe /d /s /c "\"C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat\" && \"C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Tools\\MSVC\\14.51.36231\\bin\\Hostx64\\x64\\cl.exe\" /nologo /std:c++17 /EHsc /O2 /DUNICODE /D_UNICODE /DNOMINMAX FontCollectionVisibilityProbe.cpp /Fe:FontCollectionVisibilityProbe.exe /link dwrite.lib gdi32.lib ole32.lib"`. Compiler & vcvars paths must match measured inventory rows (`cl.exe` SHA `dc8426b8760d92cf757df3d10b9f0244a95b454ff43194a58161568a0ec70d53`, `vcvars64.bat` SHA `6b516d8fcf543c14b2d861e1f45661e0029230fe0dc48e86ce78522801822209`).
