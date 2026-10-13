# SR0 r12 immutable admission/run manifest successor

r11 failed before workload launch because installer-created `manifest-r11.json` was reused by scheduler, whose `Write-AtomicJson` correctly rejected existing files. r12 keeps admission manifest immutable & creates distinct run manifest only after scheduler verifies every admission field against its requested paths, hashes, owner, workload settings, memory policy, & control receipt.

Files:

- `install_r12_sources.ps1`: bounded 29-source + 3-binary installer; writes r12 plan + immutable admission manifest; no native action.
- `preflight-r12.ps1`: validates admission/run path separation, 32-row closure, source hashes, controls, 900s/1s, 200 rows/10 Hz, 1 GiB/0x200/no-kill-on-close.
- `test-manifest-admission-controls-r12.ps1`: executes same admission predicate for positive input & 9 mutated rejection cases.
- `schedule-once-v8-admission.ps1`: verifies immutable admission SHA & every generated field, writes fresh run manifest, then schedules worker.
- `run-admission-r12.ps1`: bounded plan-to-scheduler adapter; no field guessing.

Root sequence:

```powershell
& .\install_r12_sources.ps1 -ZipPath <source-pack.zip> -MetadataPath <source-pack-metadata.json> -ControlsReceiptPath <existing-r10-controls.json> -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r12 -FactoryRoot D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r12 -ControlRoot <stage>\control-root -ControlReceiptRoot <factory> -PlanPath <stage>\one-run-plan-r12.json -ManifestPath <stage>\manifest-r12-admission.json -RunManifestPath <stage>\manifest-r12-run.json -RunRoot <factory>\run -Base D:\Claude\swiftright\.work\sr0-r12-workload-v1 -LockPath D:\Claude\desktop.lock -WorkloadExe <pinned WorkloadWin.exe> -RendererDll <pinned swiftright_render.dll> -PresentMonExe D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe -RunControls
& .\test-manifest-admission-controls-r12.ps1 -AdmissionManifestPath <stage>\manifest-r12-admission.json -ExpectedTaskName SR0-factory-display-selfjob-v7-root-r12 -ExpectedRunRoot <factory>\run -ControlRoot <fresh control root>
& .\preflight-r12.ps1 -StageRoot <stage> -PlanPath <stage>\one-run-plan-r12.json -AdmissionManifestPath <stage>\manifest-r12-admission.json -RunManifestPath <stage>\manifest-r12-run.json -ControlsReceiptPath <factory>\drain-controls-r11.json -ReceiptPath <stage>\source-preflight-r12.json
& .\run-admission-r12.ps1 -PlanPath <stage>\one-run-plan-r12.json -AdmissionManifestPath <stage>\manifest-r12-admission.json -RunManifestPath <stage>\manifest-r12-run.json -AdmissionManifestSha256 <sha256(manifest-r12-admission.json)> -SchedulePath <stage>\schedule-once-v8-admission.ps1
```

Pinned binaries remain WorkloadWin `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`, PresentMon `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`. No qualification or parity claim is emitted.
