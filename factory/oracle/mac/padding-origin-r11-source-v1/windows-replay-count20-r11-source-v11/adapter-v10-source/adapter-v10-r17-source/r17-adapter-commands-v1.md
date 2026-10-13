# r17 Count20 adapter plan & archive roots

Source-only root guidance. It performs no native, GUI, lock, remote, compiler, or qualification action. r17 nonce, issued hash, capture IDs, image IDs, source hash, case hash, & tuple joins come from measured issued metadata.

```sh
repo=/Volumes/D/claude/swiftright
py="$repo/factory/.venv/bin/python"
src="$repo/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/adapter-v10-source/adapter-v10-r17-source"
namespace_rel="factory/native/windows/.work/windows-replay-r11/r17"
archive_rel="$namespace_rel/observed-native-v17-r1"
archive="$repo/$archive_rel"
issued_rel="$archive_rel/coordinator-r1/issued-metadata.json"
work="$repo/.factory-work/adapter-v10-r17"
fixture_rel=".factory-work/adapter-v10-r17/plan-fixtures"
plan="$work/plan-r17.json"
```

`namespace_rel` is Dell output namespace transported into repository. `archive_rel` is exact fetched native observation root, including measured raw files, coordinator/task receipts, worker outputs, compiler/source/runtime joins, & metadata rows. It is read-only input. Reader/archive destinations, controls, & derived plans stay under fresh `$work`; they must never be placed inside `$archive`.

`issued_rel` is anticipated r17 coordinator metadata row. Root must replace it only when fetched manifest names another exact repository-relative row; no discovery, fallback, copied v16 metadata, or caller-only nonce is allowed. Plan deriver rejects absolute/drive/UNC paths, symlink components, malformed IDs, source/case drift, duplicate IDs, wrong count, or frozen tuple binding.

Create fresh `$work` & supervise every local job:

```sh
mkdir -p "$work/logs"
supervise() {
  label="$1"; shift
  "$py" "$repo/factory/tools/supervise-job.py" --seconds 30 --rss-mib 256 \
    --out "$work/logs/$label" -- "$@"
}
base_rel="factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/fresh-count20-adapter-plan-v2.json"
supervise plan-fixtures "$py" "$src/test-r17-plan-deriver-fixtures.py" \
  --repo "$repo" --control-root "$fixture_rel" --base-plan "$base_rel" \
  --output "$fixture_rel/result.json"
supervise derive-plan "$py" "$src/derive-adapter-plan-r17.py" \
  --base-plan "$base_rel" --issued-metadata "$issued_rel" \
  --repo "$repo" --output "$plan"
```

Deriver output must carry `kind=factory-fresh-r11-count20-adapter-plan-r17`, `version=r17`, measured `issuedLineage`, exact issued metadata bytes/SHA, 20 distinct `capture/<32hex>` & `image/<32hex>` IDs, source/case joins, & `qualification=hold-until-r17-task-memory-proof-and-trusted-reader`. Fixture output has `nativeEvidence=false` & cannot qualify candidate.

After root verifies archive manifest & completed memory receipt, existing v10 producer/normalizer/adapter/reader commands may consume `$plan`; preserve `$archive` read-only & write reader output to fresh `$work/reader-archive-r17`. Missing proof roles, worker output paths, memory lineage, or any raw hash keeps candidate held.
