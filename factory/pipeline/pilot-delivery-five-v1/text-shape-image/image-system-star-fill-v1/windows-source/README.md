# Original `Image(systemName: "star.fill")` source packet

This packet keeps exact original SwiftUI witness in `package/Sources/FactoryProbe/Witness.swift`. Mac source packet at `../mac-source` runs same witness through SwiftUI `Image(systemName:)`; it does not reuse named RGBA fixture pixels.

Windows host resolves only `.system("star.fill")` through `FactorySystemImageAssets.json` mapping (`Segoe Fluent Icons`, `E735`, mapping version `segoe-fluent-icons-star-fill-v1`). Once provider produces exact RGBA bytes, host validates dimensions, `sha256`, identity, provider, glyph, & yellow foreground semantic, then registers one retained ABI 0.6 `ImageHandle` with `Bridge.registerImage`; teardown releases every handle. Missing/mismatched mapping fails closed. No glyph-text primitive, named asset, or default image fallback remains.

Current mapping is intentionally `provider-raster-required`: no measured provider RGBA bytes are invented. `licenseStatus` remains `unverified`. A Windows provider capture must supply `width`, `height`, `rgbaBase64`, `rgbaSha256`, `status: provider-raster-ready`, & exact provider version before native execution can proceed.

Current source evidence:

- Runtime `ImageReference.system` & default intrinsic size: `factory/native/windows/api-final-9060345a-20261011/runtime/Sources/SwiftRightRuntime/Controls.swift:50-63`, `Graph.swift:810-812`.
- ABI 0.6 image registration/release: `factory/native/windows/remaining-five-hosts-v2/dependencies/staged-bridge-inputs-r09/Sources/SwiftRightBridge/Bridge.swift:351-374`.
- Existing text-glyph candidate only: `factory/native/windows/host-parse-20261011/RendererHost.swift:178-186`; this packet deliberately replaces it with RGBA registration, so glyph route is not presented as SF Symbol parity.

Root-owned bounded flow after provider bytes are measured:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-system-star-fill-v1\windows-source\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-system-star-fill-v1\windows-source\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright'
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-system-star-fill-v1\windows-source\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -PreflightOnly
```

Root then runs exact emitted argv under original-handle Job Object cap 1 GiB, one SwiftPM job, & frontend flags `-Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1`. After compile, root copies populated staged `FactorySystemImageAssets.json` beside exact produced `FactoryProbe.exe` (`.factory-work\hosts\system-star-fill\package\.build\x86_64-unknown-windows-msvc\release\`) before native launch. Archive compiler/native receipts before any cleanup; record handle registration/release, provider map hash, host hash, screenshot pixels, & Mac observation separately. No parity claim follows from Mac observation alone.
