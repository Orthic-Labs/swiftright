# Paired padding settled v2

Successor to v1, preserving v1 raw report. Reads exact gate-seeded Mac20 evidence & capture-v4 partial Windows archive.

Windows archive has 18 started attempts: 15 eligible host observations, runs 3 & 16 retained as invalid-host captures because raw stdout contains `FactoryOwnedRendererHWNDAmbiguous`, run18 retained as `Owned renderer child deadline` with kernel wait `258`, runs19/20 never started. Peer review is bound by exact report hash `679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c`.

Only 15 eligible rows enter semantic comparison. All 18 raw rows remain represented with source/case/provider hashes & raw timing. Mac20 source/case/witness joins remain exact: source `b969817f…`, case `84951ddf…`, witness `860fa789…`; offscreen reference `96×40 @1`, compositor `96×72`; Windows reference `800×600 @240 DPI`.

Timing remains provider raw-only. Native parity, pixel parity, provider readback, goldens & promotion remain held. No retry or normalization is performed.

```sh
python3 factory/pipeline/paired-padding-settled-v2/report.py \
  --windows-root factory/native/windows/padding-settled-capture-v4/actual-repeat-r1
python3 factory/pipeline/paired-padding-settled-v2/report.py \
  --windows-root factory/native/windows/padding-settled-capture-v4/actual-repeat-r1 --fault-controls
```
