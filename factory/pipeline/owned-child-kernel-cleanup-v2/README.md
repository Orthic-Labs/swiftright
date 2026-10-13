# Owned child kernel cleanup v2

Prospective source successor for fresh Text/Circle packets. Frozen r9 helper `a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7` remains unchanged.

`Invoke-FactoryOwnedCleanup` treats retained-handle `WaitForSingleObject` result as exit authority. Framework `HasExited` is diagnostic. With wait `258`, it queries PID/path/start through retained handle (`GetProcessId`, `QueryFullProcessImageNameW`, `GetProcessTimes`), compares UTC start ticks, requires caller-pinned 64-hex executable hash, then may terminate exact retained handle. It waits caller-supplied cleanup budget (default 5000 ms), validates `GetExitCodeProcess`, & reports `killed-owned-handle-after-phantom-exited` when cached `HasExited` was true. Any unknown wait, failed exit-code query, identity drift, path/reparse/hash drift, or timeout returns hold & never authorizes release.

Native capture budgets remain unchanged: renderer/window deadline 30 s, process exit 15 s, stream drain 5 s, outer lifecycle budgets supplied by caller. This helper never qualifies capture failure, changes lock/background guards, or releases desktop without existing outcome proof.

## Fresh overlay rebinding

`patch-overlay-helper-v2.py` accepts explicit donor overlay paths only. It refuses existing output, symlink/reparse components, traversal, changed files, oversized files, >256 overlay files, or >256 MiB staged bytes. It copies successor helper & rewrites only supplied old helper hash pins. It emits `overlay-rebind-manifest.json`; donor remains untouched. Root must stage copied helper & every listed overlay file into fresh Text/Circle namespace, then reseal source-inputs/integration bindings against emitted bytes before launch.

Example root-owned staging command (do not run in this source lane):

```text
factory/.venv/bin/python factory/pipeline/owned-child-kernel-cleanup-v2/patch-overlay-helper-v2.py --donor-root <fresh-donor> --output-root <fresh-output> --helper-source factory/pipeline/owned-child-kernel-cleanup-v2/cleanup-kernel-authority-v2.ps1 --old-helper-sha256 a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7 --overlay-file overlay/capture-text-single-v3.ps1 --overlay-file overlay/capture-text-count20-v1.ps1
```

`test-cleanup-kernel-authority-v2.ps1` exercises production function through injected wait/PID/exit/terminate providers: phantom `HasExited`, genuine kernel signal, wrong PID/start/path/hash, unknown wait, & failed exit-code query. Root must run via bounded supervisor & archive receipt before any native action.
