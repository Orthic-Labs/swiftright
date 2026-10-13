# Count1 r3 execution overlay

Installer copies four pinned PowerShell files directly into Dell `D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\root-metadata-controls-v1\execute-r3\`:

- `coordinator-r3.ps1`
- `interactive-task-r3.ps1`
- `dispatch-r3.ps1`
- `capture-repeat-r3.ps1`

Each script keeps automatic `$PSScriptRoot` as overlay location, then derives explicit `$overlayRoot` & `$baseRoot = Join-Path $overlayRoot '..\\..'` for original capture-v3 dependencies. Count1 is sole accepted count. Coordinator chain is `coordinator-r3` → `interactive-task-r3` → `dispatch-r3` → `capture-repeat-r3`.

`test-execution-chain-admission.py` performs source-only headless admission against archived actual fixtures. It checks baseline, wrong manifest hash, wrong manifest byte count, chain edges, gate ordering, Count1 restrictions, metadata/guard/schema joins, & zero native/lock actions.
