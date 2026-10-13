# SR0 r11 source-only next-run stage

This packet materializes fresh r11 paths from explicit repository sources. It performs no process launch, scheduler action, lock mutation, compiler action, or qualification claim. Existing r10c raw evidence stays immutable.

`make_r11_stage.py` rejects symlinks, broad discovery, stale stage roots, source files over 64MiB, aggregate source bytes over 128MiB, wrong drain-control receipt kind/status, or nativeQualificationClaim=true. It copies 29 pinned source/control rows, including NEW collector-v8 predicate controls, verifies bytes/SHA after copy, verifies 3 explicit external binary rows (32-row closure), then writes `source-input-rows.json`, fresh plan JSON, & one-shot manifest. Workload/renderer/PresentMon binaries are never copied; exact paths, byte counts, & hashes are CLI-bound & verified.

Fresh candidate source pins:

- collector `a060ac5763c5de27cb6b8213c34c0d2cb3ecca904e3cc51d8cccf0dbada6f31a`
- identity helper `4e7af8708f78b1613196cc710c6cd7222f9a0485984326bd2e390df422a2d9ad`
- launcher worker `efcdce28ed817125187688d8c72466567408ede500fab5dd80b3b7afaad699aa`
- admitted r10 controls `e409a156ce7e536005ac589c7d56a7f76242899d5e1fe19c75f77d64b3fe30d2`
- r11 source-control runner `1040943b66b557d31b090be3e799d0477ee26bd25d99a94ac7b45e6d0950d0f0`
- r11 stage generator `bd4d2de977540b7471bd9cd9f7583d730aef5aa8234f4580dbcc965bf9742744`
- r11 source preflight `6cf114777e3dae31546beb4bd19fdd88418e8b1a5008087629511ba768c88c83`
- r11 integrated observer `0fae637711a3c0d2d3b0881105be5f0a70dc5ba964f690e64a66b91151d87b16`
- r11 collector controls `5602deb19fdf40d09ea9067eace50cbee1308aa9fd79ac99e80dfbb7b4a14de0`
- Mac source packer `74ad62e521130c85dc9cd4f61a5197b9de84e4d4bfb5097bf1f029f3d246029c`
- Windows ZIP materializer `8bb29319f8976b278c099e261109d78d893467039e6fcd76acb8fd5a22687085`

## Mac bounded source pack

Mac pack keeps 29 explicit source/control files in ZIP, records three original Windows binary rows from immutable r10 plan, & performs no Windows path resolution. It is archival input for Windows materialization; it does not claim native readiness.

```bash
python3 ./factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/next-run-stage-v1/pack_r11_sources.py \
  --repository-root /Volumes/D/claude/swiftright \
  --stage-definition /Volumes/D/claude/swiftright/factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/next-run-stage-v1/make_r11_stage.py \
  --source-plan /Volumes/D/claude/swiftright/factory/pipeline/sr0-display-selfjob-root-v4/actual-native-r10c/control/plan.json \
  --output-zip /Volumes/D/claude/swiftright/.factory-work/sr0-display-selfjob-v4/r11-source.zip \
  --metadata-out /Volumes/D/claude/swiftright/.factory-work/sr0-display-selfjob-v4/r11-source-pack.json
```

ZIP metadata preserves Windows operational paths, bytes, & SHA256; Windows materialization must bind those rows to explicit operational binary paths before staging.

## Windows ZIP materializer (no Python dependency)

`install_r11_sources.ps1` consumes Mac ZIP+metadata, verifies 29 source rows & original 3 binary rows, extracts fresh stage paths, AST-parses every staged PowerShell source, writes r10-compatible 32-row plan/manifest, & keeps `nativeActions=0`/`lockActions=0`. Add `-RunControls` only when root is ready to execute staged collector predicate, drain controls, & source preflight.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\install_r11_sources.ps1 `
  -ZipPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\r11-source.zip `
  -MetadataPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\r11-source-pack.json `
  -ControlsReceiptPath D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r10\drain-controls-r10.json `
  -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11 `
  -FactoryRoot D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11 `
  -ControlRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\control-root `
  -ControlReceiptRoot D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11 `
  -PlanPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-run-plan-r11.json `
  -ManifestPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-shot-manifest-r11.json `
  -RunRoot D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\run `
  -Base D:\Claude\swiftright\.work\sr0-r12-workload-v1 `
  -LockPath D:\Claude\desktop.lock `
  -WorkloadExe D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe `
  -RendererDll D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\swiftright_render.dll `
  -PresentMonExe D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe `
  -RunControls
```

## Root-owned Windows invocation

Use fresh empty paths under ignored `.factory-work`:

```powershell
python.exe .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\make_r11_stage.py `
  --repository-root D:\Claude\swiftright `
  --stage-root D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11 `
  --factory-root D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11 `
  --control-root D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\control-root `
  --control-receipt-root D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11 `
  --controls-receipt D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r10\drain-controls-r10.json `
  --plan-out D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-run-plan-r11.json `
  --manifest-out D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-shot-manifest-r11.json `
  --run-root D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\run `
  --workload-exe D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe `
  --workload-exe-bytes 5233152 `
  --workload-exe-sha256 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c `
  --renderer-dll D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\swiftright_render.dll `
  --renderer-dll-bytes 11887616 `
  --renderer-dll-sha256 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  --presentmon-exe D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe `
  --presentmon-exe-bytes 980320 `
  --presentmon-exe-sha256 b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af
```

Run staged source controls against NEW collector/identity pins before native launch. Runner executes production collector forced-stop predicate controls, then existing bounded drain controls; it emits separate `collector-controls-r11.json` beside main receipt.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\run-source-controls-r11.ps1 `
  -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11 `
  -PlanPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-run-plan-r11.json `
  -OutputPath D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\drain-controls-r11.json
```

Then run source-only preflight, producing fresh receipt:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\preflight-r11.ps1 `
  -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11 `
  -PlanPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-run-plan-r11.json `
  -ManifestPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-shot-manifest-r11.json `
  -ControlsReceiptPath D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\drain-controls-r11.json `
  -ReceiptPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\source-preflight-r11.json
```

Preflight output is source admission only: `nativeActions=0`, `nativeQualificationClaim=false`. Root must bind observer/transport receipt paths to r11 plan, preserve 900s/1s, 1GiB flags512, NoActivate, NoResources, one run, 200 rows, key rate10, & require explicit child receipt status plus exit identity before any native scheduling.

## Root-owned observer entry

After staging, root supplies generated plan, controls, transport, & plan/preflight hashes to `observer-source-r11.ps1`. Entry rechecks 32 source rows, all binary pins, AST preflight, r11 controls receipt, NoActivate, NoResources, 1GiB flags512, retained schedule handle, child exit identity, stream seals, coordinator/collector release proof, scheduler terminal state, & transport self-only cleanup. It emits only `nativeQualificationClaim=false`; any failed child or missing proof remains held.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\observer-source-r11.ps1 `
  -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11 `
  -PlanPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r11\one-run-plan-r11.json `
  -ExpectedPlanSha256 <generated-plan-sha256> `
  -PreflightPath .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\next-run-stage-v1\preflight-r11.ps1 `
  -ExpectedPreflightSha256 eba6194f3137028030efa4926ad875d92c387664d82a5c6db2bcfee12228fe5b `
  -ControlsReceiptPath D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\drain-controls-r11.json `
  -ExpectedControlsReceiptSha256 <generated-controls-sha256> `
  -TransportHelperPath D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs `
  -TransportHelperSha256 <admitted-transport-helper-sha256> `
  -OutputPath D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r11\observer-r11.json
```
