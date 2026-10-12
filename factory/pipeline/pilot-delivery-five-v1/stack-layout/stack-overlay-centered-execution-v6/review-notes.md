# Independent centered-host review

Reviewed original Mac source at `stack-layout/stack-overlay-aac89-mac-v1/mac-source/Sources/StackOverlayMacHost/CaptureHost.swift`. Mac wraps unchanged `Witness_stack_overlay` in `.fixedSize().frame(width: 320, height: 240, alignment: .center)`, then applies white background & light scheme. This is container placement around intrinsic witness, not a runtime rewrite.

Current runtime `37429120` confirms matching intrinsic behavior: `LayoutEngine.swift:79-81` measures root under `rootProposal`, then places root at origin with measured size; `.overlap` `stackPlan` returns max child size; `.overlay` returns first child base size & places overlay within it (`LayoutEngine.swift:371-430`). For this witness, base ZStack is 48×32 logical points; `Text("+")` remains overlay child. At scale 2.5, centered translation is computed from resolved pixel root frame, yielding approximately `(340,260)` pixels in 800×600 viewport. This matches Mac frame-center semantics.

`FactoryCenteredLayout.swift` applies same calculated delta to every resolved node in root subtree, while background stays full viewport. It does not alter stack/overlay runtime behavior or hide a stack size defect; it models explicit host frame placement present in Mac source. Finite/fitting guards fail closed if root exceeds viewport or geometry is invalid.

Root action: copy this packet into fresh `D:\\Claude\\swiftright\\.factory-work\\hosts\\stack-overlay-centered-r1\\package`, materialize fresh case/tuple bindings, then use retained-handle generic compiler lifecycle with exact `package/plan.json` argv. Existing `prepare-pilot-five-compile-v1.py` currently has no `stack-overlay` host choice; do not pass `custom-layout-v2` against this packet because that stages different source. No source bug found in centering adapter; native compile/capture remain root-owned.


Execution-v3 source correction: runtime emits `Overlay` for witness `.overlay`; adapter admits this explicit structural container alongside existing stack/container names. Child order, resolved geometry, witness bytes, runtime, renderer, bridge, & ABI remain unchanged.
