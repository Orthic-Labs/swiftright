# Paired reader root v1

Source-only handoff for fresh Text & source-aligned Padding Count20. Existing trusted readers remain authoritative; this packet creates no aliases, raw rewrites, qualification, parity, or golden result.

Pinned reader sources are recorded in `../circle-close-diagnosis-r1/diagnostic-capture-root-v6/source-manifest.json`; no reader source is copied or modified here.

## Text

Root must write one fresh `factory-text-circle-paired20-input-v1` JSON after fresh Windows Count20. It requires exactly 20 ordered rows, `capture/<32 hex>` & `image/<32 hex>` per row, identical caseID/caseHash/tupleID/tupleHash/sourceHash/recipeHash on both sides, exact parent proof with original handle retained, owned exit, streams sealed/drained, lock released, active job count zero, matching native PID, bounded raw/metrics/PNG refs, & source/case/tuple/recipe/compile/exe/renderer refs. Keep `status=observed-diagnostic`, `semantic=held`, `timing=raw-only`.

The existing reader performs bounded stat-before-open, symlink rejection, streamed SHA-256, JSON/image limits, identity joins, PID joins, Text viewport/font/wrap checks, & six real mutation controls:

```text
python3 factory/pipeline/pilot-next-source-v1/paired-text-circle-v1/compare_paired.py \
  --input <fresh-text-paired20-input.json> \
  --output <fresh-text-paired20-report.json>
python3 factory/pipeline/pilot-next-source-v1/paired-text-circle-v1/compare_paired.py \
  --input <fresh-text-paired20-input.json> --controls \
  --output <fresh-text-paired20-controls.json>
```

Mac source candidate remains explicit at `factory/oracle/mac/text-origin-r11-root-v1/observed-style-mac20-r3`; root must bind its exact fresh case/tuple/source/recipe refs into input JSON. No old case may be relabeled.

## Padding

Padding uses trusted F10 production reader & paired comparator. Root must first materialize an explicit input map from fresh Windows export rows; expected tuple is `sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011`, expected case is `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9`. Existing Mac source rows are under `factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1`; source, tuple, case, recipe, host hashes, run IDs, & raw byte refs must be joined by exact hash/bytes. Windows joins remain held until fresh Count20 export plus original parent certificate arrive.

```text
python3 factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/f10-production-reader-r4/prepare_f10_adapter_input.py \
  --export-manifest <fresh-padding-windows-export-manifest.json> \
  --artifact-export-manifest factory/pipeline/paired-rectangle-fixed-r11-root-v3/artifact-bytes-r1/export-manifest.json \
  --expected-tuple sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011 \
  --expected-case swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9 \
  --output <fresh-padding-f10-input-map.json>
factory/.venv/bin/python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/trusted-reader-report.py \
  --input <root-authored-padding-paired20-input.json> \
  --output <fresh-padding-trusted-reader-report.json>
factory/.venv/bin/python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/run-paired-comparison-r3.py \
  --input <root-authored-padding-paired20-input.json> \
  --output <fresh-padding-paired20-diagnostic.json>
```

F10 output must retain `qualified=false`, `nativeParityGranted=false`, `goldens=0`, `promotion=held`, raw timing, & separate semantic/paint/geometry diagnostics. Missing Windows rows, wrong case/tuple/source/host, duplicate IDs, bad bytes/hash, missing parent certificate, or altered artifact role must return blocked/exit 2 against fresh mutated copies.
