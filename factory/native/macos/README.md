# F5 native Mac candidate capture

`CaptureHost.swift` wraps F4 generated witness source with offscreen `ImageRenderer`, root `Layout` & `TextRenderer` measurements. Original witness source is copied unchanged. Plain/instrumented pixels are preserved separately; transparency is measured, never assumed.

`capture.py` requires execution-eligible F4 manifests & persisted hash-matching canonical cases. Regular cases come from factory/pipeline/cases; gate cases use --case-root. Existing factory/.venv validator libraries are reused when absent from system Python. Fresh binaries compile & execute only below `/Users/adrdsouza/Library/Caches/SwiftRightFactory/`. Source/binary/adapter hashes accompany every case. Each run starts separate plain, instrumented, own-window compositor & recorder-driven AX processes. Outputs cannot overwrite existing case evidence.

Permission checks use `AXIsProcessTrusted()` & `CGPreflightScreenCaptureAccess()` only. Existing signed F1MacRecord is copied unchanged & strictly verified. Current signed binary is F1-only; newer generic source is not treated as binary capability. That recorder channel is held. Fresh AXClient compiles on internal disk, preflights its actual trust & validates only owned PID/executable path/hash/window title. Actual linker-signed identity is recorded; no signing identity or permission store is modified. ScreenCaptureKit selects only owned PID/window ID after positive screen preflight. Every subprocess owns its process group; timeout cleanup targets only that group.

```sh
python3 factory/native/macos/capture.py \
  --manifest factory/probes/generated/<case>.manifest.json \
  --case-root factory/pipeline/cases \
  --output factory/native/macos/evidence/<new-run-id> --runs 20
python3 -m unittest factory.native.macos.test_capture -v
```

Raw outputs remain under individual run directories. `normalize.py` emits validated `capture.json` with measured root layout, image hashes, witness AX nodes & render timestamps. Captures are observational candidates; no baseline promotion or qualification is performed. Root wrapper callbacks do not establish internal custom-Layout callbacks. TextRenderer run bounds do not establish resolved witness font/colour or bundled-font provenance; CoreText system font control is separate. Chrome-only AX is held. Static pilots do not establish animations. Clock correlation is same-process render interval only.

ScrollView produces blank offscreen ImageRenderer pixels on this host. Such images are held while real owned-window SCK, AX & root-layout evidence is retained in partial candidate captures. External AX excludes every node outside AXHostingView, including titlebar static text.

Private bundled-font pilots may supply `recipeFile` (hash-verified factory-relative canonical recipe) & `providerResources.font` (`path`, `hash`, `postScriptName`, `family`). Resource is copied/hash-verified beneath internal work directory. Every fresh process registers via `CTFontManagerRegisterFontsForURL(..., .process, ...)` before constructing SwiftUI content; native hash, PostScript name & CoreText descriptor URL must match copied blob. Raw `registeredFontResource` records provider identity/metrics separately from unresolved TextRenderer glyph-font identity. Process registration never installs fonts globally. Existing captured sources/hashes remain immutable.
