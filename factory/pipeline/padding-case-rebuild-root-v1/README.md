# Fresh padding case rebuild v1

F10 hold comes from immutable identity mismatch:

* historic Windows source/capture plans use `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258` with case hash `sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d`;
* Mac20, issued Windows metadata, candidate tuple, & generated fresh case use `.r11.h13bfe5b8fbd9` with case hash `sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de`.

Existing receipts stay untouched. `materialize-case-bindings-v1.py` requires fresh case equality across Mac report, candidate, issued metadata, source/capture legacy-plan distinction, Count20, source hash, measured executable, & renderer. It emits only append-only preflight JSON.

Run source preflight from repository root:

```powershell
$repo='D:\Claude\swiftright'
$fresh="$repo\factory\oracle\mac\padding-origin-r11-source-v1\generated\13bfe5b8fbd9\cases\swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json"
$mac="$repo\factory\oracle\mac\padding-origin-r11-source-v1\observed-mac20-r1\mac-only-production-comparator-r1.json"
$src="$repo\factory\oracle\mac\padding-origin-r11-source-v1\windows-root-headless-r11-r1\observed-native-v17-r1\replays\r1\plan.json"
$capture="$repo\factory\native\windows\padding-capture-lease-capture-v3\capture-plan.json"
$candidate="$repo\factory\oracle\mac\padding-origin-r11-source-v1\windows-root-headless-r11-r1\observed-native-v17-r1\replays\r1\candidate-tuple.json"
$issued="$repo\factory\oracle\mac\padding-origin-r11-source-v1\windows-root-headless-r11-r1\observed-native-v17-r1\replays\r1\issued-metadata.json"
$bind="$repo\.factory-work\padding-case-rebuild-root-v1\case-bindings.json"
python "$repo\factory\pipeline\padding-case-rebuild-root-v1\materialize-case-bindings-v1.py" `
  --case $fresh --mac-report $mac --source-plan $src --capture-plan $capture `
  --candidate-tuple $candidate --issued-metadata $issued --output $bind
```

Then use existing append-only materializers with `$fresh` as `--case`, `$src` as immutable `--source-plan`, `$candidate`, `$issued`, and new roots under `factory/native/windows/.work/windows-replay-r11/fresh-case-v1/`. Compile fresh package bytes before capture-plan materialization; pass resulting compile receipt, executable, launch preflight, renderer, serializer, & candidate metadata to existing `materialize-fresh-capture-plan-v1.py`. Its output must retain `plan.case == fresh`, bind `sourceHash` to `Witness.swift`, bind measured executable/renderer hashes, and keep `executionEligible=false` until root executes full preflight.

Root must run unchanged v17 entry scripts from `factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v17/source-map-v17.json` only after fresh plan & fresh capture plan pass joins. Historic `replays/r1/plan.json`, v3 `capture-plan.json`, Mac20 raw archive, & prior Windows raw receipts remain immutable evidence.

## Fresh compiler package stage

After existing `materialize-fresh-padding-plan-v1.py` emits `$freshPlan`, stage source bytes into a new package namespace. `stage-fresh-compile-package-v1.py` copies bounded regular source files, rewrites only fresh package/scratch/replay roots, verifies current compiler & renderer hashes, verifies `Witness.swift`, runtime source receipts, exact fresh case & candidate tuple, then emits compile argv. It never invokes SwiftPM.

```powershell
$stage="$repo\.factory-work\windows-replay-r11\fresh-case-v1"
$package="$stage\package"
$scratch="$stage\package\build-fresh-r1\scratch"
$receipt="$stage\compile-package-stage.json"
python "$repo\factory\pipeline\padding-case-rebuild-root-v1\stage-fresh-compile-package-v1.py" `
  --case-bindings $bind `
  --fresh-plan "$stage\fresh-replay-plan-v1.json" `
  --source-package "$repo\.factory-work\hosts\padding-window-diagnosis\package" `
  --output-package $package --scratch-path $scratch `
  --producer-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-case-v1\producer" `
  --run-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-case-v1\replay" `
  --output-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-case-v1\outputs" `
  --compiler-path 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  --renderer-path "$repo\.factory-work\inputs\renderer\swiftright_render.dll" `
  --output-receipt $receipt
```

Expected stage receipt: `factory-padding-fresh-compile-package-stage-v1`, `executionEligible=false`, `nativeActions=0`, `compilerActions=0`, fresh `planSha256`, current compiler/renderer hashes, Witness hash, runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, & PE output path `...\out\Products\Release-windows-x86_64\FactoryProbe.exe`. Root must launch compiler through existing owned process supervision using emitted argv, prepend Swift runtime bin to `PATH`, retain compile receipt/exe hashes, then invoke capture-plan materializer with current compile outputs.
