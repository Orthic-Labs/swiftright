**Verdict: off-track on direction. One block is near working; the two declared protected holds are built on a runtime bug and a host omission, and product code received no fixes since R7.**

## Direction finding

Effort since R7 went into factory host adapters, holds and packets, not into SwiftRight runtime or renderer behavior. The Rounded and bundled-font holds both misattribute cause:

- **Rounded corner hold rests on a runtime API bug.** The current runtime defaults the corner style to continuous at `factory/native/windows/api-shape-bbceb5a1-20261011/runtime/Sources/SwiftRightRuntime/Shapes.swift:80`. Apple's RoundedRectangle initializer defaults to circular; only the newer static rect shape defaults to continuous. The hold diagnosis treats the runtime default as witness semantics. Fixing the default is a permitted runtime change. After it, the shared mapper's throw at `FactoryResolvedNodeMapper.swift:107` never fires and the existing ABI rect radius plus border expresses the witness. Verified: runtime line. Unchecked: Apple default is from my knowledge, confirm with one grep of the SwiftUI swiftinterface.
- **lineLimit is already delivered to the host and ignored.** The ZStack host guards on `request.lineLimit` at `main.swift:19`, and the Tinos log prints `lines=3 lineLimit=1`. Truncation with an ellipsis belongs in the measurer the host owns. No ABI field is needed. The v5 hold is self-imposed.

## Defects root missed

- **Shared mapper regressed stroke geometry.** `FactoryResolvedNodeMapper.swift:123-126` draws the border inside unexpanded bounds. The v5 primitive at `FactoryShapePrimitive.swift:42-51` expands by half the line width for SwiftUI's centered stroke. Consolidation dropped the correct transform, so Rectangle stroke and Rounded stroke through the shared path will be one line width small.
- **Image glyph is probably rendered upside down.** `FactorySystemImageProvider.swift:104-106` flips rows bottom-up, but GetGlyphOutline bitmaps are top-down. A star flips visibly. The planned bounds, tint and coverage checks are invariant under vertical flip, so this verification cannot catch it. The GDI rasterizer is a second renderer in the host; the ABI measure request already carries family and color, so a Segoe Fluent Icons text run through the product renderer is the simpler honest route.
- **Custom Layout witness identity.** The receipt records witness sha 20bd…, the recipe registers 613d…. `Witness.swift:6-20` conditionally imports SwiftRightRuntime and aliases LayoutSize, LayoutRect and LayoutPoint. The unmodified SwiftUI witness does not compile on Windows. That runtime API gap is hidden by fixture adaptation and contradicts "same Swift witness".
- **Exact RGB is the wrong gate for strokes.** CoreGraphics and GPUI anti-alias differently, so stroke diffs never reach zero. The Windows ink ending one pixel early on right and bottom is the real geometry defect to chase.

## Original-block status

| Block | Evidence | Status |
|---|---|---|
| Rectangle fill/stroke | fill 20 exact per packet; stroke mapping wrong in shared mapper | fill working, stroke defective |
| RoundedRectangle stroke | 572 px diff, Win bbox short by 1 px | blocked by runtime default bug, not renderer |
| Image star.fill | no Windows build; flip risk | not started on Windows |
| ZStack/overlay | no Windows v6 build | not started on Windows |
| Bundled-font Text | 3 lines vs 1; renderer family unproven | lineLimit fixable now |
| Custom Layout | two static cases 0 diff x20; host log shows children at correct geometry | working for adapted witness |

Custom Layout receipts carry no non-white bbox, but the host log emits both Color nodes at the expected positions, so the match is content-bearing. Remaining recipe axes are draft demands; the recipe itself says candidate and pending review. They should not gate delivery. The witness-identity gap matters more.

## Strongest counterargument

Hold discipline prevents silently substituting circular geometry for continuous. That would be right if continuous were Apple's semantics. It is not. The holds protect a runtime deviation and a host omission, and the user said to stop adding machinery.

## Genuine holds

- Renderer-side bundled font loading. Process-private GDI registration is invisible to DirectWrite, and the ABI header exposes no font registration entry. This is protected code.
- Default-font policy is a product decision for the runtime, but it does not block ZStack. Text in a default font can never be pixel-exact across platforms; compare text by bounds tolerance and everything else exactly.

Resource flag: the Windows prebuild peaked at about 89% of the compiler cap. Ten and twenty expansion will exceed it. Unchecked: exit-0 receipts, process quiescence, Mac 20-run repeatability.

## Corrective actions

1. Change the runtime RoundedRectangle default to circular, restore centered-stroke expansion in the shared mapper, recapture Rectangle stroke and Rounded, and verify by bbox equality plus bounded edge delta.
2. Implement lineLimit truncation in the host measurer with an ellipsis search inside maxWidth, then capture Tinos. Prove renderer font selection with a one-off session-wide registration diagnostic or record the protected hold with that evidence.
3. Drop the GDI raster path for a renderer text run. If it stays, add a flip-sensitive row-profile check before any capture.

Next concrete action: edit `Shapes.swift:80` to default circular and rebuild Rounded through the shared mapper.
