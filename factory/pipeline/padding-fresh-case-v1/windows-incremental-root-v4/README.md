# Padding cached incremental Windows compiler v4

Source-only successor of root-v3. It keeps compile-only/nativeActions=0, verifies fresh & donor lineage, exact 13 source rows, bridge rows, & every row in fresh `runtime-source-tree.json` against actual `runtimePackagePath`. Fresh plan must carry explicit `runtimeSourceTreePath`; implicit locations are rejected. Runtime tree file hash must equal both plan tree-hash fields, & every listed row is hashed under actual `runtimePackagePath`.

Fresh Windows host hash is the measured 64-hex value `3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a`. Cached compiler argv derives from donor argv by appending `--jobs 1`; donor argv is checked for absence of `-j`, `--jobs`, & `-Xswiftc -num-threads`. Fresh metadata requires `compileRequest.maxParallelJobs=1` & `maxFrontendThreadsObserved=null`; no frontend override is inserted. Runtime tree, source, host, case, tuple, & donor receipt faults are rejected before compiler admission.

Final cleanup retains original compiler handle, records native wait/GetExitCode, drains bounded streams, polls job active count until zero under 15 seconds before closing job handle, & preserves `cleanupError` when zero cannot be proven. Failed compile receipts stay failed.

Root runs controls before any compile action. Preflight uses `-PreflightOnly`; final remains compile-only until separate native admission:

```powershell
& .\test-padding-incremental-controls-v3.ps1 `
  -BuilderPath .\build-padding-incremental-v3.ps1 `
  -FreshPlanPath <fresh-plan> -FreshInputRoot <fresh-input-root> `
  -OperationalPackage <donor-package> -OperationalScratch <donor-scratch> `
  -OperationalPlanPath <donor-plan> -OperationalReceiptPath <donor-receipt> `
  -CompilerPath <swift.exe> -RendererPath <renderer.dll> `
  -JobHelperPath <Sr0OwnedJobProcess.cs> -BridgeRoot <bridge-root> `
  -OperationalExpectedOutputPath <donor-cache-exe> -ControlRoot <fresh-control-root>
```

Then root invokes `build-padding-incremental-v3.ps1` with same explicit arguments, measured fresh plan SHA, `-Phase preflight -PreflightOnly`. Final compile invocation is separately controlled & writes fresh output outside donor package/cache. Packet makes no native, lock, or parity claim.
