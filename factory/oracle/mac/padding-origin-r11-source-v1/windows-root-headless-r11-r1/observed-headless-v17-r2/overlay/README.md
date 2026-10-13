# Fresh r11 coordinator v17

v17 is immutable successor to v16. It preserves explicit `AdmissionRoot`, self-job memory guard, & v16 source joins. Capture now dot-sources `worker-output-preflight-v17.ps1` & validates every planned `native-01` through `native-20\uia-worker` path before preflight returns, output creation, renderer launch, lock use, or worker invocation.

Run namespace must be fresh & under `D:\Claude\swiftright\factory\native\windows\`; root uses NamespaceRoot `D:\Claude\swiftright\factory\native\windows\.work\windows-replay-r11\r17` & RunRoot below it. v16 source/metadata remain frozen. Root stages v17 scripts under one overlay & passes repository AdmissionRoot, ProducerRoot, ControlRoot, RunRoot, OutputRoot, and exact measured receipt pins. Native execution remains pending root review.

Stage `Sr0OwnedJobProcess-v15.cs` beside v17 interactive script from frozen v15 hash in source map; this preserves 1 GiB self-job guard.

Headless admission command is coordinator `-PreflightOnly`; capture may also be invoked directly with `-PreflightOnly` after passing `-AdmissionRoot`. Both paths require `first-proof-fresh-r11-v17.ps1 -UiaSchemaPath <ProducerRoot>\dependencies\uia-worker\schema.ps1`, verify schema hash, pass `-AdmissionRoot <repository-root>` into first-proof, & validate planned worker paths. `test-worker-output-preflight-v17.ps1 -ControlRoot <fresh-control-root>` exercises positive, wrong-namespace, & existing-worker faults; receipt is source-only.

Root control command:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\test-worker-output-preflight-v17.ps1 -ControlRoot D:\Claude\swiftright\factory\native\windows\.work\worker-output-preflight-controls-r17
```
