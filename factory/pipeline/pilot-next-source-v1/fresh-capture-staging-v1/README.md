# Fresh Rectangle/Text/Circle capture staging

`stage_fresh_capture_v1.py` is source-only staging for measured final Text-style, Circle, or admitted Rectangle plans. Text/Circle mode requires generated manifest/case/tuple, exact recipe & witness bytes, final Windows compile receipt, executable, serializer control, & pinned `uia-worker-invoke-v2.ps1`. Rectangle mode requires admitted Count1 `source-inputs.json`, producer `capture-plan.json`, & full config template; it rebases those exact refs into fresh Count20 roots without relabeling donor evidence. It validates canonical case/tuple/recipe joins, final plan/receipt/executable/source/runtime/renderer joins, compile exit/stream/job closure, fresh Count1/Count20 roots, & native action count zero.

It emits `capture-plan.json`, `source-inputs.json`, `config-template.json`, & `source-map.json`. `source-inputs.json` uses legacy producer kind/count fields, raw hash aliases, recipeFile, capturePlanPath/hash, compileRef, exeRef, rendererRef, & source-binding rows; config includes admission/control roots, package, run roots, source-input path/hash, & capture-plan path/hash. It records required UIA overlay as explicit hash-bound input; no worker overlay is silently inferred. It never creates native output, lock, worker, compiler, or GUI state. Historical cases/tuples remain lineage only.

Root invocation shape:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/fresh-capture-staging-v1/stage_fresh_capture_v1.py \
  --profile text-style|circle \
  --final-plan <measured-final-plan.json> --manifest <fresh-manifest.json> \
  --case <fresh-case.json> --tuple <fresh-tuple.json> --recipe <exact-recipe.json> \
  --compile-receipt <final/observation.json> --executable <FactoryProbe.exe> \
  --witness <exact-witness.swift> --uia-overlay <overlay/uia-worker-invoke-v2.ps1> \
  --serializer-control <serializer-control.json> --producer-root <fresh-producer-root> \
  --overlay-root <fresh-overlay-root> --first-run-root <fresh-count1-root> \
  --repeat-run-root <fresh-count20-root> --output <fresh-staging-dir>
```

Rectangle successor invocation:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/fresh-capture-staging-v1/stage_fresh_capture_v1.py \
  --profile rectangle --donor-source-inputs <admitted-count1/source-inputs.json> \
  --donor-capture-plan <admitted-count1/producer/capture-plan.json> \
  --donor-config-template <admitted-count1/config-template.json> \
  --producer-root <fresh-producer-root> --overlay-root <count20-overlay-root> \
  --control-root <fresh-control-root> --admission-root <fresh-admission-root> \
  --output-root <fresh-native-root> --integration-guard-path <fresh-overlay/integration-guard.ps1> \
  --integration-guard-hash <64-hex> --issued-metadata-path <fresh-admission/issued-metadata.json> \
  --issued-metadata-hash <64-hex> --serializer-control-sha256 <64-hex> \
  --successor-overlay-map <count20-lifecycle-v1/source-map.json> \
  --first-run-root <fresh-native-root/native-count1> \
  --repeat-run-root <fresh-native-root/native-count20> --output <fresh-staging-dir>
```

Root source controls should admit donor baseline, then reject mutated donor count, case/tuple/source hash, dispatch repeat count, missing source-binding row, wrong run root, & native-action value before native launch.
