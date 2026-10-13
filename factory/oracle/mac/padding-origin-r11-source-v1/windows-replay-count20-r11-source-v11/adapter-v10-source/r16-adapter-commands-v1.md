# r16 Count20 adapter orchestration

This is root-run source guidance. It launches no native process, acquires no lock, & does not qualify candidate. Keep fetched Windows evidence, metadata, controls, outputs, & reader destination in separate fresh roots.

```sh
repo=/Volumes/D/claude/swiftright
py="$repo/factory/.venv/bin/python"
src="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/adapter-v10-source"
issued="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-headless-v16-r1/coordinator-r1/issued-metadata.json"
issued_rel="factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-headless-v16-r1/coordinator-r1/issued-metadata.json"
archive="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-native-v16-r1"
work="$repo/.factory-work/adapter-v10-r16"
control="$work/fixture-controls"
plan="$work/plan-r16.json"
map="$work/input-map-r16.json"
inputs="$work/inputs-r16.json"
normalized="$work/normalized-r16.json"
reader_archive="$work/reader-archive-r16"
reader_report="$work/reader-report-r16.json"
supervise() {
  label="$1"; shift
  "$py" "$repo/factory/tools/supervise-job.py" --seconds 30 --rss-mib 256 \
    --out "$work/logs/$label" -- "$@"
}
mkdir -p "$work/logs"
```

Root must set `template`, `template_native`, `template_metadata`, `template_overlay`, `metadata_root`, `native_root`, `overlay_root`, `issuer_source`, & `task_result` as repository-relative paths from fetched manifest rows before running producer command. Keep `archive` absolute only as local reader root. Set `proof` to exact fetched proof-bundle path. Values below are placeholders until exact archive rows are measured; no path discovery or fallback is permitted.

```sh
base_plan_rel="factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/fresh-count20-adapter-plan-v2.json"
base_plan="$repo/$base_plan_rel"
supervise derive-plan "$py" "$src/derive-adapter-plan-r16.py" \
  --base-plan "$base_plan_rel" \
  --issued-metadata "$issued_rel" --repo "$repo" --output "$plan"
```

Deriver must report actual runID `01acb1d24a04471fa5709dac1c4a73c5` & issued metadata SHA `sha256:7216cd29266556cff4fec9a214f4bd5b403218db27d2007edc90823334e500e6`; any mismatch is HOLD.

Use v10 producer only after exact metadata/control/native transfer is present. `task_result` must be completed native task output carrying same runID, issued SHA, 1 GiB job receipt, active process count `1`, `0x200` memory flag, `killOnJobClose=false`, bounded peak, & positive parent PID. Do not pass `--allow-pending`.

```sh
supervise produce-input-map "$py" "$src/produce-input-map-v10.py" \
  --template "$template" \
  --template-native-root "$template_native" \
  --template-metadata-root "$template_metadata" \
  --template-overlay-root "$template_overlay" \
  --metadata-root "$metadata_root" \
  --native-root "$native_root" \
  --overlay-root "$overlay_root" \
  --issuer-source "$issuer_source" \
  --issued-metadata "$issued_rel" \
  --task-result "$task_result" \
  --output "$map" --repo "$repo"

supervise produce-inputs "$py" "$src/produce-inputs-v10.py" \
  --input-map "$map" --plan "$plan" --archive-root "$archive" --output "$inputs"

supervise run-adapter "$py" "$src/run-adapter-v10.py" \
  --inputs "$inputs" --plan "$plan" --archive-root "$archive" \
  --proof-bundle "$proof" --output "$normalized"

supervise trusted-reader "$py" "$src/run-trusted-reader-v10.py" \
  --proof-bundle "$proof" --input-map "$map" --plan "$plan" \
  --input-archive-root "$archive" --archive-root "$reader_archive" \
  --output "$reader_report"
```

`$proof` must be exact fetched `windows-exit-proof-r2` output, with 20 captures, 20 distinct prefixed capture/image IDs, 13 proof roles per capture, runtime tree/modules, compiler/source/exe/renderer joins, raw stream seals, coordinator release, & memory receipt. Reader destination must be fresh & separate from `$archive`; its 256 MiB operation bound applies. Reader output remains observational until paired comparison.

Run source-only fixture controls under fresh ignored roots. Outputs are diagnostics, never native evidence:

```sh
supervise v9-fixture-controls "$py" "$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/adapter-v9-source/test-adapter-v9-fixture-controls.py" \
  --control-root "$control/v9" --output "$control/v9/result.json"

supervise r16-plan-fixtures "$py" "$src/test-r16-plan-deriver-fixtures.py" \
  --control-root "$control/plan-deriver" \
  --base-plan "$base_plan" --output "$control/plan-deriver/result.json"

supervise memory-lineage-fixtures "$py" "$src/test-memory-lineage-fixture-controls-v10.py" \
  --control-root "$control/memory-lineage" \
  --output "$control/memory-lineage/result.json"
```

Every output path must be absent before run & created exclusively. Preserve fetched archive & metadata unchanged. Do not relabel r16 IDs, copy historical r7/r14 outputs, or infer missing proof hashes. Any missing role, source/case/tuple drift, raw ref mismatch, memory receipt mismatch, or reader rejection stays HOLD; parity/golden/freeze remain held.
