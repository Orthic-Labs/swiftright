# F10 paired inputs r3

This packet rebases stale run-33877 logical refs onto three explicit archived Mac roots. `mac-path-map-r3.json` contains 423 fixed logical-to-physical paths. `mac-rebased-refs-r3.json` records each target's computed SHA-256 & byte count, plus fixed Mac capture refs for runs 1..20. No fallback root, path discovery, or live host path is admitted.

Source-only Mac validation:

```sh
python3 factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/validate-rebased-mac-r3.py --mac-only
```

After root supplies Windows20 output, update only `input-manifest-r3.pending.json` with exact `windowsCaptures` path & 20 `windowsArchives` rows keyed by canonical capture hashes. Each typed capture must carry production `meta.conditions.windowsExitProof` with all 13 production proof-role refs plus compiler/host/runtime/raw closure. Each archive directory must contain exact raw refs consumed by `verify_windows_exit_admission`; no synthesized proof or hashes.

Production reader + semantic comparison command:

```sh
python3 factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/run-paired-comparison-r3.py \
  --input factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/input-manifest-r3.pending.json \
  --output factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/report-r3.json
```

Command first runs exact archive reader & Windows exit admission for all 20 captures, then `factory.comparison.comparator.compare_case` over fixed Mac20 captures plus typed Windows20 captures. Result remains diagnostic: semantic/timing/parity/pixel parity/goldens/promotion stay held until independent acceptance evidence closes.

Current missing Windows joins:

- `windowsCaptures`: typed `normalized-observational` JSON at `factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r3/windows-captures.json`.
- `windowsArchives`: 20 exact canonical capture-hash to archive-directory rows from root Count20 adapter output.
- `windowsExitProof`: 20 production proof objects, each with all 13 production proof-role refs plus compiler/host/runtime/raw closure & raw archive bytes.
