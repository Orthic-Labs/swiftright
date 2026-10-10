# GPUI 0.2.2 readback hook audit

## Pin & source

`render/swiftright-render/Cargo.toml:18-20` pins Windows GPUI as `=0.2.2`; `render/swiftright-render/Cargo.lock:2104-2108` resolves it from crates.io with checksum `979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707`. Internal source archive at `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/gpui-readback-audit/gpui-0.2.2.crate` matches lock checksum. Compact provenance is in [evidence/gpui-readback-source.json](evidence/gpui-readback-source.json).

## Findings

- **No exposed rendered-window texture readback hook found in pinned GPUI.** Windows `PlatformWindow::draw` forwards `Scene` to GPUI's internal renderer (`src/platform/windows/window.rs:844-846`). Its `DirectXRenderer` owns swap chain & render target (`src/platform/windows/directx_renderer.rs:60-75`), gets swap-chain buffer as render target (`:1112-1125`), draws scene & calls `Present(0, DXGI_PRESENT(0))` (`:286-316`). This path exposes neither target texture nor readback bytes through GPUI's platform trait (`src/platform.rs:494-502`).
- **No GPU-completion/fence hook found on Windows.** `PlatformWindow::completed_frame` is a default empty method (`src/platform.rs:500-501`); Windows implementation has no override (`src/platform/windows/window.rs`, `PlatformWindow` impl at `:518`). GPUI calls `window.present()` then `window.complete_frame()` (`src/window.rs:1047-1065`), while Windows renderer's `present` only calls DXGI `Present` (`src/platform/windows/directx_renderer.rs:203-207`). Treat that as a present submission/API return, not evidence of GPU completion or display scanout. No D3D fence/query/wait use was found in GPUI's Windows source.
- **A narrower readback exists, but it is not framebuffer capture.** `src/platform/windows/direct_write.rs:1032-1054` creates a CPU-readable staging texture for glyph rasterization; `:1111-1124` copies that glyph-layer render target & maps its bytes. Scope is text glyph layer output, not composed GPUI window scene.
- **Screen capture is a separate optional desktop capture feature.** GPUI gates it behind `screen-capture = ["scap"]` (`Cargo.toml:35-56`); renderer manifest uses default GPUI features, which omit `screen-capture`. Windows API delegates to `scap_screen_capture` only when enabled (`src/platform/windows/platform.rs:390-399`). It is not GPUI swap-chain readback or a GPU-fence signal.

## ABI 0.7 implication

Pinned GPUI source provides no direct public hook for exact rendered-window pixels or GPU-completion timing. A reliable GPU readback contract would require renderer/platform changes (for example, copying composed swap-chain output to a staging resource & reporting completion) or another explicitly qualified capture mechanism. GPUI `Present` return, `completed_frame`, and its glyph raster readback do not establish that contract. No paint/presentation timing claim follows from this source audit.

## Source anchors

Inspected extracted crate at `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/gpui-readback-audit/gpui-0.2.2/`. These are primary sources from exact locked archive; source line references above are relative to that tree. Archive SHA-256 equals lock checksum.
