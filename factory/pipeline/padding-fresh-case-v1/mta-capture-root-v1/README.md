# Padding Count1 MTA source packet

`prepare_padding_mta_root_v1.py` is source-only. It reads explicit fresh Padding case, manifest, tuple, compile plan, compile receipt, witness bytes & immutable Padding capture sources. It stages Text Count1-v7 MTA lifecycle files, V6 process-wait calls, root-v3 cleanup roles, worker-contract rows & fresh graph refs. It never launches PowerShell, Swift, native host, lock, SSH or GUI work.

Canonical case identity stays separate from raw case-file identity:

- canonical case hash: `sha256:9ece4c6f5de297a2a303c19cb95167b14e0291a77ee5e40f6d9b5dc7a65996cd`
- raw case JSON SHA256: `9be4e91b6048c5c2ee8167ffb2d78bbd36dc89ea81239fb7beab3f806f93130b`
- fresh plan SHA256: `214e73d4239604be7580add966c86fd387fa7985fef79ee307de81846a8b2433`
- fresh compile receipt SHA256: `0f3518e05fd6912246c84d34ab5479ca507f0880d1ab4f3b2aae9e4e20f7d20c`
- Windows host SHA256: `3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a`

Root-owned invocation after review:

```sh
python3 factory/pipeline/padding-fresh-case-v1/mta-capture-root-v1/prepare_padding_mta_root_v1.py \
  --padding-source-root factory/pipeline/padding-fresh-case-v1/windows-capture-root-v4 \
  --case factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/case.json \
  --manifest factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/manifest.json \
  --tuple factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/tuple.json \
  --plan factory/pipeline/padding-fresh-case-v1/windows-incremental-root-v4/root-controls-r1/plan-incremental-v4.json \
  --receipt factory/pipeline/padding-fresh-case-v1/windows-incremental-root-v4/root-controls-r2/actual-final-r2/observation.json \
  --source-witness factory/pipeline/padding-fresh-case-v1/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.swift \
  --namespace padding-mta-r11-count1-r1 \
  --output-root factory/pipeline/padding-fresh-case-v1/mta-capture-root-v1/generated/padding-mta-r11-count1-r1 \
  --output-zip factory/pipeline/padding-fresh-case-v1/mta-capture-root-v1/generated/padding-mta-r11-count1-r1.zip \
  --installer factory/pipeline/padding-fresh-case-v1/mta-capture-root-v1/generated/install-padding-mta-r1.ps1
```

Output is source-only pending Windows admission. Native qualification, parity, & frozen status remain held.
