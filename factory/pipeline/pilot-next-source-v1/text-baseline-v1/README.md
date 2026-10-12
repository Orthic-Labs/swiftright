# Text baseline pilot source packet

`swiftui.text.layout.baseline.pilot-next` is source-only. Witness uses `Text("Aa")`, system regular 24pt font, primary foreground, light color scheme, & 120x48 centered viewport. Font family, fallback, scale, baseline, AX/UIA text nodes, complete raw trees, compositor pixels, source hash, runtime commit, renderer hash, host hashes, & compile receipts are measured joins. Missing semantic text values remain held with raw evidence preserved.

Materialize only from measured tuple bytes:

```sh
REPO=/Volumes/D/claude/swiftright
PYTHON=$REPO/factory/.venv/bin/python
PACKET=$REPO/factory/pipeline/pilot-next-source-v1/text-baseline-v1
OUT=/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/text-baseline-<fresh>
SWIFTRIGHT_REPO_ROOT=$REPO PYTHONPATH=$REPO "$PYTHON" "$PACKET/materialize-text-case-v2.py" \
  --tuple "$OUT/measured-tuple.json" --output "$OUT/generated"
```

After root records both measured host hashes in tuple, build same source on internal disk, then require exact binary hash before any capture:

```sh
SWIFTRIGHT_REPO_ROOT=$REPO PYTHONPATH=$REPO "$PYTHON" "$PACKET/build_text_host.py" \
  --output "$OUT/mac-prebuild"
MAC_HASH=$($PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"]["sha256"])' "$OUT/mac-prebuild/host-build-r1.json")
SWIFTRIGHT_REPO_ROOT=$REPO PYTHONPATH=$REPO "$PYTHON" "$PACKET/prepare_text_host.py" \
  --manifest "$OUT/generated/manifest.json" --case "$OUT/generated/cases/"*.json \
  --output "$OUT/mac-final" --expected-binary-hash "$MAC_HASH"
HOST_HASH=$($PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"]["sha256"])' "$OUT/mac-final/host-build-r1.json")
SWIFTRIGHT_REPO_ROOT=$REPO PYTHONPATH=$REPO "$PYTHON" "$PACKET/capture_origin_text_fixed_r1.py" \
  --manifest "$OUT/generated/manifest.json" --case-root "$OUT/generated/cases" \
  --scratch "$OUT/capture-scratch" --output "$OUT/mac-evidence" --runs 20 \
  --expected-host-hash "$HOST_HASH"
```

Root must stage measured Windows host build separately, then materialize fresh canonical tuple/case with both host hashes. Windows execution reuses only lifecycle sources listed in `source-manifest.json`; it must bind Text font/viewport fields before Count1.

Tuple requires exact current runtime `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer `sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, measured Mac & Windows host hashes, SDK, macOS build, toolchains, factory version, & acceptance config. Root stages source rows from `source-manifest.json`, then builds same witness on internal disk. Existing Rectangle same-group Mac capture, bounded AX client, Windows Count1/Count20 lifecycle, job helper, & generic integration guard are explicit immutable dependencies; root must bind fresh Text source inputs before use.

Admission order is Mac prebuild, Windows prebuild, measured tuple/case, Count1, then Count20. Count1 requires fresh prefixed IDs, no-prompt AX/screen preflight, background window placement, complete raw AX/UIA, pixel archive, retained handles, sealed streams, terminal worker/renderer proof, 1GiB self-job, & lock release. Count20 additionally requires successful Count1, 20 ordered IDs, unchanged font/viewport contract, all source/runtime/renderer/host joins, & trusted-reader acceptance. Historical padding, Rectangle, or stale provider metadata cannot satisfy Text admission.

No source step requests permission or activates foreground. Mac capture uses `orderBack(nil)` through same-group protocol; Windows adapter uses background placement. Display or parity remains held until independent reader joins fresh raw archives.
