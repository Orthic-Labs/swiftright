# Tuple12 Windows incremental adapter v8

Source-only successor to v7. It preserves v6 helper, 54-file manifest, 42 source-file count, three edits, 1 GiB job, 8 MiB streams, 900-second deadline, reader-before-assignment/resume order, bounded active-process proof, & artifact-restoration-only semantics. Adapter PATH order is run shim, sealed compiler bin, Swift Runtimes 6.4.0 `usr\bin`, then inherited PATH; `swiftCore.dll` is bounded & recorded by hash.

Each edit catches trial failure, performs bounded termination/drain/active proof, writes `trials/edit-N.failure.json` with kernel wait/exit, stream, active, cleanup, handle, timeout/output, & held-mutation fields, then rethrows. Restoration remains gated by all-job quiescence. v7 remains unchanged.

Manifest environment diagnostic is bounded & read-only. Root runs it on Windows after parser review:

```powershell
$root = 'D:\Claude\swiftright'
$out = Join-Path $root '.work\sr0-r12-manifest-diagnostic-v8'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `
  (Join-Path $root 'qualification\tuple12-takeover\workload-incremental-v8\diagnose-manifest.ps1') `
  -PackagePath 'D:\Claude\swiftright\.work\sr0-r12-workload-v1\probes\sr0-b\workload' `
  -SwiftPath 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  -OutRoot $out
```

Diagnostic prepends sealed compiler & runtime bins to inherited `PATH`, records explicit environment fields, probes `dump-package` & JSON `show-dependencies`, and writes per-probe output/receipt plus `manifest-diagnostic.json`. Each probe uses v6 owned helper with suspended create, readers before assignment/resume, 1 GiB job, 8 MiB stream cap, 120-second bound, retained original handle, bounded drain, & active-process zero proof. It never edits source or artifacts.
