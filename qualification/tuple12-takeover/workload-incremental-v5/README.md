# Tuple12 UI-only incremental v5

Source-only candidate for root-owned Dell execution. It measures exactly three
UI-only edits against sealed WorkloadWin release metadata. Shared
`shared/Sr0OwnedJobProcess.cs` owns exact x64 structs, redirected STARTUPINFO,
quoted argv0, suspended CreateProcess, assignment-enforced ResumeThread, job
memory/kill-on-close flags, retained handles, & active-count queries. Job memory,
kernel terminal state, bounded drains, active-process count, Rust shim count,
source restoration, & artifact restoration are receipted. It does not touch
desktop lock, launch GUI, send input, sign, or perform final restored-source build.

## Sealed inputs

- Source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- Build receipt: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/build-r1-receipt.json`
- Build receipt SHA-256: `14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579`
- Compiled manifest: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-build-r1/compiled-source-manifest.json`
- Source manifest SHA-256: `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`
- Plan manifest SHA-256: `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`
- WorkloadWin SHA-256: `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`
- Renderer SHA-256: `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`
- Compiled manifest: `files` length 54, `sourceFiles` count 42, `patchesApplied=3`,
  `guardImport=SwiftRightBridge`, & `qualification=hold-build-native`.

Deriver requires exact receipt/manifest joins, release argv
`build --jobs 1 -c release --product WorkloadWin`, `manifestOK=true`, verifier
exit 0, `nativeLaunches=0`, `lockActions=0`, & `qualification=hold-native`.

## Root-owned Dell commands

Run after parser/typecheck review, in fresh stage namespace:

```powershell
$Repo = 'D:\Claude\swiftright'
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Receipt = Join-Path $Stage 'build-r1-receipt.json'
$Manifest = Join-Path $Stage 'compiled-source-manifest.json'
$Metadata = Join-Path $Stage 'release-build-metadata-v5.json'
$Derive = Join-Path $Repo 'qualification\tuple12-takeover\workload-incremental-v5\derive-release-metadata.ps1'
$Adapter = Join-Path $Repo 'qualification\tuple12-takeover\workload-incremental-v5\build-incremental-tuple12.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Derive -StageRoot $Stage -Receipt $Receipt -CompiledManifest $Manifest -Out $Metadata
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Adapter -StageRoot $Stage -SourceRoot (Join-Path $Stage 'src') -BuildMetadata $Metadata -Edits 3
```

Receipt must report `kind=sr0-tuple12-ui-only-incremental-v5`, three terminal
trials, `rust_invocations_total=0`, exact shim counts, `memory_cap_bytes=1073741824`,
`memory_limit_kind=job-memory`, `job_active_readable=true`,
`job_active_processes=0`, one-second kernel polling, bounded logs, original
kernel handle retained, job assignment before resume, drained stdout/stderr,
`source_restored=true`, `hashes_identical=true`,
`final_noop_identity_check=false`, & `artifact_restoration_only=true`.

`owned_descendants` is emitted only from readable job active-count zero proof.
Any launch, timeout, output-cap, failed drain, unreadable active count, or
nonzero active count fails closed & terminates exact owned job before cleanup.

## Source controls

`test_tuple12_workload_incremental_v5_controls.py` is source-only. Root must run
it through repository supervisor before any Dell execution. It must exercise
positive lifecycle, job-memory flag, suspended assignment order, active-count
gate, 32 MiB artifact bound, timeout/drain faults, signed-max resume guard, & v5 receipt kind.

`job-controls-v2.ps1` is root-owned Windows headless lifecycle control using
same shared helper. Run positive, descendant, timeout, output-cap, & wrong-memory
modes, then each refusal mode in fresh process namespaces:

```powershell
$out = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1\control-out'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode positive
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode spawned-descendant
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode timeout
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode output-cap
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode wrong-memory-flag
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode resume-before-assignment
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\job-controls-v2.ps1 -OutRoot $out -Mode drop-active-query
```

Positive & `wrong-memory-flag` must exit 0 with explicit PASS lines. Resume-order
& active-query omission faults must exit nonzero after exact owned child cleanup.

No compiler, native run, signing, lock, or final no-op build has been performed
for v5 in current source lane.
