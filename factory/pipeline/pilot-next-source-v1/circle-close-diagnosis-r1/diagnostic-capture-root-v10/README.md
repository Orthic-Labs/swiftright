# Circle close diagnostic root v10

Source-only Count1 packet derived from measured incremental Circle final build. Frozen donor remains `factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources`; no binary is copied. Fresh v10 packet excludes measured serializer, build-preflight, MTA worker, & donor cleanup rows before copying each once, installs exact approved V3 cleanup helper bytes in renderer & UIA support roots, keeps `integrationGuardPath` under installed `package/`, rewrites only named donor production wait callers to `FactoryProcessWaitV6`, preserves root-v10 profile/tests as byte-stable negative controls, runs typed-reference, source integration, cleanup ABI, & fault controls, & rejects V5 in production callers.

R3 failure cause was donor `overlay/capture-circle-single-v3.ps1` plus support/UIA callers retaining `FactoryProcessWaitV5`. Fresh package-only rewrite binds those callers & their helper type to V6; frozen donor bytes remain unchanged.

Measured refs:

- plan `a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1`
- receipt `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`
- EXE `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`
- renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- source `01f9fef3ab058a958bebf886191519e0102b05ff6b46acedd0d59a7aa8601f2e`
- tuple `sr1-circle-close-diagnostic-r11-20261012-r2`, case `swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4`

Recipe identity uses both measured forms from final plan: semantic `recipe.hash = sha256:57fcd72382175df83a1fe29e4e387f1e902a37174caa44cd8fc50ebc0f411a15` (canonical JSON) & raw `recipe.sha256 = sha256:22cbc4a3652dbc14ea500112bc440056047c324a0a30f633d66d4913dc00858c` (generated/recipe.json bytes). v9 compared semantic plan hash with nonexistent recipe.hash field; v10 keeps raw recipeRef while recording semantic recipeHash.

Fresh packer seals tuple bytes before writing `candidate-binding.json`, then binds `canonicalTupleRef.sha256` to final tuple bytes; source controls include tuple-hash fault coverage. Next admission uses fresh `circle-close-r11-r10b` namespace.

Run preparer once with explicit measured paths, fresh local outputs, & Dell namespace:

```sh
python3 factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v10/prepare-circle-diagnostic-root-v10.py \
 --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
 --overlay-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v10 \
 --source-inputs factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/source-inputs.json \
 --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json \
 --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
 --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json \
 --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json \
 --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
 --binding factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/candidate-binding.json \
 --context factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/context.json \
 --capture-plan factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/capture-plan.json \
 --serializer factory/native/windows/padding-window-diagnosis-build-v1/dependencies/serializer-actual-r2/control.json \
 --integration-bindings factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/integration-bindings.json \
 --build-preflight factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v10/capture-build-preflight-diagnostic-v10.ps1 \
 --uia-worker factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/dependencies/uia-worker/invoke-worker-mta.ps1 \
 --renderer factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll \
 --exe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/actual-prebuild-r1/FactoryProbe.exe \
 --cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
 --renderer-cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
 --installed-root D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\circle-close-r11-r10b \
 --external-plan-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\plan-close-final-r2.json \
 --external-receipt-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\close-incremental-v2-final-r1\\observation.json \
 --external-exe-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\build-bound-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe \
 --external-renderer-target D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll \
 --output-root <fresh-local-packet> --zip-path <fresh-zip> --installer-path <fresh-installer> --stage-manifest-path <fresh-stage-manifest>
```

Dell installer verifies external EXE/renderer bytes, package-only archive roots, stage graph, source graph, full overlay closure, runs typed-reference, source integration, & fault controls, issues fresh metadata, writes complete `control/config.json`, then invokes coordinator `-PreflightOnly`. It performs zero native, compiler, GUI, or lock actions. `RunRoot` remains absent until later launch. Compiled host package binds canonical `D:\Claude\swiftright\.factory-work\hosts\circle\package`; dispatch packet package remains installed `package/` staging root, while typed local refs resolve under that staging root.

Generated config binds `outputRoot` to `<stage>\\native` & `runRoot` to strict descendant `<stage>\\native\\replays\\r1`. Production `Assert-CircleNestedRunRoot` rejects equal, sibling, & outside paths before metadata, dispatch, or capture joins seal.
