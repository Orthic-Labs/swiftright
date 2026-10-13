# Circle close diagnostic v4 source packet

SOURCE_ONLY Count1 packet. It binds fresh incremental plan/receipt, generated case/manifest/recipe/tuple, candidate binding/context, capture plan, serializer, integration bindings, MTA worker, renderer, executable, cleanup-v3 root helper, build script & job helper by streamed SHA-256/byte checks. Plan tuple host hashes are compared field-for-field; case/recipe hashes retain `sha256:` canonical form. Local admission documents are remapped into one installed Windows namespace, while measured plan/receipt/binaries remain explicit external refs. Every resealed dependent ref is updated after path/hash transforms.

Orchestrator: `prepare-circle-diagnostic-root-v4.py`. It creates fresh output, package, source graph, stage manifest, ZIP & installer; it never compiles, launches, locks, deletes, discovers recursively or edits donor files. Bounds: 256 files, 64 MiB/file, 256 MiB total, 4 MiB JSON. Native/compiler/lock actions remain zero.

First materialize `source-inputs-v4.json` with `materialize-circle-diagnostic-source-inputs-v4.py` from exact fresh generated refs. Then run one prepare command after all fresh binding/context refs exist:

```sh
python3 materialize-circle-diagnostic-source-inputs-v4.py \
  --plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json \
  --receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
  --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json \
  --case factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/cases/swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4.json \
  --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json \
  --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
  --binding <fresh-candidate-binding.json> --context <fresh-context.json> \
  --capture-plan <fresh-capture-plan.json> --serializer <fresh-serializer-control.json> \
  --integration-bindings <fresh-integration-bindings.json> --build-preflight <fresh-build-preflight.ps1> \
  --uia-worker <fresh-invoke-worker-mta.ps1> \
  --renderer <measured-renderer.dll> --exe <measured-FactoryProbe.exe> \
  --compiled-host-package 'D:\Claude\swiftright\.factory-work\hosts\circle\package' \
  --out .factory-work/circle-close-r11-r4/source-inputs-v4.json

python3 prepare-circle-diagnostic-root-v4.py \
  --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
  --overlay-root . \
  --output-root .factory-work/circle-close-r11-r4 \
  --source-inputs .factory-work/circle-close-r11-r4/source-inputs-v4.json \
  --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json \
  --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
  --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json \
  --case factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/cases/swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4.json \
  --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json \
  --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
  --binding <fresh-candidate-binding.json> --context <fresh-context.json> \
  --capture-plan <fresh-capture-plan.json> --serializer <fresh-serializer-control.json> \
  --integration-bindings <fresh-integration-bindings.json> --build-preflight <fresh-build-preflight.ps1> \
  --uia-worker <fresh-invoke-worker-mta.ps1> --renderer <measured-renderer.dll> --exe <measured-FactoryProbe.exe> \
  --cleanup-v2 <cleanup-v3.ps1> --renderer-cleanup-v2 <cleanup-v3.ps1> \
  --installed-root 'D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r4' \
  --external-plan-target 'D:\Claude\swiftright\.factory-work\hosts\circle\package\plan-close-final-r2.json' \
  --external-receipt-target 'D:\Claude\swiftright\.factory-work\hosts\circle\close-incremental-v2-final-r1\observation.json' \
  --external-exe-target 'D:\Claude\swiftright\.factory-work\hosts\circle\package\FactoryProbe.exe' \
  --external-renderer-target 'D:\Claude\swiftright\.factory-work\hosts\circle\package\FactoryRenderer.dll' \
  --zip-path .factory-work/circle-close-r11-r4.zip \
  --installer-path .factory-work/install-circle-close-r11-r4.ps1 \
  --stage-manifest-path .factory-work/circle-close-r11-r4-stage-manifest.json \
  --build-script <measured-build-circle-diagnostic-root-v4.ps1> --build-script-sha256 <sha256> \
  --job-helper <measured-Sr0OwnedJobProcess.cs> --job-helper-sha256 <sha256>
```

After staging, root installs ZIP with `install-circle-diagnostic-root-v4.ps1`, runs preflight controls, then separately issues fresh metadata. This packet reports diagnostic native observations only; it does not qualify parity or freeze tuple.
