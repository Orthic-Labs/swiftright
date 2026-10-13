# Tuple12 incremental source build v1

Source-only successor for genuine WorkloadWin UI-only incremental measurement. Root must parse this PowerShell on Dell before use; this packet performs no compiler, GUI, lock, native input, signing, or Git action.

## Source pins

- source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- materialized 54-file source manifest: `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`
- original build receipt: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/build-r1-receipt.json`, SHA-256 `14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579`
- original receipt argv: `build --jobs 1 -c release --product WorkloadWin --scratch-path D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch` plus ComCtl v6 manifest linker flags
- WorkloadWin: `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c` (5,233,152 bytes)
- renderer: `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2` (11,887,616 bytes)
- adapter: `build-incremental-tuple12.ps1`, SHA-256 `31fdb6ccaf066d53ff0d90ea78fe3657e1e5db274e56ba2ec1c6a820b83fdc28`
- release metadata derivation: `derive-release-metadata.ps1`, SHA-256 `345ad21ae9b5055eed479316d8dbb2fc0886dcb440c1ec6e99d2b535d54e201f`
- pure controls: `qualification/test_tuple12_workload_incremental_v1_controls.py`, SHA-256 `a23e3349961b4a74bca7fa3fce31015ac7ea404c8f2a2717bd4c73dfe4d717b5`

- read-only display context probe: `qualification/tuple12-takeover/workload-analysis-v3/display-context.ps1`, SHA-256 `7c47dcea44b88162ce4d1f0fab6deb72e42ccd0cde196f46b3fabdd50009c631`

`build.json` from original archive has no configuration field. `derive-release-metadata.ps1` emits `release-build-metadata.json` only after verifying sealed receipt argv contains `-c release`, exit 0, retained compiler handle, 54 verified source files, manifest verifier exit 0, native/lock counts 0, receipt SHA, executable/DLL hashes, & compiled-manifest bytes. `configuration=release` is receipt-derived metadata, not fabricated.

## Root Dell sequence

Root should stage receipt & compiled manifest into fresh tuple12 stage without rewriting archived inputs, then run:

```powershell
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Receipt = "$Stage\build-r1-receipt.json"
$Compiled = "$Stage\compiled-source-manifest.json"
$Metadata = "$Stage\release-build-metadata.json"
$Derive = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-incremental-v1\derive-release-metadata.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Derive `
  -StageRoot $Stage -Receipt $Receipt -CompiledManifest $Compiled -Out $Metadata
if ($LASTEXITCODE -ne 0) { throw "release metadata derivation failed: $LASTEXITCODE" }
```

The staged receipt & manifest must hash to the pins above. Adapter invocation then uses source under `$Stage\src`, build output paths from derived metadata, exact Swift 6.4 Asserts compiler path, `--jobs 1`, release product `WorkloadWin`, & fresh output namespace:

```powershell
$Source = "$Stage\src"
$Adapter = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-incremental-v1\build-incremental-tuple12.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Adapter `
  -StageRoot $Stage -SourceRoot $Source -BuildMetadata $Metadata -Edits 3 -EngineArtifacts @()
if ($LASTEXITCODE -ne 0) { throw "incremental build failed: $LASTEXITCODE" }
```

Adapter writes `$Stage\incremental.json` with three genuine source edits, one retained Swift process handle per build, kernel wait/GetExitCodeProcess proof, .NET exit proof, stdout/stderr drain proof, Rust shim invocation count, source restoration hash, artifact before/after hashes, & owned namespace fields. It restores source in `finally`, restores owned stage EXE/DLL bytes after each trial, performs final no-op identity check, & rejects preexisting receipt/output paths. It never deletes files, kills global processes, touches desktop lock, launches GUI, or sends input.

Expected receipt conditions: all three build exits `0`; kernel wait `0`; kernel exit `0`; .NET exit `0`; both streams drained each trial; `rust_invocations_total=0`; `source_restored=true`; `hashes_identical=true`; `builds_ok=true`; `desktop_lock_touched=false`; `gui_launched=false`; `native_input=false`. A failed condition is a hold, not a pass.

Pure controls, before root parse/build:

```sh
python3 qualification/test_tuple12_workload_incremental_v1_controls.py
```

The controls require positive handle/kernel/drain/source/artifact/namespace guards & reject seven mutations. They do not claim compiler or native success.
