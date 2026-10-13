# SR0 r13 Mac offline materializer v2

`materialize_r13_analysis_v2.py` is source-only & Mac-runnable. It admits exact entries from r13 `export-manifest.json`, rejects symlinks, verifies streamed bytes/SHA-256, caps each input at 16 MiB & selected archive bytes at 32 MiB, then copies parser inputs into fresh output. It derives `presentmon.console.txt` by exact `presentmon.stdout.txt` followed by `presentmon.stderr.txt`; inserted bytes are zero.

Archive lacks `build.json`. v2 therefore requires genuine repo `build.json` plus sealed build receipt. It validates receipt kind, exit 0, retained compiler handle, 54 source files, manifest proof, source manifest SHA, & WorkloadWin/renderer hashes, then adds only `configuration=release` to parser build input. No placeholder build data is emitted.

Root runs on Mac:

```sh
python3 -I factory/pipeline/sr0-display-selfjob-root-v4/sr0-r13-offline-analysis-v2/materialize_r13_analysis_v2.py \
  --archive-root factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/root-source-admission-r13-v1/actual-native-raw-r3 \
  --build-json probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json \
  --build-receipt probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/build-r1-receipt.json \
  --parser qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py \
  --output-root .factory-work/sr0-r13-offline-analysis-v2/materialized \
  --receipt .factory-work/sr0-r13-offline-analysis-v2/materializer-receipt.json
```

After materialization, root may run frozen analyzer explicitly:

```sh
python3 -I qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py \
  --os windows --root .factory-work/sr0-r13-offline-analysis-v2/materialized \
  --expect-runs 1 --expect-scale 2.5 \
  --out .factory-work/sr0-r13-offline-analysis-v2/report
```

Materialization emits `qualificationHeld=true`, `qualificationClaim=false`, `nativeActions=0`, & raw provenance. It does not reinterpret parser output or promote display qualification.
