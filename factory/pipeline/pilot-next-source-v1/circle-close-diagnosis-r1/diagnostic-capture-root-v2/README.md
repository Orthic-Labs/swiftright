# Circle close diagnostic Count1 source packet v2

This packet stages one fresh Circle diagnostic capture from measured incremental Windows compile evidence. It preserves prior `diagnostic-capture-v1` & donor `capture-count1-r5g-sources`; it never relabels historical `factory-circle-compiler-plan-v1` / `factory-circle-owned-compile-v1` evidence.

Measured final inputs are bound before staging:

- plan `a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f`
- receipt `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`
- candidate Windows executable `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`
- tuple `44413e65c5ae87e479129531458f5910a9477dc6cf3b8961db9e449755dec65f`
- runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`
- renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- root-v3 cleanup successor `cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13`

`prepare-circle-diagnostic-root-v2.py` copies only rows declared by donor `stage-manifest.json`, explicit diagnostic overlay files, measured evidence, & cleanup-v2 into a new source root. It enforces regular-file/reparse/path/size/total bounds, exact plan/receipt/tuple/executable/runtime seals, fresh destination, & graph rows. It performs zero compiler/native/remote/lock actions.

Stager replaces both UIA worker callsites & renderer callsite in fresh output so root-v3 cleanup receives measured worker/renderer executable hash; `sourceTransforms` records donor/new hashes. Donor bytes remain unchanged.

Root source command, with actual measured `source-inputs.json` & explicit local final evidence paths:

```sh
python3 prepare-circle-diagnostic-root-v2.py \
  --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
  --overlay-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v2 \
  --output-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/circle-close-r11-r2/source \
  --source-inputs source-inputs.json \
  --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/plan-final.json \
  --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
  --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json \
  --case factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/cases/swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4.json \
  --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json \
  --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
  --cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
  --renderer-cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1
```

Reseal fresh output before packaging. This refreshes source-inputs hash after adding explicit renderer/UIA cleanup-v2 role pins; root must use resulting file hash for coordinator arguments:

```sh
python3 reseal-circle-diagnostic-root-v2.py \
  --source-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/circle-close-r11-r2/source \
  --cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
  --renderer-cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1
```

Root then creates ZIP from `source/package` only, writes stage-manifest rows from graph, & invokes installer with `-StageRoot D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r2`; installer remains source-only.

Root creates ZIP only from generated `package`, writes `factory-circle-incremental-diagnostic-stage-v2` manifest from `source-graph-v2.json`, then runs `test-circle-diagnostic-controls-root-v2.ps1` against staged source inputs. Installer `install-circle-diagnostic-root-v2.ps1` verifies ZIP/manifest/graph hashes, rejects existing stage/reparse/traversal/oversize/duplicate rows, extracts into fresh `D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r2`, & emits source-only receipt. It does not run build or capture.

Before ZIP creation, root runs `reseal-circle-diagnostic-root-v2.py` against fresh source output. It updates only explicit integration-bindings, worker-contract, capture-plan, & source-input rows, binds both renderer/UIA cleanup-v2 roles, refreshes graph rows, & fails when any required role is absent. Resealing never edits donor or historical receipts.

Actual capture remains root-owned: use overlay scripts only after source controls pass; use incremental plan/receipt kinds, fresh Count1 metadata, noactivate/background renderer, strict 15-second renderer deadline & 5-second drain, retained original handles, full worker release proof, `executionEligible=true` with qualification `diagnostic-native-only-not-qualified`.
