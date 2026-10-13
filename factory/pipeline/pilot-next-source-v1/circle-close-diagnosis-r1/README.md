# Circle Count1 r5g close diagnosis r1

Circle raw evidence is preserved under `factory/native/windows/pilot-circle-root-v1/actual-count1-r5g-diagnostic`; this packet adds no native actions & does not alter old receipts.

Circle host PID 31152 rendered successfully: Bridge load/run markers, `FACTORY_RENDERER_READY`, 474 commits, window-closed marker at `2026-10-12T02:43:38.607Z`, clean renderer shutdown, sealed stdout/stderr, UIA worker exit 0, & final retained-handle exit 0. Coordinator still held `Owned renderer child deadline` because close-return at `02:43:38.7307369` reached 15s with retained kernel wait 258; cleanup later observed kernel wait 0 at `02:43:55.2336337`. Circle pixels were repeat-stable, while PrintWindow & screen methods differed; native parity remains held.

Text Count1 r5g uses same 15s capture loop & reaches kernel wait 0 about 144ms after close-return. Circle UIA worker completed naturally before close, so worker failure is unsupported. Evidence points to Circle-specific host/runtime shutdown latency plus an observed `.NET HasExited=true`/exit 0 versus retained-kernel wait 258 mismatch. Existing deadline stays strict.

Fresh diagnostic source should record monotonic markers around `graph.tearDown`, `measurer.releaseAll`, `bridge.shutdownComplete`, `Bridge.run` return, & `exit(result)`, while polling retained kernel handle beside `Process.WaitForExit`; hold admission until this separates wrapper wait-state mismatch from protected host/runtime shutdown. See `diagnosis.json` for exact paths, times, hashes, & pins.

## Source-bound candidate

`candidate-main.swift` is frozen Circle `Sources/FactoryProbe/main.swift` plus stderr-only `FACTORY_CLOSE_PHASE` markers. `circle-main-close-markers.patch` is exact unified diff; `frozen-inputs.json` pins every host source, plan, runtime receipt/tree, renderer, overlay, compiled exe, & compile receipt. Candidate changes no graph, measurement, bridge, deadline, or exit behavior.

Root execution sequence:

1. Copy frozen native package into fresh ignored candidate stage; verify every `frozen-inputs.json` path/hash before replacement of `Sources/FactoryProbe/main.swift` with `candidate-main.swift`. Keep original package, case, tuple semantics, runtime, renderer, compiler, scratch, lease, background guard, & `capture-circle-single-v3.ps1` unchanged.
2. Materialize fresh candidate plan from frozen plan `23f99cc23c81b2bb49b8bbe60a77123a94b840c8f2a0851073cd981760a5e308`; update only host source binding/source hash required by marker source, with explicit fresh plan hash. Preserve case/tuple, compiler, runtime, renderer, scratch, & compile request fields. Build candidate with pinned compiler/runtime/renderer inputs, then require source/case/tuple/exe/renderer/runtime joins before launch. Record fresh compile receipt; do not reuse old exe hash or relabel old plan/receipt.
3. Run one Count1 under existing owned coordinator with 15-second close deadline, 5-second stream drains, no activation, background guard, same capture lease. Start existing direct retained-handle observer before launch; retain original process handle, sample `WaitForSingleObject(handle, 0)`, `GetExitCodeProcess`, `Process.HasExited`, `Process.ExitCode`, & marker stderr using one monotonic deadline.
4. Require sealed stdout/stderr, direct handle terminal, signed/raw/.NET exit-code agreement, active job count zero, & lock release before any artifact/source restoration. Preserve held receipt on any mismatch.

Interpret marker order with lifecycle samples: `window-closed-enter` → graph teardown → measurer release → shutdown complete → `FACTORY_BRIDGE_RUN_END`/`mainactor-return` → `before-process-exit`. If direct handle remains 258 after `mainactor-return` while later reaches 0, hold host/runtime teardown; if direct handle reaches 0 before 15s while `Process.WaitForExit` lags, hold capture-wrapper wait-state only. Existing 15-second gate remains unchanged.

## Fresh source stage

`prepare-circle-close-diagnostic.py` is bounded stdlib packer. It admits exact donor main hash `900b982ac3ee69bc61814fa60eab7df379feaec89e0d2ab0a862a0386cded6e7`, exact candidate main hash `b761a826b249e7b918c6a25af8b3d9bccaced7005d1a35253fb3fd618a576a19`, explicit plan rows, no symlink components, no forbidden traversal, exact marker call count, required teardown/Bridge.run anchors, ≤256 files, ≤64 MiB/file, & ≤256 MiB total. It emits package ZIP, fresh `plan-prebuild-v2.json` with stage package/scratch paths, & stage manifest. `install-circle-close-diagnostic-v1.ps1` verifies archive/manifest/build/helper hashes, rejects traversal/duplicates/reparse entries, extracts only into fresh `D:\Claude\swiftright\.factory-work\hosts\circle-close-r1`, & performs no compile/native action. `build-circle-close-diagnostic-v1.ps1` derives from root-owned `build-circle-owned-v2.ps1` (`3d4b4d4cee16ad0ee974b624d6fb0eee2c2ce77ac82a7ed8d719b09d34c12808`), changes only stage literal, keeps exact `plan-$Phase-v2.json` path, suspended→assign→resume helper flow, 1 GiB job, `--jobs 1`, `-num-threads 1`, bounded streams, & compile-only status.

Root packer invocation:

```text
python3 factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/prepare-circle-close-diagnostic.py --donor-native-root factory/native/windows/pilot-circle-root-v1/actual-count1-r5g-diagnostic/native --donor-plan factory/native/windows/pilot-circle-root-v1/actual-count1-r5g-diagnostic/native/plan.json --donor-witness-manifest factory/native/windows/pilot-circle-root-v1/package-r3/witness.manifest.json --candidate-main factory/pipeline/pilot-next-source-v1/circle-close-diagnosis-r1/candidate-main.swift --output-package .factory-work/circle-close-r1-package --output-zip .factory-work/circle-close-r1-package.zip --output-plan .factory-work/circle-close-r1-plan-prebuild-v2.json --output-manifest .factory-work/circle-close-r1-stage-manifest.json
```

Windows installer invocation uses emitted archive/manifest hashes plus helper `factory/pipeline/pilot-next-source-v1/windows-task-memory-v1/Sr0OwnedJobProcess.cs` (`112e5775...c69e`):

```text
& .\install-circle-close-diagnostic-v1.ps1 -PackageZip .\circle-close-r1-package.zip -PackageZipSha256 <manifest.packageArchive.sha256> -StageManifest .\circle-close-r1-stage-manifest.json -StageManifestSha256 <stage-manifest-sha256> -BuildScriptPath .\build-circle-close-diagnostic-v1.ps1 -BuildScriptSha256 79448e4ba729185a1d791a23c2e4a2b8815579c315e4095018026b3f79b01344 -HelperPath .\Sr0OwnedJobProcess.cs -HelperSha256 112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e
& D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\build-circle-close-diagnostic-v1.ps1 -PlanPath D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\package\plan-prebuild-v2.json -PlanSha256 <manifest.plan.sha256> -Phase prebuild -PreflightOnly
```

Root runs compile only after preflight receipt; native Circle capture remains separate, preserves strict 15s/5s limits, & must issue fresh candidate plan/compile receipt before any launch.
