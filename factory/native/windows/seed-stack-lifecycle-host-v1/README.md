# Stack lifecycle diagnostic host v1

New package, compiler output & observation namespace. Original host/executable/witness remain immutable. Witness bytes & runtime/bridge/compiler/dependency bindings match frozen stack parent. Markers add UTC epoch seconds, monotonic GetTickCount64, PID & thread around callback teardown/release/shutdown, bridge.run entry/return, hook unhook, Swift actor scope defer/return & immediately before exit. Marker stdout flush can perturb timing; this executable supplies localization evidence only, never native parity/repetition proof.

Source verification: `python3 factory/native/windows/seed-stack-lifecycle-host-v1/adapt-host.py --verify`.
Windows compiler-only entry: `run-compile.ps1` after stage membership/hash verification & AST review. Existing build-v2 actual-control admission remains mandatory. Output: `package/build-lifecycle-v1-r1/observation.json` & `FactoryProbe.exe`. No executable launch in compiler driver.

Interpretation: callback-enter without callback-return narrows callback work; bridge-run-enter without bridge-run-return narrows bridge/renderer return; run-return without actor-return narrows host/bridge scope destruction; before-exit while retained process kernel is unsignalled narrows CRT/process exit after final host marker. Missing markers alone do not prove location: correlate marker flush, final raw stream completion & retained kernel receipt. Compare a fresh diagnostic capture with immutable v5 baseline under unchanged deadline & WM_CLOSE policy.
