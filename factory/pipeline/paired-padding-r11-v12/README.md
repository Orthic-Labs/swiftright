# Paired padding r11 v12 source-bound report

`sourcebound-admission-v1.py` joins fresh r17 adapter case/source/executable/renderer identity with issued order, measured observation rows, normalized captures, & 13 proof roles. It retains source-plan case separately, then reports protected `windows_exit_admission` case mismatch without relabeling captures or editing frozen gate/reader.

Run after v12 attach:

```sh
pair="$repo/factory/pipeline/paired-padding-r11-v12"
"$py" "$pair/sourcebound-admission-v1.py" --repo "$repo" --input-map "$out/input-map-v12.json" --normalized "$out/normalized-v12.json" --proof-bundle "$out/proof-bundle-v12.json" --adapter-plan "${archive#$repo/}/fresh-count20-adapter-plan-r17-r1.json" --output "$out/sourcebound-admission-v1.json"
"$py" "$pair/test-sourcebound-admission-controls-v1.py" --repo "$repo" --input-map "$out/input-map-v12.json" --normalized "$out/normalized-v12.json" --proof-bundle "$out/proof-bundle-v12.json" --adapter-plan "${archive#$repo/}/fresh-count20-adapter-plan-r17-r1.json" --output "$out/sourcebound-controls-v1.json"
```

## Fresh producer capture plan

After fresh package compile succeeds, materialize producer metadata from immutable v3 capture-plan plus fresh package/receipt/renderer/serializer bytes. Copy producer v3 tree to `$producerFresh`, place resulting `capture-plan.json` at its root, then run unchanged v17 overlays against `$producerFresh`:

```powershell
$pair="$repo\factory\pipeline\paired-padding-r11-v12"
$producerFresh="$repo\.factory-work\windows-replay-r11\fresh-v1\producer"
$package="$repo\.factory-work\hosts\padding-window-diagnosis\package"
$receipt="$package\build-capture-lease-r1\observation.json"
$exe="$package\build-capture-lease-r1\FactoryProbe.exe"
$preflight="$repo\.factory-work\hosts\padding-window-diagnosis\preflight.ps1"
$renderer="$repo\.factory-work\inputs\renderer\swiftright_render.dll"
$serializer="$repo\factory\native\windows\padding-capture-lease-build-v1\dependencies\serializer-actual-r2\control.json"
$issued="$repo\factory\native\windows\.work\windows-replay-r11\r17\coordinator-r1\issued-metadata.json"
python "$pair\materialize-fresh-capture-plan-v1.py" `
  --base-capture-plan "$repo\factory\native\windows\padding-capture-lease-capture-v3\capture-plan.json" `
  --source-plan "$package\plan.json" `
  --package $package --compile-receipt $receipt --executable $exe `
  --launch-preflight $preflight --renderer $renderer --serializer-control $serializer `
  --producer-root $producerFresh `
  --first-run-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-v1\producer\actual-single-r1" `
  --repeat-run-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-v1\producer\actual-repeat-r1" `
  --output-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-v1\producer" `
  --issued-metadata $issued `
  --candidate-tuple "$repo\factory\native\windows\.work\windows-replay-r11\r17\coordinator-r1\candidate-tuple.json" `
  --output "$producerFresh\capture-plan.json"
```

Materializer requires receipt `planSha256/sourceHash`, issued Count20 case/source/exe/renderer joins, & exact fresh package plan hash. It emits `actualBuild`, `dispatch.first/repeat`, preflight pin, serializer pin, output namespace, & lineage fields consumed by unchanged `prepare-capture`, `resume`, `dispatch`, & `capture` scripts. Native/compiler/gui/remote/lock actions remain zero in metadata stage.

`blocked-by-protected-production-gate` is truthful when frozen source-plan case differs from fresh issued/native case. No parity, golden, or trusted-reader readiness follows from source-bound evidence.

## Production paired observation route

After v12 trusted-reader observation, run `run-paired-comparison-v1.py` with exact fresh case, `normalized-v12-r3.json`, `adapter-proof-v12.json`, reader report/archive, Mac20 archive/comparator, & immutable `replays/r1/plan.json`. Reader emits `reader-observed-rejections` with exact per-row gate issues when protected case identity blocks admission; paired runner re-reads Mac captures through `ArchiveByteReader`, re-verifies every Windows proof through same reader, checks recorded row status, then calls production `compare_case` with observational holds. It emits `blocked-by-protected-production-gate` when source-plan case differs from fresh capture case; parity stays held.

```sh
pair="$repo/factory/pipeline/paired-padding-r11-v12"
out="$repo/.factory-work/sr1-adapter-v12-r17-r1"
archive="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-native-v17-r1"
mac="$repo/factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1"
case="$repo/factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json"
reader_archive="$out/reader-archive"
"$py" "$pair/run-paired-comparison-v1.py" --repo "$repo" --mac-root "$mac" --mac-manifest "$mac/raw-archive-manifest.json" --reader-archive "$reader_archive" --case "$case" --normalized "$out/normalized-v12-r3.json" --adapter-proof "$out/adapter-proof-v12.json" --reader-report "$out/trusted-reader-v12.json" --mac-report "$mac/mac-only-production-comparator-r1.json" --source-plan "$archive/replays/r1/plan.json" --output "$out/paired-comparison-v1.json"
"$py" "$pair/test-paired-comparison-controls-v1.py" --mac-root "$mac" --mac-manifest "$mac/raw-archive-manifest.json" --case "$case" --normalized "$out/normalized-v12-r3.json" --adapter-proof "$out/adapter-proof-v12.json" --reader-report "$out/trusted-reader-v12.json" --mac-report "$mac/mac-only-production-comparator-r1.json" --source-plan "$archive/replays/r1/plan.json" --output "$out/paired-comparison-controls-v1.json"

Export concise F9 JSON & HTML only after paired verdict & reader receipts exist:

```sh
f9="$out/f9"
"$py" "$pair/export-f9-report-v1.py" --paired "$out/paired-comparison-v1.json" --mac-report "$mac/mac-only-production-comparator-r1.json" --reader-report "$out/trusted-reader-v12.json" --output-dir "$f9"
```

Exporter requires candidate-only Count20, exact paired/reader row statuses, protected-gate receipt, & held parity/golden/promotion. It records paired comparator semantic/timing/repeatability verdicts, Mac semantic channel reasons, raw timing refs, Windows row reasons, & protected legacy-plan case mismatch. Channel difference hashes remain observational; it emits no parity, golden, or promotion claim.

## Fresh case-bound replay plan

Historic `replays/r1/plan.json` retains legacy case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258`; it must remain unchanged. Materialize append-only plan bound to Mac case, issued metadata, & candidate tuple before root compiles or replays:

```powershell
$repo='D:\Claude\swiftright'
$src="$repo\factory\oracle\mac\padding-origin-r11-source-v1\windows-root-headless-r11-r1\observed-native-v17-r1"
$case="$repo\factory\oracle\mac\padding-origin-r11-source-v1\generated\13bfe5b8fbd9\cases\swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json"
$fresh="$repo\.factory-work\windows-replay-r11\fresh-v1"
python "$repo\factory\pipeline\paired-padding-r11-v12\materialize-fresh-padding-plan-v1.py" `
  --case $case `
  --source-plan "$src\replays\r1\plan.json" `
  --candidate-tuple "$src\replays\r1\candidate-tuple.json" `
  --issued-metadata "$src\replays\r1\issued-metadata.json" `
  --package-path "$repo\.factory-work\hosts\padding-window-diagnosis\package" `
  --scratch-path "$repo\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch" `
  --compiler-path 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  --renderer-path "$repo\.factory-work\inputs\renderer\swiftright_render.dll" `
  --producer-root "$repo\factory\native\windows\padding-capture-lease-capture-v3" `
  --run-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-v1\replay" `
  --output-root "$repo\factory\native\windows\.work\windows-replay-r11\fresh-v1\replays" `
  --output "$fresh\fresh-replay-plan-v1.json"
```

Output preserves immutable source-plan shape & binds `plan.case == issuedMetadata.case == candidateTuple.case`, source hash equal to pinned `Sources/FactoryProbe/Witness.swift`, measured executable equal to candidate Windows host hash, & renderer bytes equal to tuple renderer hash. Package, scratch, compiler, & renderer paths remain source-plan bindings; only producer/run/output roots are fresh. Production compiler argv is copied from recorded `replays/r1/observation.json` with no added concurrency flag or unverified environment claim. Root must stage exact source/runtime/renderer bytes, then use v17 `issue`, `resume-issued-coordinator`, `dispatch`, `capture`, `first-proof`, `worker-output-preflight`, & integration guard scripts. Every run must retain numeric exit, streams, active count, raw hashes, & source/exe/renderer/runtime joins.
```
