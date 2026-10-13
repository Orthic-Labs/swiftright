# SR1 r3 execution overlay review

Read-only source review of `factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r3`, packet manifest SHA-256 `ce539c088668b1b49ae5daa938d7df5a881f515e321d4b038172bf60cdbbf7b2`.

## PASS_SOURCE_ONLY_PENDING_DELL

- Four pinned files resolve `$baseRoot` from overlay `..\..`; resulting root is capture-v3 root. Chain is explicit: coordinator → interactive task → dispatch → capture repeat.
- `test-execution-chain-admission.py` passed: baseline accepted; wrong manifest hash & byte faults rejected; Count1 only; manifest gates precede lock/native entry; native/lock actions 0. Fixture joins use issued metadata `26ab10c1...`, guard `79845ab4...`, tuple/schema joins from archived r1.
- Pinned source hashes: coordinator `c8a58f258f6a9961bc670027bbcc5e74fcb61920096b3bf8c43d611f286f4485`, interactive `fd5bfa4d4c3803a4f54dbc597992618b6fad044d94cc7a126f52f7d9de3a7098`, dispatch `69f4956fd746c1c2ca6864d38476f1350bd49ce41aad53efbdeeb3535fbc5c4f`, capture `915d3e007e1cf6c89d059380a5956133701abc181ad021ec99c6c80d7fdcb7dc`.
- Source lineage binds exact case, source hash, package, compile receipt, executable, runtime commit/tree, renderer, bridge inputs, candidate tuple, source refs, issued metadata, & fresh run root before child launch. Mac absolute `sourceArchiveRef` remains Mac-owned receipt input; no Windows existence check is required.
- Background guard remains fail-closed: `UseShellExecute=false`, `CreateNoWindow=true`, thread-CBT activation marker, foreground abort, same process/HWND/path/start identity, retained-handle cleanup & raw stream sealing.

## Separate source lane

- New SR0 `StartupGuard.swift` compile was red only because `SwiftRightBridge` import was missing; source fix is separate from this prebuilt factory host lane. New overlay manifest r2 carries that fix.
- Capture source records ordinary `$p.ExitCode` for host-valid observation after `WaitForExit`; final exit certificate uses retained process handle captured immediately after `Process.Start`, with kernel wait/GetExitCode proof. No r3 exit-code patch is required.
- `dispatch-r3.ps1:40` writes `dispatch-<Count>.json` into base capture root with `Set-Content`; failed r2 produced no file, & root fresh-output preflight prevents collision. Keep as source hygiene observation, no current qualification hold.
- Factory host prebuilt `3d3171b6...` carries full-lifetime CBT activation-veto proof; r3 retains same-process/HWND/path/start identity, foreground abort, retained-handle cleanup, & raw stream sealing.
