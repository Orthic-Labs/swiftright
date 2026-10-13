# Tuple12 UI-only incremental v2

Source-only candidate for root-owned Dell execution. It measures three genuine
UI-only edits against sealed WorkloadWin release metadata, while Rust shim count,
compiler terminal state, owned descendants, stream drains, source restoration,
& artifact restoration remain independently receipted. It does not touch desktop
lock, launch GUI, send input, sign, or perform final restored-source build.

## Sealed inputs

- Source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- Build receipt: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/build-r1-receipt.json`
- Build receipt SHA-256: `14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579`
- Compiled manifest: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/compiled-source-manifest.json`
- Source manifest SHA-256: `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`
- Plan manifest SHA-256: `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`
- WorkloadWin SHA-256: `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`
- Renderer SHA-256: `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`
- Compiled manifest has `files` array length 54, `sourceFiles` count 42,
  `patchesApplied=3`, `guardImport=SwiftRightBridge`, & `qualification=hold-build-native`.

Deriver requires these exact joins, receipt `sourceFilesVerified=54`, release
argv `build --jobs 1 -c release --product WorkloadWin`, `manifestOK=true`,
manifest verifier exit 0, `nativeLaunches=0`, `lockActions=0`, & `qualification=hold-native`.
It accepts `sourceFiles` only as either integer or array, then validates count;
it never assumes shape without checking.

## Root-owned Dell commands

Run after parser/typecheck review, in fresh stage namespace:

```powershell
$Repo = 'D:\Claude\swiftright'
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Receipt = Join-Path $Stage 'build-r1-receipt.json'
$Manifest = Join-Path $Stage 'compiled-source-manifest.json'
$Metadata = Join-Path $Stage 'release-build-metadata-v2.json'
$Derive = Join-Path $Repo 'qualification\tuple12-takeover\workload-incremental-v2\derive-release-metadata.ps1'
$Adapter = Join-Path $Repo 'qualification\tuple12-takeover\workload-incremental-v2\build-incremental-tuple12.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Derive -StageRoot $Stage -Receipt $Receipt -CompiledManifest $Manifest -Out $Metadata
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Adapter -StageRoot $Stage -SourceRoot (Join-Path $Stage 'src') -BuildMetadata $Metadata -Edits 3
```

Adapter receipt must report `kind=sr0-tuple12-ui-only-incremental-v2`, three
terminal trials, `rust_invocations_total=0`, exact before/after/total shim line
counts, `memory_cap_bytes=1073741824`, one-second kernel polling, bounded output
logs, owned job descendants, drained stdout/stderr, `source_restored=true`,
`hashes_identical=true`, `final_noop_identity_check=false`, &
`artifact_restoration_only=true`. Artifact restoration identity is not proof of
a final restored-source compiler build; any gate requiring such build remains held.

## Source controls

`qualification/test_tuple12_workload_incremental_v2_controls.py` passed supervised
positive controls, owned no-op terminal/drain controls, count ordering, timeout
termination, & nine mutation faults. Controls run only through:

```sh
python3 factory/tools/supervise-job.py --seconds 30 --rss-mib 256 --out .factory-work/sr0-incremental-v2-controls-r4 -- python3 qualification/test_tuple12_workload_incremental_v2_controls.py
```

Current source pins:

- Adapter `bcd7a0ae2ef9e7a2983eb2158b8a4a2f27ae878819b8452af9de91318442e5ad`
- Deriver `c7945c1fc4e01f48ce65ce92a0bf5fda2373a5c6aa7e5bd27f1a54c93391d8c4`
- Controls `e7b3a4a2e0bffedad9a24d2f3822d05f2dde0daca00a1fefd11e2b21b0ef15b6`

No compiler, native run, signing, lock, or final no-op build has been performed
for v2 in current source lane.
