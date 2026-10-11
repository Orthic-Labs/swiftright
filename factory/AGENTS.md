# Factory workspace hygiene

Keep disposable runtime, host builds, staging & scratch inside ignored `.factory-work/` beneath SwiftRight checkout. Use rolling `runtime-stage` & `hosts` directories; never create `D:\Claude\factory-swiftright-*` siblings.

Mac fresh native binaries remain an exception required by capture policy: build & run only from internal-disk scratch, never `/Volumes/D`; retain required receipts before cleaning owned scratch. Never trigger permission prompts.

Before reusing or moving staging, confirm no owned process or running task needs it. Archive required evidence & hashes into factory evidence packets before retiring staging. Preserve frozen receipts; change prospective bindings in fresh packets.

Clean owned local scratch after every completed or aborted job. Never delete Dell files over SSH; move retired material into `D:\Claude\_factory-old-DELETE-ME` for Adrian to remove. Keep no retired build trees in active workspace.

Before reporting completion, verify active staging is ignored by Git & no owned staging remains outside checkout. Report cleanup completion separately from factory completion.

# Local resource limits

Never search for hashes by recursively reading every repo file. Resolve paths from manifests or use `rg --files` with an explicit source scope first. Exclude VM disks, `.tart`, `.work`, `.factory-work`, `.build`, `target`, `.venv`, `node_modules` & `.git` from source discovery.

Hash explicit files with `factory/tools/hash-explicit-files.py`: streaming 1 MiB chunks, maximum 64 MiB per file, 256 files, 256 MiB total & 60 seconds. Larger evidence requires a separately scoped streaming operation with a stated byte/time budget; never `read_bytes()` unknown files or build an in-memory archive. Check size before opening files.

Preserve every `exec_command` session ID. A yielded process is still running: supervise it to completion or terminate that owned job before ending its subtask. Root must reconcile outstanding sessions before accepting an agent's completion.
