# Block swiftui.padding-frame (SR1 block 6)

Five original cases, each a Witness (`package/Sources/FactoryProbe/Witness.swift`, byte-identical in `mac-source/`), a 320 x 240 pt canvas captured at scale 2.5 (800 x 600 px). Filled `Color` and `Rectangle` make every edge visible in pixels. Hosts: `shared/make-case.py` copies the Witness to `mac-source/` and stamps both hosts (Windows: the shared product host `pilot-delivery-five-v1/shared-windows-host`; Mac: `shared/MacHost.swift`, offscreen `ImageRenderer`).

| Case | Covers |
|---|---|
| `padding-edges-v1` | `padding(_:)`, `padding(.horizontal/.vertical/.top/.leading/.trailing, n)`, `Edge.Set` arrays, `EdgeInsets`, default amount, fractional lengths, padding that moves siblings |
| `frame-alignment-v1` | `frame(width:height:alignment:)` for all nine alignments, oversized child, width-only and height-only frames |
| `frame-alignment-rtl-v1` | the same grid and per-edge padding under `layoutDirection = .rightToLeft` |
| `flexible-frame-v1` | `frame(minWidth/maxWidth/minHeight/maxHeight:alignment:)`, `.infinity`, bounds against offers of 200/100/60 pt, oversized child, min-only, infinite-max frames sharing an HStack |
| `nested-fractional-v1` | nested fixed frames, padding and stacks with fractional sizes and spacing (device-pixel snapping) |

Run: `python3 factory/tools/pair.py factory/pipeline/blocks-6-10/padding-frame/<case> --runs 20 --sandbox --stage <stage> --renderer D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll`.

**Tie rule.** An edge on an exact half device pixel (an odd number of points at scale 2.5) is rounded by SwiftUI by a value-dependent rule that the runtime now reproduces (`DevicePixelSnap`, see `../pixel-ties/README.md`); these witnesses still avoid such edges, and `../pixel-ties/` holds the cases that land on them.
