# Custom Layout original API execution source packet v6

Fresh source-only packet for original recipe inputs `child-count=2`, `proposal-width=48`, `layout-direction=leftToRight`; case identity remains `swiftui.custom-layout.recipe/case/9e168af9151444e6`. Child frames remain 12x10 & 16x14, spacing remains 4, order remains `ForEach(0..<2)`. Runtime pin is `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer tuple11, ABI `0.6`.

Windows & Mac `Witness.swift` bytes are identical SHA256 `sha256:afe77cdfbd5c73943aeebe52c515f2149c7951a4e3512f1678cda6625cdb58f7`. Source uses direct `Layout`, `ProposedViewSize`, `CGSize`, `CGRect`, & `CGPoint` APIs behind only conditional module imports; no `AppleLayout` or `AppleGeometry` aliases remain. This exercises current runtime geometry bridge (`Layout.swift`) through its direct CGSize/CGRect overloads.

Windows package plan is resealed at `package/plan.json`; source bindings distinguish template recipe/case hash from expanded witness hash. Mac source plan is `mac-source/source-plan.json`, with same witness bytes, fixed 320x240pt opaque-white centered host, scale 2.5, and no native evidence. Root must perform existing bounded builds & captures; packet makes no parity claim.
