# Circle close diagnostic root v6

Source-only Count1 packet for measured incremental Circle compile. It preserves frozen `capture-count1-r5g-sources`, adds fresh v6 overlay beside donor files, & keeps compiled EXE/renderer/receipt as external hash-bound refs.

Measured inputs:

- plan kind `factory-circle-incremental-compile-plan-v1`, raw SHA256 `a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1`
- receipt kind `factory-circle-incremental-owned-compile-v1`, raw SHA256 `fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428`
- EXE SHA256 `84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490`
- renderer SHA256 `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- source SHA256 `01f9fef3ab058a958bebf886191519e0102b05ff6b46acedd0d59a7aa8601f2e`
- tuple `sr1-circle-close-diagnostic-r11-20261012-r2`, case `swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.44413e65c5ae87e4`

Root runs preparer once with explicit donor, v6 overlay, generated tuple/manifest/recipe/witness, donor admission docs, measured plan/receipt, & external Windows paths. `--output-root`, `--zip-path`, `--installer-path`, & `--stage-manifest-path` must be fresh. Output contains `package/plan.json` from measured final plan, donor package rows, fresh admission docs, `package/overlay/root-v6` controls, `source-graph-v6.json`, & no binary copies.

Installer performs bounded ZIP/hash/path checks, creates fresh stage only, & emits source-only install receipt. Before native work, root points capture/coordinator at `package/overlay/root-v6` scripts, runs v6 source closure/integration/metadata controls, confirms issued metadata hash, then uses existing Count1 coordinator with `-PreflightOnly`. No qualification or parity claim is emitted.

Root command shape:

```text
python3 prepare-circle-diagnostic-root-v6.py \
  --donor-root factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources \
  --overlay-root factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/diagnostic-capture-root-v6 \
  --source-inputs factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/source-inputs.json \
  --final-plan factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/plan.json --final-receipt factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/actual-final-r1/observation.json \
  --tuple factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/tuple.json --manifest factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/manifest.json --recipe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/final-stage-r1/generated/recipe.json \
  --binding factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/candidate-binding.json --context factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/admission/context.json \
  --capture-plan factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/capture-plan.json --serializer factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/serializer-control.json \
  --integration-bindings factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/integration-bindings.json \
  --build-preflight factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/overlay/capture-build-preflight.ps1 \
  --uia-worker factory/native/windows/pilot-circle-root-v1/capture-count1-r5g-sources/producer/dependencies/uia-worker/invoke-worker-mta.ps1 \
  --renderer factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll --exe factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/root-rolling-incremental-v2/actual-prebuild-r1/FactoryProbe.exe \
  --cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 --renderer-cleanup-v2 factory/pipeline/owned-child-kernel-cleanup-root-v3/cleanup-kernel-authority-v3.ps1 \
  --installed-root D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\circle-close-r11-r6 \
  --external-plan-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\plan-close-final-r2.json \
  --external-receipt-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\close-incremental-v2-final-r1\\observation.json \
  --external-exe-target D:\\Claude\\swiftright\\.factory-work\\hosts\\circle\\package\\build-bound-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe \
  --external-renderer-target D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll \
  --output-root <fresh-local-packet> --zip-path <fresh-zip> --installer-path <fresh-installer> --stage-manifest-path <fresh-stage-manifest>
```

Local measured byte archives above have verified hashes. Installer now requires matching Windows external paths explicitly through `-ExternalExePath` & `-ExternalRendererPath`; it hashes both before extraction. After install, use `package/admission/source-inputs.json`, `package/overlay/root-v6/integration-fresh-circle-diagnostic-v6.ps1`, `package/overlay/root-v6/issue-circle-diagnostic-metadata-v6.ps1`, & `package/overlay/root-v6/coordinator-count1-diagnostic-v6.ps1`; pass fresh `RunRoot` below namespace & leave RunRoot absent before coordinator.

Installer invocation on Dell must pass same measured external refs:

```powershell
& .\install-circle-diagnostic-root-v6.ps1 -PackageZip $zip -PackageZipSha256 $zipSha -StageManifest $stageManifest -StageManifestSha256 $stageSha -SourceGraph $sourceGraph -SourceGraphSha256 $graphSha -BuildScriptPath $buildScript -BuildScriptSha256 $buildSha -HelperPath $helper -HelperSha256 $helperSha -ExternalExePath 'D:\Claude\swiftright\.factory-work\hosts\circle\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe' -ExternalRendererPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' -StageRoot 'D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r6'
```
