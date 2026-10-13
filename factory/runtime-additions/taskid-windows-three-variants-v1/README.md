# Windows TaskID three-variant diagnostic

Deferred direct-SSH experiment for one focused release test per variant:

- `original`: frozen source, 120 ms `settle`, original assertions.
- `retained`: retains `Graph` across await, same 120 ms `settle`.
- `terminal`: retains `Graph` & waits terminal commit event before same settle.

Task body remains 40 ms. No runtime edits, full suite, GUI, Pulse receipt, retry, or Dell deletion. `dispatch.py preflight` verifies frozen source manifest & all 45 package files per variant locally, without SSH/compiler/test execution. `upload` requires `TASKID_ALLOW_UPLOAD=1` & creates fresh `D:\Claude\factory-swiftright-taskid-three-input-20261011`. `run` remains blocked until `TASKID_RUN_TOKEN=RUN-NOW-PERFORMANCE-PAIR-COMPLETE`; remote script then runs each exact filter once under fresh `D:\Claude\factory-swiftright-taskid-three-run-20261011`.

Remote receipts bind source bytes/times before & after, Swift/SwiftC path/hash, actual owned process argv/cwd/start/end/exit, CIM process tree, stdout/stderr hashes/times, & discovered test executables. Original outcome remains raw baseline evidence; no pass is called fix.
