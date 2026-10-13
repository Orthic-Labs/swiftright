# Circle close diagnostic root v7

Source-only Count1 packet derived from measured incremental Circle final build. Frozen donor remains `factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources`; no binary is copied. Fresh v7 packet fixes three admission defects: owned `source-inputs.json` uses atomic replacement, ZIP payload has package-only roots, & generated config carries complete coordinator fields plus overlay source bindings.

Measured refs:

- plan `a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1`
- receipt `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`
- EXE `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`
- renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- source `01f9fef3ab058a958bebf886191519e0102b05ff6b46acedd0d59a7aa8601f2e`
- tuple `sr1-circle-close-diagnostic-r11-20261012-r2`, case `swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4`

Run preparer once with explicit measured paths, fresh local outputs, & Dell namespace:

```sh
python3 factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v7/prepare-circle-diagnostic-root-v7.py \
 --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
 --overlay-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v7 \
 --source-inputs factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/source-inputs.json \
 --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json \
 --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
 --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json \
 --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json \
 --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
 --binding factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/candidate-binding.json \
 --context factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/context.json \
 --capture-plan factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/capture-plan.json \
 --serializer factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/serializer-control.json \
 --integration-bindings factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/integration-bindings.json \
 --build-preflight factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/overlay/capture-build-preflight.ps1 \
 --uia-worker factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/dependencies/uia-worker/invoke-worker-mta.ps1 \
 --renderer factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll \
 --exe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/actual-prebuild-r1/FactoryProbe.exe \
 --cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
 --renderer-cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
 --installed-root D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\circle-close-r11-r7 \
 --external-plan-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\plan-close-final-r2.json \
 --external-receipt-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\close-incremental-v2-final-r1\\observation.json \
 --external-exe-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\build-bound-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe \
 --external-renderer-target D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll \
 --output-root <fresh-local-packet> --zip-path <fresh-zip> --installer-path <fresh-installer> --stage-manifest-path <fresh-stage-manifest>
```

Dell installer verifies external EXE/renderer bytes, package-only archive roots, stage graph, source graph, full overlay closure, runs source integration & 25-fault controls, issues fresh metadata, writes complete `control/config.json`, then invokes coordinator `-PreflightOnly`. It performs zero native, compiler, GUI, or lock actions. `RunRoot` remains absent until later launch.
