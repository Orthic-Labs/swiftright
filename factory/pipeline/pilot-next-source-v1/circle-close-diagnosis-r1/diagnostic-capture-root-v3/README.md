# Circle close diagnostic source packet v3

Source-only Count1 packet for `swiftui.circle.fixed.pilot-next.*` incremental compile output. It preserves diagnostic qualification=false, strict renderer, UIA, lock, job, stream, original-handle, 15-second native, & 5-second drain guards. It performs no compiler, native, lock, remote, or GUI action.

Measured inputs are supplied explicitly. Use `materialize-circle-diagnostic-source-inputs-v3.py` with actual final plan, receipt, generated tuple/case/manifest/recipe, binding/context, capture plan, serializer, integration bindings, build preflight, UIA worker, renderer, EXE, & compiled package paths. Helper rejects missing, reparse, changing, or oversized files, emits refs with bytes & SHA-256, preserves recipe raw hash separately from canonical recipe hash, & emits no placeholder values.

Measured final refs:

- plan SHA-256 `a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1`
- receipt SHA-256 `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`
- EXE SHA-256 `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`
- renderer SHA-256 `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`
- tuple id `sr1-circle-close-diagnostic-r11-20261012-r2`
- case id `swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4`
- canonical case hash `dfaa17fb33d46629b623f00e5315b818871a26647dd14a328f0524646ea6e674`
- canonical recipe hash `57fcd72382175df83a1fe29e4e387f1e902a37174caa44cd8fc50ebc0f411a15`
- raw recipe bytes hash `22cbc4a3652dbc14ea500112bc440056047c324a0a30f633d66d4913dc00858`

Example source-input generation, with every path replaced by an actual measured path supplied by root:

```text
python3 materialize-circle-diagnostic-source-inputs-v3.py --plan <plan-final.json> --receipt <observation.json> --tuple <candidate-tuple.json> --case <case.json> --manifest <manifest.json> --recipe <recipe.json> --binding <binding.json> --context <context.json> --capture-plan <capture-plan.json> --serializer <serializer-control.json> --integration-bindings <integration-bindings.json> --build-preflight <capture-build-preflight.ps1> --uia-worker <worker.ps1> --renderer <renderer.dll> --exe <swift.exe> --compiled-host-package <measured-package-root> --out <source-inputs.json>
```

Then source-stage with `prepare-circle-diagnostic-root-v3.py`, reseal with `reseal-circle-diagnostic-root-v3.py`, build a ZIP from emitted `package`, & run `test-circle-diagnostic-controls-root-v3.ps1`. Controls first admit one real baseline, then reject each source, tuple-host, serializer, preflight, case, receipt, & certificate mutation. Source controls report zero native, compiler, lock, & GUI actions.

External compiled package remains measured rolling path `D:\Claude\swiftright\.factory-work\hosts\circle\package`; plan consumers use `sourceInputs.planRef.path`, never `package\plan.json`. Install only into fresh `D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r3`. Packet does not relabel prior Circle captures or claim parity.
