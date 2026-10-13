# Tuple12 WorkloadWin incremental source-build recipe

Status: source-only recipe; root must run all Windows effects. It derives tuple12 incremental proof from the exact 54-file source-bound stage, then binds v8 workload controls & analyzer v3. It never edits renderer, runtime, bridge, frozen receipts, or prior stages.

## Pinned inputs

- source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- tuple12 source manifest: `qualification/tuple12-workload-source-manifest.json`, SHA-256 `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`
- materialized tuple12 source closure: 54 files, materialized manifest SHA-256 `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`
- stage: `D:\Claude\swiftright\.work\sr0-r12-workload-v1`
- WorkloadWin: `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`
- renderer: `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`
- existing incremental source reference: `probes/sr0-b/workload/scripts/build-incremental.ps1`, SHA-256 `e20ccf8202deb5276d131bb57451152508efd18ae22336a06de4413d08320ad2`
- v8 controls source pins: `qualification/tuple12-takeover/workload-controls-v8/source-pins.json`, SHA-256 `bf494d8d7ba96444041a95a6b39a675af18ed3889a85ad9ed59897d8699ebcdd`
- v8 runner: `qualification/tuple12-takeover/workload-controls-v8/run-workload.ps1`, SHA-256 `4fbb5774e8c62bee0ff387b2a5d1c537f7ea2b089676ce780435bf55afe8268d`
- v3 analyzer: `qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py`, SHA-256 `35330066332c30e96d5e3a6232a0188889760ad73b7d4c04f1d9fb9f178b535a`
- strict assembler: `qualification/assemble-tuple12-workload-v1.py`, SHA-256 `434d45c28a8fb5714cc259662b05f165e8b7cba7e095f07467a3e36b7ba78afd`

## Stage preflight

Run in one root-owned Dell session after desktop/task quiescence. Fail closed if any check fails:

```powershell
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Source = "$Stage\src"
$Script = "$Source\probes\sr0-b\workload\scripts\build-incremental.ps1"
$Build = Get-Content -LiteralPath "$Stage\build.json" -Raw | ConvertFrom-Json
if ($Build.configuration -cne 'release') { throw 'tuple12 build.json must bind configuration=release' }
if ([string]$Build.exe_sha256 -cne '7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c') { throw 'WorkloadWin hash mismatch' }
if ([string]$Build.dll_sha256 -cne '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2') { throw 'renderer hash mismatch' }
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw 'stage incremental source missing' }
if ((Get-FileHash -LiteralPath $Script -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'e20ccf8202deb5276d131bb57451152508efd18ae22336a06de4413d08320ad2') { throw 'incremental source drift' }
```

The historical script has two tuple12 path assumptions: its default `Base` is `D:\Claude\sr0b-workload`, & it expects `Base\probes\...` while tuple12 source is under `Stage\src\probes\...`. Do not invoke it unchanged with tuple12 stage root. Root must use reviewed tuple12 adaptation with separate `$Stage` (metadata/output) & `$Source` (package working directory), or fail closed & prepare a new immutable source copy. No junction, symlink, or in-place protected artifact substitution is admitted.

## Required incremental invocation contract

The reviewed tuple12 adapter `qualification/tuple12-takeover/workload-incremental-v1/build-incremental-tuple12.ps1` (SHA-256 `31fdb6ccaf066d53ff0d90ea78fe3657e1e5db274e56ba2ec1c6a820b83fdc28`) retains existing script invariants: unique run directory, shim first on `PATH`, `RUSTC_WRAPPER` shim, three `WorkloadScreen.swift` marker edits restored in `finally`, pinned WorkloadWin copied back byte-identically when relink changes it, renderer hash before/after, every build exit recorded, & `incremental.json` written only after all trials. It must use:

```powershell
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Source = "$Stage\src"
$Incremental = "$Stage\incremental.json"
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-incremental-v1\build-incremental-tuple12.ps1" `
  -StageRoot $Stage -SourceRoot $Source -BuildMetadata "$Stage\release-build-metadata.json" -Edits 3 -EngineArtifacts @()
if ($LASTEXITCODE -ne 0) { throw "incremental qualification failed: $LASTEXITCODE" }
```

`build-incremental-tuple12.ps1` is now present as immutable source successor; root must not silently substitute old `build-incremental.ps1`. Release metadata must first be derived from sealed build receipt with `derive-release-metadata.ps1`; source pins are recorded in its README. Expected receipt `$Incremental` fields: `platform=windows`, `edits=3`, three trial exits 0, `rust_invocations_total=0`, `hashes_identical=true`, `builds_ok=true`, & `pinned_exe_sha256` equal to WorkloadWin hash. Renderer is prebuilt; `-EngineArtifacts @()` leaves no unbound engine artifact.

## Fresh workload binding

After release build metadata & incremental receipt are sealed, root must run v8 through coordinator v5 with explicit source roots. Use unique tag/output & noactivate path:

```powershell
$Base = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Controls = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-controls-v8'
$Analysis = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-analysis-v3'
$Coordinator = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-coordinator-v5\workload-coordinator.ps1'
$OutRoot = "$Base\out-v8"
$Tag = 'tuple12-r10-v8'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Coordinator `
  -Base $Base -ControlRoot $Controls -AnalysisRoot $Analysis -OutRoot $OutRoot `
  -ExpectExe 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c `
  -ExpectDll 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2 -Tag $Tag
if ($LASTEXITCODE -ne 0) { throw "workload coordinator failed: $LASTEXITCODE" }
```

Coordinator output is `$Base\runs\$Tag`; receipt is `$OutRoot\receipts\workload-$Tag.json`. It forwards `-Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate -LifecycleProof` to v8 runner.

Runner must write analyzer-required `presentmon.console.txt`, pass `$Base\incremental.json` explicitly, preserve raw CSV/meta/streams, & keep strict display, W2, W6, source, noactivate, lifecycle, & 3-run gates. The v3 analyzer calibrates from every captured present start; display-row eligibility remains separate. This repairs timestamp calibration without converting dropped rows into displayed evidence.

## Admission

Run strict assembler against fresh packet only:

```powershell
$Packet = "$Base\runs\$Tag"
$Receipt = "$OutRoot\receipts\workload-$Tag.json"
$Assembly = "$OutRoot\workload-$Tag-assembly.json"
& py -3.11 -I 'D:\Claude\swiftright\src\qualification\assemble-tuple12-workload-v1.py' `
  --root $Packet --receipt $Receipt --out $Assembly
if ($LASTEXITCODE -ne 0) { throw "workload assembly incomplete: $LASTEXITCODE" }
```

Assembler must see coordinator `status=passed`, exit 0, all lifecycle/cleanup/session proofs, release metadata, incremental receipt, exact EXE/DLL, analyzer `PASS` with no refusal reasons, three valid runs, & noactivate evidence. Existing v7 packet remains immutable & intentionally incomplete.
