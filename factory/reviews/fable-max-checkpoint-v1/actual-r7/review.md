**Verdict: at-risk.** The interval produced real Windows observations on three original witnesses, as R6 asked, but the residual-mismatch diagnoses are wrong or unsupported, and fixes are landing in five forked factory host packages rather than the runtime.

**Direction finding.** Mismatch attribution is the misdirection. The ZStack comparison records the plain-blue centre pixel as Mac RGB 0,136,255 versus Windows 0,122,255 at `stack-overlay-native-capture-r2/first-pixel-comparison.json:28-38`. The v3 host palette hard-codes `"system.blue":0x007affff` at `FactoryFill.swift:19`, so every blue pixel differs on Windows regardless of geometry. Rounded's witness strokes `Color.blue` at `Witness.swift:8`. Its 100×50 px frame with a 5 px centred stroke is a ring of roughly 1.4k to 1.9k pixels including edge coverage, and 1648 differ with difference bounds equal to the whole non-white box at `rounded-stroke-native-capture-r15/first-pixel-comparison.json:9-27`. That is the entire ring, not four corners. A continuous-versus-circular corner delta would be a few hundred pixels at most, so the "circular renderer approximation" narrative logged at `FactoryShapePrimitive.swift:23,47` explains nothing measured yet. Likewise the ZStack count of 9600 equals exactly the 120×80 px rectangle, so the "+" font diagnosis has no isolating evidence.

Second issue: palette, root centring with dx=360/dy=260 at `host.stdout.txt:4`, stroke-centring geometry, the one-glyph star sidecar and bundled-font family binding all live in FactoryProbe host code, duplicated per block. The custom-layout v3 red fix did not reach the ZStack or Rounded hosts. The additive runtime release at `sr1-plan.md:7-8` permits implementing these once in the runtime. Nothing observed required protected renderer or ABI edits.

**Block status.** Verified from files read unless marked claim.

| Block | Evidence | Status |
|---|---|---|
| Rectangle fill | 20/20 exact per R6, not re-read | Working, fill only |
| RoundedRectangle stroke | Count1, 1648 px differ, whole ring | Renders centred; colour wrong; corner question unmeasured |
| ZStack/overlay | Count1, 9600 px = entire rect | Correct bounds; colour wrong; text unmeasured |
| Custom Layout | Count1, 0 px differ; node 385,288 30×25 at scale 2.5 matches the 12×10 pt witness | Working for one child. `ForEach(0..<1)` at `Witness.swift:24` leaves spacing and index-sized children dead; confirm the recipe's child count was not reduced |
| Image star.fill | No Windows build. Registry hard-codes identity, glyph and `system.yellow` at `FactorySystemImageRegistry.swift:23-26,51-58` | One-glyph fixture, not Image semantics |
| Bundled Tinos Text | No Windows build or capture; no Mac20 | Not started |

Mac references are offscreen FactoryProbe renders at scale 2.5 per `manifest.json:3-10`, not displayed windows. Adequate for static paint, but state it.

**Strongest counterargument.** Host adapters are legitimate observation scaffolding: the runtime already emits shape style, line width and semantic colour names, and R6 endorsed rendering through available ABI fields to obtain measurements. True, and these are the first real measurements for three blocks. But measurements guide fixes only when residuals are read correctly. The current reading sends effort to corner geometry and font metrics while one wrong constant dominates both comparisons.

**Corrective actions.**
1. **Fix the blue constant once**, audit red and yellow, in one shared location, preferably the runtime. Re-capture Rounded and ZStack Count1 and report residual counts. Expect Rounded to drop to corner-only and ZStack to isolate the circle and "+".
2. **Collapse the five host forks** into one Windows host that consumes any witness. Ten and twenty blocks on the current pattern means twenty divergent palettes and centring adapters.
3. **Define "working" for Image now**: a name-to-glyph provider table, size from font metrics, tint from semantic colour, verified by bounds, tint and coverage mask rather than pixel exactness. Drop hash-bound sidecar and hand-rolled SHA-256 work. Then build Tinos v3 and run Count1.

**Holds.** Genuine: protected renderer and ABI while SR0 is OPEN, no Dell deletion, desktop-lock serialisation, memory caps, background windows. Unnecessary: pausing all dispatch while a read-only Mac-side review runs, recorded at `sr0-sr1-running-holds.md:4` and already flagged by R6. "Count1 insufficient" for custom Layout is correct but cheap; run Windows20 alongside the colour re-capture. The `factorySnappedExtentCanMatch` tolerance at `FactoryTextGeometry.swift:4-14` admits a one-pixel extent slack and needs its own fault control before any text comparison relies on it.

**Unverified.** The packet's FactoryShapeAdapter.swift path does not exist. The v4 Rounded palette is unread, so the blue inference rests on the v3 palette plus the ZStack centre pixel. Whether the recipe's custom Layout witness had more than one child. Rectangle 20/20 this session. Image v4 compilation. Process-budget coverage beyond owned supervisors.

**Next action.** Root sets the shared blue constant to the Mac-measured RGB 0,136,255, rebuilds the Rounded and ZStack hosts from one palette, and runs Count1 for both against the existing Mac20 references.
