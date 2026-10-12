# SR0 strict input repair v1

Fresh adapter for archived Windows run:
factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/actual-native-raw.

Frozen report observer-r6/strict-parser-original-r1 refused four input joins:

- presentmon.console.txt absent; raw capture has separate PM stdout (0 B) & stderr (65 B).
- build.json absent from exported raw namespace; exact release artifact binding exists in
  probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json.
- incremental.json absent; exact 3-edit receipt exists in
  qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/incremental.json.
- W7 remains held unless explicit incremental receipt passes source-manifest identity.

materialize-strict-inputs-v1.ps1 copies bounded raw result/CSV/r1 traces, joins PM
stdout then stderr into fresh presentmon.console.txt, derives release build.json
with original artifact/source-manifest hashes, & copies explicit incremental receipt.
Raw files stay unchanged; output receipt records every source/hash. It preserves
pid_exit ... handle=2660 ... unchanged. analyze-workload-v3-strict-input-v1.py
accepts optional handle tail in both pid & pid_exit records, with thresholds,
display joins, 60 Hz assertion, & incremental semantics unchanged.

Known pins from archived evidence:

- exe 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c
- renderer 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
- source manifest 26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468
- source file 6e0f6ffb9d5afebb249412e92cbc76583a17c1a24f6602016d86dfdfa94b5429
- raw PM CSV presentmon.csv 693,538 B; raw workload result 2,720 B; PM stderr 65 B.

Root-only Windows invocation after refreshing hashes & choosing fresh output roots:

$repo='D:\Claude\swiftright'
$src="$repo\factory\pipeline\sr0-display-selfjob-v4\strict-input-repair-v1"
$raw="$repo\factory\pipeline\sr0-display-selfjob-root-v4\observer-r6\actual-native-raw"
$build="$repo\probes\sr0-b\workload\out\tuple12-source-build-v1\observed-workload-r10-v7-r1\runs\build.json"
$inc="$repo\qualification\tuple12-takeover\root-process-validation-v9\observed-incremental-v9-r1\incremental.json"
$out="$repo\.factory-work\sr0-display-strict-input-repair-v1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-strict-input-repair-controls-v1.ps1" -MaterializerPath "$src\materialize-strict-inputs-v1.ps1" -AnalyzerPath "$src\analyze-workload-v3-strict-input-v1.py" -OutputPath "$repo\.factory-work\sr0-display-strict-input-repair-v1\controls.json"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\materialize-strict-inputs-v1.ps1" -RawRoot $raw -BuildPath $build -IncrementalPath $inc -OutputRoot $out -OutputPath "$out\materialize-receipt.json"
py -3 "$src\analyze-workload-v3-strict-input-v1.py" --os windows --root $out --out "$out\strict-report" --expect-runs 1 --expect-scale 2.5

Expected report may clear input-presence refusals only. It must retain original
display/capture findings: 2,268 measured presents vs ~3,600 expected, 110 displayed,
30 Hz refresh, dropped presents, latency failures, & W7 receipt values. Any
missing/changed source hash, CSV PID/QPC/display field, or timing threshold stays
held. No parity or qualification claim follows input repair.

## Windows-local Python materializer

`materialize-windows-inputs-v1.py` is bounded Python materialization for archived Windows raw evidence on this Mac checkout. It binds only explicit archived raw files, build receipt, & three-edit incremental receipt; it does not infer Mac layout, launch Windows work, or alter raw bytes. Derived `presentmon.console.txt`, `build.json`, & `incremental.json` remain held for strict analysis.

Known local Windows inputs:

- raw: `factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/actual-native-raw`
- build: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json`
- incremental: `qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/incremental.json`

Root-only local invocation:

    python3 factory/pipeline/sr0-display-selfjob-v4/strict-input-repair-v1/materialize-windows-inputs-v1.py --raw-root factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/actual-native-raw --build-path probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json --incremental-path qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/incremental.json --output-root .factory-work/sr0-display-strict-input-repair-windows-v1 --receipt .factory-work/sr0-display-strict-input-repair-windows-v1/materialize-receipt.json
    python3 factory/pipeline/sr0-display-selfjob-v4/strict-input-repair-v1/analyze-workload-v3-strict-input-v1.py --os windows --root .factory-work/sr0-display-strict-input-repair-windows-v1 --out .factory-work/sr0-display-strict-input-repair-windows-v1/strict-report --expect-runs 1 --expect-scale 2.5

This route is local raw-evidence materialization only. Strict display, capture, timing, & incremental findings remain held; no parity claim follows derived namespace.


## Local Mac archive materializer

`materialize-mac-archive-v1.py` is bounded Python equivalent for local Mac archives. It copies every regular raw file under 64 MiB with 128 MiB total, preserves relative paths & hashes, binds explicit release build-mac receipt, & records absent incremental proof as held. It does not map F1/F2 files into workload-analysis-v3 runs.

Known local inputs:

- raw: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/actual-mac20`
- build: `probes/sr0-b/workload/out-mac/build-mac.json`
- incremental: no local Mac receipt found; omit flag, W7 stays held.

Root-only local invocation:

    python3 factory/pipeline/sr0-display-selfjob-v4/strict-input-repair-v1/materialize-mac-archive-v1.py --raw-root probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/actual-mac20 --build-path probes/sr0-b/workload/out-mac/build-mac.json --output-root .factory-work/sr0-display-mac-strict-input-repair-v1 --receipt .factory-work/sr0-display-mac-strict-input-repair-v1/materialize-receipt.json

Receipt status remains materialized-held; no strict metric or parity claim follows raw archival copy.
