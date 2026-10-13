# SR0 paired timing diagnosis v1

Factory-only report packet for archived Windows observer-r6 evidence & existing Mac F1 evidence. It preserves raw bytes, strict parser thresholds, source pins & all qualification holds.

## Explicit inputs

Windows strict source refs:

- raw: `factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/actual-native-raw`
- frozen strict report: `factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/strict-input-repair-r2/strict-report/report.json`
- build: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json`
- incremental: `qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/incremental.json`
- source manifest: `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`
- source file: `6e0f6ffb9d5afebb249412e92cbc76583a17c1a24f6602016d86dfdfa94b5429`
- WorkloadWin: `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`
- renderer: `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`
- raw result: 2,720 B; PresentMon CSV: 693,538 B; PresentMon stderr: 65 B; retained handle: 2660.
- failed v5 raw comparison: `factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/actual-native-raw`; result 2,719 B, PresentMon CSV 959,029 B, nested worker exit 0, `stream_drains worker_stdout=0 worker_stderr=1`, so its timing rows remain held behind stream proof.

Mac timing source refs:

- report: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/mac-f1-report-r1.json`
- raw captures: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/actual-mac20`
- capture join: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/capture-start.json`
- source manifest: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/mac-source-manifest.json`
- report says `requiredRuns=20`, `observedRuns=20`, `passedRuns=20`, `status=qualified`, & F1-only admission. It carries raw identity joins, not comparable visible timing percentile fields.

## Existing captured Windows timing

Frozen report records 2,268 PresentMon rows in measured window, 110 displayed rows, expected ~3,600 rows, 33.3294 ms refresh interval, displayed interval p95 1,833.1842 ms, visible latency p95 1,543.5486 ms, & clock-correlation p95 0.3061 ms. Report is `INCOMPLETE` because display gate reports sparse display rows. These values diagnose capture state; they do not qualify Windows or establish parity.

## Root execution

Root runs existing bounded Windows materialization, then frozen strict analyzer:

```powershell
$repo='D:\Claude\swiftright'
$src="$repo\factory\pipeline\sr0-display-selfjob-v4\strict-input-repair-v1"
$raw="$repo\factory\pipeline\sr0-display-selfjob-root-v4\observer-r6\actual-native-raw"
$build="$repo\probes\sr0-b\workload\out\tuple12-source-build-v1\observed-workload-r10-v7-r1\runs\build.json"
$inc="$repo\qualification\tuple12-takeover\root-process-validation-v9\observed-incremental-v9-r1\incremental.json"
$out="$repo\.factory-work\sr0-display-strict-input-repair-windows-v1"
py -3 "$src\materialize-windows-inputs-v1.py" --raw-root $raw --build-path $build --incremental-path $inc --output-root $out --receipt "$out\materialize-receipt.json"
py -3 "$src\analyze-workload-v3-strict-input-v1.py" --os windows --root $out --out "$out\strict-report" --expect-runs 1 --expect-scale 2.5
```

Root then runs report-only diagnosis against frozen strict report & Mac F1 report:

```powershell
py -3 "$repo\factory\pipeline\sr0-display-selfjob-v4\paired-timing-diagnosis-v1\diagnose-paired-timing-v1.py" `
  --windows-report "$out\strict-report\report.json" `
  --mac-report "$repo\probes\sr0-s\fresh-on-bridge\out\tuple12-mac-preflight-takeover-v1\mac-f1-report-r1.json" `
  --output "$repo\.factory-work\sr0-display-paired-timing-diagnosis-v1\diagnosis.json"
```

Diagnosis output stays `diagnostic-held` & `parityClaim=false` until Mac report contains comparable raw timing references joined to same case/tuple. No threshold is relaxed & no receipt is relabeled.
