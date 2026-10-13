# SR0 r13 capture-held reader

R13 completed capture & terminal cleanup while remaining qualification-held. This packet adds report-only admission for that state. It accepts exactly:

- launcher `sr0-display-launcher-v8-status`, `status=held`, child receipts read, aggregate descendants quiescent, active count `1`;
- collector `sr0-display-collector-v8-drain-pidjoin`, `status=qualification-held`, `captureComplete=true`, `qualificationHeld=true`, hold reason `strict-display-parser-pending`, retained parent handle, workload/PresentMon terminal identities, sealed streams, valid CSV evidence, workload task quiescence, `lockReleased=true`;
- coordinator `sr0-display-coordinator-v5`, `status=held`, parent kernel/.NET/raw exit `0`, no parent qualification certificate, no lock owner observation, `final-kind` error.

`Test-CaptureHeldTerminalV13` is report-only. It emits no qualification claim & performs no lock action. `test-capture-held-controls-v1.ps1` AST-extracts that exact function, pins three actual r13 receipts, accepts actual held evidence, & rejects nine mutations.

## Actual r13 pins

- run manifest: `a0d6769783b0d88e494e76368e39fb0cabfa9239e622fa5bc965b0ccca42b74e` (5,653 bytes)
- launcher receipt: `f302d8275545238770953739a76922cb0acd097956a2a86938aecd23f6ef50ff`
- collector receipt: `638538d7c481a2363f54f73f129229799be9629566a8bbb2bb870849f2fed2a8`
- coordinator receipt: `521bf3af3e23bef586f289ff1a05e6105831b6880448b36f2d83981327be33dc`
- PresentMon CSV: `b080fcab80dd5b802a82e844cdd2a8e7c95c84a1e4b9efc9e6b72c4820a2f76e` (926,320 bytes, 4,506 rows, 4,203 WorkloadWin rows, target PID 17076)
- PresentMon stderr: `f522a4b28ee9eedb6189a4389f8fa839f193614ad098940bb23ae59e6d185b28` (65 bytes, benign warning)

Receipts must be materialized from `live-read-transport-r1` into fresh files named `launcher-receipt.json`, `collector-receipt.json`, & `coordinator-verdict.json`; controls reject path/hash drift. Historical r12/r13 raw evidence remains immutable.

## Root control command

```powershell
& .\test-capture-held-controls-v1.ps1 `
  -CaptureRoot '<fresh-r13-receipt-root>' `
  -PredicatePath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\sr0-r13-capture-held-reader-v1\capture-held-predicate-v13.ps1' `
  -SourcePinsPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\sr0-r13-capture-held-reader-v1\source-pins.json' `
  -ControlRoot '<fresh-control-root>'
```

## Offline strict display parser

Capture-held reader does not qualify display output. After receipt controls pass, root may materialize an analysis root from sealed r13 bytes & run frozen parser:

```powershell
& py -3.11 -I '<repo>\qualification\tuple12-takeover\workload-analysis-v3\analyze_workload.py' `
  --os windows --root '<fresh-r13-analysis-root>' --expect-runs 1 --expect-scale 2.5 `
  --out '<fresh-r13-analysis-root>\report'
```

`<fresh-r13-analysis-root>` must contain exact bounded source-bound files before parser start:

- `result-workload.txt` from r13 workload result;
- `presentmon.csv` (sealed r13 CSV above) & `presentmon.console.txt` derived only from sealed PresentMon stdout/stderr bytes;
- release `build.json`;
- `r1/meta.json`, `r1/integrity.json`, `r1/inputs.csv`, `r1/frames.csv`, `r1/bridge_input.csv`, `r1/ticks.csv`, `r1/mainactor.csv`, & `r1/inject.csv`.

Parser also reads `resources.csv`, `resources-meta.json`, & `overhead_probe.csv` when present. R13 collector sealed `presentmon.stdout.txt`/`presentmon.stderr.txt`; it did not publish frozen analyzer `presentmon.console.txt`, so missing console or run tables must remain an explicit parser hold. No console, build, run table, or display row may be synthesized. Frozen thresholds, PID/QPC joins, `Dropped=0`, `msUntilDisplayed`, timing limits, & qualification gates remain unchanged.
