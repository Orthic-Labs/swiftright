# Adapter v12 source: measured r17 Count20

v12 is isolated successor under `adapter-v12-source`; v11, v10, v9, & frozen v6 files remain unchanged. It consumes explicit r17 archive refs & performs no native, GUI, compiler, lock, remote, copy, or qualification action.

Producer admission binds actual compiler/source/host/runtime/module/executable/renderer bytes, memory receipt (`1GiB`, `0x200`, active process count `1`, `killOnJobClose:false`), parent/run nonce, issued capture/image pairs in run order, measured identity, retained-handle exit (`Wait=0`, `GetExitCodeProcess=0`), sealed stdout/stderr, terminal worker, & all 36 per-run raw files. Active count `1` is admitted only as supervisor-self-only after child-terminal control; live-child guard rejection, coordinator terminal/quiescence, lock release, & all 20 retained-host certificates are required. `native-observation.json` remains source of row facts; no independent ID sorting is used. Output stays `held-observation-only` until proof builder & trusted reader pass.

`normalize-inputs-v12.py` composes frozen v6 canonical capture validation after new r17 admission. It does not alter frozen normalizer or reader. `attach-adapter-proof-v12.py` checks proof bundle role joins, terminal/drain, self-only active-count, & external quiescence evidence. Production proof builder remains existing `windows-exit-proof-r2/build-count20-proof-r2.py`; trusted path is `run-trusted-reader-v12.py` over production `ArchiveByteReader` & `verify_windows_exit_admission`. Trusted archive materialization stores each unique source blob once under `_blobs/<sha256>` & hard-links per-capture paths, retaining 256MiB total bound without duplicate exe/DLL/compiler copies. It emits `reader-observed-rejections` with 20 bounded rows when protected admission blocks; it never relabels such rows as reader-verified.

Root command sequence (refresh output paths only; all paths are repository-relative):

```sh
repo=/Volumes/D/claude/swiftright
py="$repo/factory/.venv/bin/python"
src="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/adapter-v12-source"
archive="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-native-v17-r1"
out="$repo/.factory-work/sr1-adapter-v12-r17"
closure="$repo/factory/native/windows/padding-capture-lease-build-v1"
runtime="$repo/factory/native/windows/padding-capture-lease-build-v1/runtime-source-byte-archive-r1"
modules="$closure/actual-build-r1/runtime-module-archive"
renderer="$repo/factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll"
compiler="$repo/factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-archive-r1/swift.exe"
mkdir -p "$out"
"$py" "$src/produce-input-map-v12.py" --repo "$repo" --archive-root "${archive#$repo/}" --export-manifest "${archive#$repo/}/manifest.json" --issued-metadata "${archive#$repo/}/coordinator-r1/issued-metadata.json" --task-result "${archive#$repo/}/coordinator-r1/task-result.json" --plan "${archive#$repo/}/replays/r1/plan.json" --source-binding "${archive#$repo/}/actual-inputs/source-binding.json" --candidate-tuple "${archive#$repo/}/coordinator-r1/candidate-tuple.json" --candidate-binding "${archive#$repo/}/coordinator-r1/candidate-binding.json" --native-observation "${archive#$repo/}/replays/r1/native-observation.json" --compile-observation "${archive#$repo/}/actual-inputs/compile-observation.json" --runtime-receipt "${archive#$repo/}/replays/r1/runtime-source-receipt.json" --runtime-tree "${archive#$repo/}/replays/r1/runtime-source-tree.json" --witness "${closure#$repo/}/package/Sources/FactoryProbe/Witness.swift" --exe "${closure#$repo/}/actual-build-r1/FactoryProbe.exe" --renderer "${renderer#$repo/}" --compiler "${compiler#$repo/}" --host-source-root "${closure#$repo/}/package" --runtime-source-root "${runtime#$repo/}" --runtime-module "${modules#$repo/}/x86_64-unknown-windows-msvc.swiftdoc" --runtime-module "${modules#$repo/}/x86_64-unknown-windows-msvc.swiftmodule" --output "$out/input-map-v12.json"
"$py" "$src/test-adapter-v12-controls.py" --inputs "$out/input-map-v12.json" --output "$out/input-controls-v12.json"
"$py" "$src/normalize-inputs-v12.py" --inputs "$out/input-map-v12.json" --repo "$repo" --output "$out/normalized-v12.json"
"$py" "$src/test-normalizer-v12-controls.py" --normalized "$out/normalized-v12.json" --inputs "$out/input-map-v12.json" --repo "$repo" --output "$out/normalizer-controls-v12.json"
"$py" "$repo/factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r2/build-count20-proof-r2.py" --source-root "$repo" --captures "$out/normalized-v12.json" --input-map "$out/input-map-v12.json" --output "$out/proof-bundle-v12.json"
"$py" "$src/attach-adapter-proof-v12.py" --normalized "$out/normalized-v12.json" --inputs "$out/input-map-v12.json" --proof-bundle "$out/proof-bundle-v12.json" --repo "$repo" --output "$out/adapter-proof-v12.json"
pair="$repo/factory/pipeline/paired-padding-r11-v12"
"$py" "$pair/sourcebound-admission-v1.py" --repo "$repo" --input-map "$out/input-map-v12.json" --normalized "$out/normalized-v12.json" --proof-bundle "$out/proof-bundle-v12.json" --adapter-plan "${archive#$repo/}/fresh-count20-adapter-plan-r17-r1.json" --output "$out/sourcebound-admission-v1.json"
"$py" "$pair/test-sourcebound-admission-controls-v1.py" --repo "$repo" --input-map "$out/input-map-v12.json" --normalized "$out/normalized-v12.json" --proof-bundle "$out/proof-bundle-v12.json" --adapter-plan "${archive#$repo/}/fresh-count20-adapter-plan-r17-r1.json" --output "$out/sourcebound-controls-v1.json"
"$py" "$src/run-trusted-reader-v12.py" --proof-bundle "$out/adapter-proof-v12.json" --input-map "$out/input-map-v12.json" --plan "${archive#$repo/}/fresh-count20-adapter-plan-r17-r1.json" --input-archive-root "$repo" --archive-root "$out/reader-archive" --output "$out/trusted-reader-v12.json"
```

A missing proof, pair, byte, retained-handle, self-only active-count, external-quiescence, or stream-drain join must remain `HOLD`; no `ready` label may be emitted.

Source-bound report keeps fresh issued/native case joins intact while protected production gate retains source-plan case identity. If source-plan case differs, report status is `blocked-by-protected-production-gate`; no capture relabel or protected gate change is allowed.
