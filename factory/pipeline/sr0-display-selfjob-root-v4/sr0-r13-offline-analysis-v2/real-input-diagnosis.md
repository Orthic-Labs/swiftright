# r13 offline input diagnosis

Sealed archive: `native-r10c-recovery-v1/root-source-admission-r13-v1/actual-native-raw-r3`. Its export manifest contains 65 files totaling 3,711,789 bytes. Required parser tables are present under `run/` & `run/r1/`; `run/presentmon.csv` is 926,320 bytes with SHA-256 `b080fcab80dd5b802a82e844cdd2a8e7c95c84a1e4b9efc9e6b72c4820a2f76e`. Workload result is 2,856 bytes with SHA-256 `a78ae9117969ca5a20f1524d66a6eb4167071006497156de68b011b7823f6f1d`.

Archive does not contain `run/build.json`. Genuine external inputs are explicit: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1/runs/build.json` & `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/build-r1-receipt.json`. Receipt SHA-256 is `14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579`; receipt proves exit 0, retained compiler handle, 54 verified source files, manifest OK, WorkloadWin SHA `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`, & renderer SHA `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`. v2 derives only missing release configuration field from this sealed receipt.

PresentMon console provenance is exact byte concatenation: `run/presentmon.stdout.txt` (20 bytes, SHA `0ef6a50a693d2959df6b8b95a74ba053e7a55794f0a6a7ba449aa378f5223b21`) then `run/presentmon.stderr.txt` (65 bytes, SHA `f522a4b28ee9eedb6189a4389f8fa839f193614ad098940bb23ae59e6d185b28`). No newline or other byte is inserted.

Frozen parser pin is `qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py`, SHA `35330066332c30e96d5e3a6232a0188889760ad73b7d4c04f1d9fb9f178b535a`. Raw archive remains immutable; strict display/capture qualification remains held regardless of offline parser result.
