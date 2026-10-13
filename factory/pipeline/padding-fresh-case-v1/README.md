# Fresh Padding case packet r11

This packet repairs Padding source closure while preserving frozen r09/r11 records. Mac evidence is source-bound observational only: 20 runs, compiler exit 0, host `13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777`, witness `b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b`, runtime `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`. Raw AX/compositor references remain unchanged, including width observations; no normalization is applied.

Frozen `windows-replay-admission-r2/fresh-witness.manifest.json` has stale nested witness source hash `860fa789...`; `candidate-source-manifest.json` changes only that nested hash to measured `b969817f...`. Existing Mac case/tuple, compiler receipt, host build, raw archive, & old r09 donor remain immutable. Current Mac acceptance is `not-promoted`; future Windows run needs fresh issuer IDs after corrected manifest/materialization.

Validate source packet on Mac:

```sh
factory/.venv/bin/python factory/pipeline/padding-fresh-case-v1/validate-padding-fresh-inputs.py \
  --root /Volumes/D/claude/swiftright \
  --packet /Volumes/D/claude/swiftright/factory/pipeline/padding-fresh-case-v1/fresh-padding-inputs.json
```

Root then materializes into fresh ignored staging, using existing measured fresh case (never seed r09), corrected manifest, & actual Mac host receipt:

```sh
factory/.venv/bin/python factory/oracle/mac/padding-origin-r11-source-v1/materialize-r11-case.py \
  --base-case factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json \
  --base-manifest factory/pipeline/padding-fresh-case-v1/candidate-source-manifest.json \
  --host-receipt factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/host/host-build-r1.json \
  --output-case .factory-work/hosts/padding-fresh-r11/case.json \
  --output-manifest .factory-work/hosts/padding-fresh-r11/manifest.json \
  --output-tuple .factory-work/hosts/padding-fresh-r11/tuple.json
```

Before Windows launch, root must verify output canonical case/tuple hashes, source-binding bytes, compiler receipt closure, exact Windows executable/source/runtime/renderer refs, & corrected manifest hash. Mint fresh capture/image IDs; do not reuse r09/r11 IDs or relabel old observations. Windows count-1 admission comes first; count-20 follows only after original-parent, worker, memory, terminal, lock, & raw-stream proofs pass.

Required source faults: old r09 tuple; stale nested witness hash; candidate source/hash drift; wrong case/tuple ID; Mac or Windows host hash drift; compiler output/source/receipt drift; runtime/renderer/recipe/acceptance-config drift; missing source-binding or archive row; output collision; reused capture IDs; missing fresh Windows compiler closure. Every rejection must report `nativeActions=0`.

No parity, timing, qualification, or promotion claim is made here. AX mismatch remains raw evidence for later diagnostic comparison.

Run source faults under bounded root supervision:

```sh
factory/.venv/bin/python factory/pipeline/padding-fresh-case-v1/fault-controls-v1.py \
  --root /Volumes/D/claude/swiftright \
  --packet /Volumes/D/claude/swiftright/factory/pipeline/padding-fresh-case-v1/fresh-padding-inputs.json \
  --control-root /Volumes/D/claude/swiftright/.factory-work/padding-fresh-source-controls-r1
```

Controls invoke same validator against fresh copied inputs, cover positive plus 11 mutations, retain originals, & require every rejection to report `nativeActions=0`. Count20 source control mutates valid count `20` to invalid `21`; Count1 control seed is not reused unchanged.
