Reader contract: `windows_exit_admission_issues(capture, reader) -> list[str]`.
Root F10 integration invokes verifier directly using its archive-owned reader;
caller-supplied `verified`, `pass`, `nativeParity` labels never bypass verification.

Capture `meta.conditions.windowsExitProof`:
```
{"version":1,"files":{"<role>":{"path":"<relative archive path>","hash":"sha256:<raw hash>"}}}
```
Exact roles: outcome, observation, owned, close, plan, compile, witness, exe,
renderer, runtimeReceipt, runtimeTree, stdout, stderr. Each path is unique,
normalized POSIX-relative, confined by verifier + archive reader. Reader returns
exact bytes; absent files raise OSError/KeyError. No live runtime/SDK reads.

Additional required archived bytes:
- `host/<path>` for every pinned `plan.sourceBindings` member; package/main/Witness required.
- `runtime/<path>` for every pinned runtimeTree member; package/runtime source required.
- `tool/compiler.bin`, bound to compile + plan compiler hashes.

Raw observation may be original array or object; exactly one exact-int index
matches capture run. Row must contain case/source/exe/renderer/runtime identities,
strict hostValid/exitCode, ownedIdentity, HWND, + raw files bindings for
outcome/owned/close/stdout/stderr. No raw object or identity is reconstructed.
Compile receipt binds plan/source/exe/renderer/runtime/tool, exact-int PID/exit,
argv/cwd, ordered timestamps, successful bounded process outcome. Windows
7-digit timestamps retain integer100ns ordering.

Outcome must contain no primary/stream error, exact owned PID/path/start matching
row + WM_CLOSE target, retained-kernel-handle wait0 signal certification, exactly
two completed/sealed/closed streams + byte hashes. Successful cleanup following
primary deadline still rejects. Legacy HasExited-only remains observational;
absent proof blocks qualification. Existing raw archives remain unchanged.

Guard success is structural exit-origin admission only. F10 still requires
independent semantic/timing/closure/config/other origin checks. Synthetic fixture
control pass is NOT native qualification; all fixture bytes carry test-only scope.
