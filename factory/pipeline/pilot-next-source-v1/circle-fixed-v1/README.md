# Circle fixed pilot source packet

This packet defines one source-bound Circle candidate:

- `Circle().fill(Color.blue).frame(width: 40, height: 40)` under light color scheme.
- Fixed host client viewport `320x240` DIP resolved from measured physical pixels & finite scale, with existing owned-HWND/no-activation lifecycle.
- Runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer ABI `0.6`.
- Backend path is existing `ShapeGeometry.circle` -> `FactoryFillGeometry.circle` -> ABI `.rect` with radius `20`; no protected renderer or ABI change.

`host-branch.swift` is an additive branch proposal. `factory-fill-glue.swift` is an exact copy of existing reviewed `FactoryFill.swift`, retained only as source evidence. Root should adapt branch into a fresh host package after binding measured compiler, renderer, executable, recipe, case, tuple, source, runtime, and capture values. Existing live `FactoryProbe` files remain untouched.

Call `factoryRequireCircleFixedViewport(owned.size)` immediately after existing `factoryOwnedClient()` metrics resolve, before graph creation. Add Circle branch beside existing shape dispatch; retain existing `FactoryViewport.swift` ownership, DPI, window-title, no-foreground, and terminal proofs.

Source-only plan command after root has fresh explicit paths:

```text
factory/tools/supervise-job.py --seconds 30 --rss-mib 256 --out .factory-work/circle-source-controls -- factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/circle-fixed-v1/prepare-circle-plan.py --recipe <recipe> --case <case-inputs> --witness <witness> --runtime-shapes <Shapes.swift> --host-branch <host-branch.swift> --output <fresh-plan>
```

Root then stages fresh host source, runs bounded positive/fault controls, and separately binds actual compiler/host/capture receipts. No packet value substitutes measured host hashes.

`prepare-circle-plan.py` performs bounded source metadata hashing only. It does not compile, launch, acquire GUI, or acquire lock. `test-circle-controls.py` defines one admitted baseline plus four real in-memory mutations: frame, viewport, semantic color, and shape. Run through `factory/tools/supervise-job.py` only when root schedules source controls.

After Circle Windows prebuild returns measured tuple fields, materialize fresh case/manifest/tuple bytes with:

```text
factory/tools/supervise-job.py --seconds 30 --rss-mib 256 --out .factory-work/circle-case-materializer -- factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/circle-fixed-v1/materialize-circle-case-v1.py --tuple <measured-tuple.json> --output <fresh-circle-case>
```

Materializer emits canonical case/manifest/tuple, source bindings, & replay plan `Count1 -> Count20`; it preserves raw recipe hash alongside canonical recipe hash because Circle plan admission consumes raw recipe bytes. Root then regenerates final plan with measured executable hash, issues fresh Count1 metadata, & only after Count1 proof issues Count20 metadata. No Mac pixels or qualification are inferred during materialization.

Circle is source-supported by runtime `ShapeGeometry.circle` & existing host branch. `system.blue` maps to native `0x007affff`. Root must preserve actual observed client metrics; a declared 320x240 viewport cannot substitute for measured metrics. Qualification remains held until fresh host/capture evidence binds all values.

Mac capture wrapper is `mac-capture-v1/capture_origin_circle_r1.py`; it uses
hash-pinned `CaptureHost.swift` with `sizingOptions=[]`, 320x240 DIP, no activation,
& `Witness_circle_fixed`. `AXClient.swift` is pinned beside wrapper.
