# Rounded stroke provider-hold diagnosis

Status: source diagnosis only; no source, packet, fixture, renderer, or ABI edits made here.

## Corrected finding

r12 proved startup hold was unconditional: `main.swift:190-192` passed nonempty `[.centeredContinuousRoundedStroke]` to `FactoryProviderPolicy.swift:7-9`, which returns a hold string for every nonempty list. r12 therefore exited `78` before `Bridge.load`.

That does not establish circular support for current runtime. Earlier diagnosis read stale snapshot `factory/native/windows/api-source-22172ff2-20261011/runtime/Sources/SwiftRightRuntime/Shapes.swift`, whose `RoundedRectangle` default was `.circular`. Current fresh runtime used by corrected packet is `factory/native/windows/api-shape-bbceb5a1-20261011/runtime/Sources/SwiftRightRuntime/Shapes.swift:80`, whose default is `.continuous`.

## Actual current behavior

r13 removed startup hold for observation. Its immutable stdout is:

```text
FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto
FACTORY_ABI_INITIAL_METRICS width=800 height=1396 scale=2.5
FACTORY_CENTERED_SUBTREE dx=350.0 dy=275.0 rootX=0.0 rootY=0.0 rootWidth=100.0 rootHeight=50.0 viewportWidth=800.0 viewportHeight=600.0
FACTORY_RENDERER_READY scale=2.5 width=800 height=600 hwnd=16189760 pid=42120 thread=9668 dpi=240 metricsSource=owned-client-rect
FACTORY_RENDER_ERROR Error Domain=FactoryContinuousRoundedStrokeProviderHold Code=78 "(null)"
```

Evidence path: `root-execution/rounded-stroke-native-capture-r13/failed-original-files/native/count1-r1/native-01/host.stdout.txt`; paired `final-exit-certificate.json` records exit `1`, & `capture-outcome.json` records renderer exit before capture. Window/viewport setup succeeded; failure occurs when shape mapper sees current default `.continuous`.

## Capability conclusion

Original witness is exact `RoundedRectangle(cornerRadius: 6)` with no explicit style, so current runtime resolves `.continuous`. `FactoryShapePrimitive.swift:18-22` intentionally rejects `.continuous`. ABI 0.6 exposes rect radius/border fields but no path primitive (`SWR_PRIM_PATH` is unsupported), and its rect fields do not prove continuous corner construction or centered-stroke edge semantics. Existing circular mapping cannot satisfy current witness.

Therefore unconditional startup removal is not a valid fix for original witness. Shortest legitimate resolution is retain provider hold until continuous rounded-stroke capability exists in runtime/renderer, or obtain an explicitly approved source/runtime change that resolves exact witness semantics without substituting circular geometry. Do not claim original witness is circular from stale runtime snapshot.
