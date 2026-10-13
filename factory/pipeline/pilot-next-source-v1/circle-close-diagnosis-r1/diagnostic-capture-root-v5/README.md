# Circle close diagnostic root v5

Source-only Count1 preparer. `prepare-circle-diagnostic-root-v5.py` consumes explicit fresh Circle binding/context/tuple/case/manifest/recipe files & measured final-stage plan/receipt, then emits one bounded package, SI, graph, stage manifest, ZIP & installer. It never discovers files, compiles, launches, locks, deletes, or edits donor bytes.

Measured external joins are fixed by input bytes: plan `a47edfddc082d183dff2df6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1`, receipt `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`, EXE `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`. External Windows paths remain explicit; local donor/fresh paths are remapped to `--installed-root` before ref resealing. SI target is explicit `--source-inputs-target`; no SI ref points into Mac output paths.

Use v4 overlay directory only as named source input; missing overlay/helper fails closed. Cleanup v3 hash is `cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13` & both renderer/UIA roles are pinned. ZIP bounds are 256 files, 64 MiB/file, 256 MiB total, 4 MiB JSON. Output remains diagnostic-only; no parity, golden, qualification, or tuple freeze claim.

Root command shape (fresh binding/context/control docs must be supplied by root):

```sh
python3 prepare-circle-diagnostic-root-v5.py \
  --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
  --overlay-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v4 \
  --output-root .factory-work/circle-close-r11-r5 \
  --installed-root 'D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r5' \
  --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json \
  --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
  --tuple <fresh-tuple.json> --case <fresh-case.json> --manifest <fresh-manifest.json> --recipe <fresh-recipe.json> \
  --binding <fresh-candidate-binding.json> --context <fresh-context.json> \
  --capture-plan <fresh-capture-plan.json> --serializer <fresh-serializer-control.json> \
  --integration-bindings <fresh-integration-bindings.json> --build-preflight <fresh-build-preflight.ps1> \
  --uia-worker <fresh-invoke-worker-mta.ps1> \
  --renderer <measured-renderer.dll> --exe <measured-FactoryProbe.exe> \
  --cleanup-v3 <cleanup-kernel-authority-v3.ps1> --job-helper <Sr0OwnedJobProcess.cs> \
  --external-plan-target 'D:\Claude\swiftright\.factory-work\hosts\circle\package\plan-close-final-r2.json' \
  --external-receipt-target 'D:\Claude\swiftright\.factory-work\hosts\circle\close-incremental-v2-final-r1\observation.json' \
  --external-exe-target 'D:\Claude\swiftright\.factory-work\hosts\circle\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe' \
  --external-renderer-target 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' \
  --source-inputs-target 'D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r5\package\admission\source-inputs.json' \
  --zip-path .factory-work/circle-close-r11-r5.zip \
  --installer-path .factory-work/install-circle-close-r11-r5.ps1 \
  --stage-manifest-path .factory-work/circle-close-r11-r5-stage-manifest.json
```

Fresh docs must already be measured source bindings. Script validates plan/receipt kind, phase, diagnostic eligibility, candidate, tuple/case/source/runtime/renderer/EXE joins, raw manifest/recipe bytes, donor rows, named overlay/helper rows, path safety, ref bytes & final graph. Root runs parser/source controls & native stages separately.
