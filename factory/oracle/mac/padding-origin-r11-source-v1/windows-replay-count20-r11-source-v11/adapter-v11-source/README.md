# Adapter v11: measured r17 export producer

v11 consumes one explicit `root-factory-native-v17-export-v1` inventory. It requires repository-relative `archive-root`, manifest, issued metadata, completed task result, source plan, candidate tuple/binding, native observation, compile/runtime receipts, & source-binding paths. It also requires explicit local compiler, executable, renderer, Witness.swift, runtime source tree, host source root, & produced runtime module paths. It validates each manifest/closure row by bounded stat, byte count, & streamed SHA-256 before emitting input map.

Expected export layout is explicit: `coordinator-r1/`, `actual-inputs/`, `overlay/`, `replays/r1/`, & `replays/r1/native-01` through `native-20`. No old 40-file metadata manifest, `coordinator-repeat-r1`, `actual-repeat-r1`, caller nonce, fallback discovery, archive copying, or relabeling is accepted.

Issued metadata must provide 20 distinct `capture/<32hex>` & `image/<32hex>` IDs, source/case joins, `frozenTupleBound:false`, completed task lineage, & 1 GiB memory receipt (`0x200`, active process count 1, `killOnJobClose:false`, bounded peak). Plan, source binding, task result, & export inventory hashes are measured refs.

Output includes 13 proof-role inputs for each actual native run & 24 raw rows per run. Output remains `held-observation-only` until proof-bundle production & trusted ArchiveByteReader admission. `produce-input-map-v11.py` performs no native, GUI, lock, remote, compiler, signing, or qualification action.

Root command after exact archive transport:

```sh
repo=/Volumes/D/claude/swiftright
py="$repo/factory/.venv/bin/python"
src="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/adapter-v11-source"
archive_rel="factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-native-v17-r1"
closure="factory/native/windows/padding-capture-lease-build-v1"
runtime="factory/native/windows/api-source-f7745d45-20261011/runtime"
modules="$closure/actual-build-r1/runtime-module-archive"
renderer="factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll"
compiler="factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-archive-r1/swift.exe"
"$py" "$src/produce-input-map-v11.py" --repo "$repo" \
  --archive-root "$archive_rel" \
  --export-manifest "$archive_rel/manifest.json" \
  --issued-metadata "$archive_rel/coordinator-r1/issued-metadata.json" \
  --task-result "$archive_rel/coordinator-r1/task-result.json" \
  --plan "$archive_rel/replays/r1/plan.json" \
  --source-binding "$archive_rel/actual-inputs/source-binding.json" \
  --candidate-tuple "$archive_rel/coordinator-r1/candidate-tuple.json" \
  --candidate-binding "$archive_rel/coordinator-r1/candidate-binding.json" \
  --native-observation "$archive_rel/replays/r1/native-observation.json" \
  --compile-observation "$archive_rel/actual-inputs/compile-observation.json" \
  --runtime-receipt "$archive_rel/replays/r1/runtime-source-receipt.json" \
  --runtime-tree "$archive_rel/replays/r1/runtime-source-tree.json" \
  --witness "$closure/package/Sources/FactoryProbe/Witness.swift" \
  --exe "$closure/actual-build-r1/FactoryProbe.exe" \
  --renderer "$renderer" \
  --compiler "$compiler" \
  --host-source-root "$closure/package" \
  --runtime-source-root "$runtime" \
  --runtime-module "$modules/x86_64-unknown-windows-msvc.swiftdoc" \
  --runtime-module "$modules/x86_64-unknown-windows-msvc.swiftmodule" \
  --output "$repo/.factory-work/adapter-v11-r17/input-map.json"
```

Root must substitute exact manifest/role filenames only when exported manifest proves different names. No aliases to historical r7/r16 paths are permitted.
