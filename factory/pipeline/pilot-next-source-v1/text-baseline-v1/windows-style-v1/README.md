# Text Windows style overlay

Count1-r5 rejected renderer source with `FactoryUnsupportedMeasurementStyle` before first layout. Failure source was strict legacy-body guard while Text witness emits explicit system 24pt regular/default font metadata.

`patch_text_measurer.py` writes fresh `main.swift` only. It admits exact `Font.system(size: 24, weight: .regular, design: .default).id` plus metadata `(family=nil, pointSize=24, weight=regular, design=default, isCustom=false)`, nil line limit, & measured scale. Legacy body, custom family, wrong font ID/size/weight/design, line-limit, & scale drift remain rejected. Existing `renderRun` retains exact font ID/metadata joins. `test_text_measurer_style_controls.py` applies positive & eight in-memory rejection fixtures source-only; no compiler/native process.

Root stages output into fresh Text package, binds new `plan.sourceHash` to generated `main.swift`, emits case-free prebuild plan, then compiles under existing lifecycle controls. Measured compiler/executable receipt feeds fresh tuple/case & final plan; fresh Count1 metadata precedes Count20 metadata. Failed r5 plan, receipt, case, tuple, & raw evidence remain immutable & are never rebound.

## Fresh measured binding

`materialize-text-style-case-v1.py` accepts only `plan-prebuild-r4.json`, successful `factory-text-owned-compile-v1` prebuild `observation.json`, archived Mac `run-001/capture.json`, fresh `--tuple-id`, & fresh `--acceptance-config-hash`. It streams bounded regular files, rejects symlinks, validates runtime `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer `sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, compiler `1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a`, source `sha256:4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e`, recipe `sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d`, receipt exit/stream/job/native closure, & measured executable bytes. Archived Mac tuple/case remain lineage only; Mac host hash is carried as measured input, archived Windows host hash is never reused.

Example root-owned invocation after receipt exists:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/text-baseline-v1/windows-style-v1/materialize-text-style-case-v1.py \
  --windows-plan <fresh-plan-prebuild-r4.json> \
  --windows-receipt <fresh-prebuild/observation.json> \
  --mac-capture factory/oracle/mac/text-origin-r11-root-v1/observed-mac20-r1/<old-case>/run-001/capture.json \
  --tuple-id <fresh-text-r11-windows-bound-id> \
  --acceptance-config-hash sha256:<measured-fresh-acceptance-config> \
  --output <fresh-text-materialized-dir>
```

Output contains fresh `tuple.json`, `cases/<id>.json`, `plan-final.json`, `manifest.json`, recipe/witness copies, & source-binding hashes. Qualification stays held pending fresh native Count1/Count20.
