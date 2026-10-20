# SR2 R1: compose and place (issue #36)

Block R1 of the SR2 plan (`docs/sr2-plan.md`): Group, ViewModifier with `.modifier`, `background` (colour and shape, including `background(alignment:content:)`), `offset`, `position`, GeometryReader, and `allowsHitTesting`. Runtime layout only; no ABI revision.

## Cases (`swiftui.compose/`)

12 pixel cases, each framed at about 240 x 160 pt inside the host's 320 x 240 viewport (the same viewport the F-path cases use, so the Windows host's fixed client size is unchanged). Solid colours and shapes only; no text. `pair.json` is `{}`, so the default gate applies: exact outside the 1 px edge band, at most 32 levels inside it.

- group-vstack-v1, group-modifier-v1
- viewmodifier-v1, background-color-v1, background-alignment-v1, background-shape-v1
- offset-v1, offset-negative-v1, position-v1
- geometryreader-v1, geometryreader-center-v1
- hittest-static-v1 (`allowsHitTesting(false)` must not change pixels)

Hit-test semantics are not gated here; they belong to the block 38 harness. `ci-list.txt` lists the case paths in the same format as `factory/pipeline/f-path/ci-list.txt`.

## Layout per case

`pair.json`, `mac-source/Sources/MacHost/{CaptureHost.swift,Witness.swift}`, and `package/{Package.swift, Sources/FactoryProbe/{Witness.swift,FactoryViewport.swift,main.swift}}`. The witness struct is `Witness_r1_<name>` (hyphens become underscores), renamed in `CaptureHost.swift` and `main.swift`. No `runs/` directories are included.

## Status

Authored only. Nothing has been built or run. Root integration owns the single verification batch.
