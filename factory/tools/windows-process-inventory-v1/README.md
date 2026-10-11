# Windows process inventory v1

`windows_process_inventory.py` is stdlib-only Windows source. Default `--mode inventory` uses bounded Toolhelp32 snapshot, exact `powershell.exe` filter, `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|PROCESS_VM_READ)`, image path, UTC FILETIME start identity, ProcessCommandLineInformation class `60`, PSAPI memory counters, and flat scalar rows. Snapshot count counts every visited process & is capped at 2048; command-line reads at 64 KiB, JSON output at 2 MiB, and run deadline at 20 seconds. Full command-line SHA256 & encoded-command SHA256 are recorded before preview truncation.

Helper attempts self Job Object aggregate-memory limit 128 MiB with `JOB_OBJECT_LIMIT_JOB_MEMORY` (`0x200`); it never sets `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. Every opened handle closes in `finally`. Root must stage through supplied Python path & bounded supervisor.

`--mode cancel` is separate & fail-closed. Root supplies JSON kind `factory-owned-cancellation-v1` containing exact PID, `powershell.exe`, full image path, start FILETIME, full command-line SHA256, nonempty encoded-command SHA256 allowlist, `issuedAtUtc`, `expiresAtUtc`, & `allowTerminate:true`. Validity window is capped at 20 seconds. Helper opens original process handle with `SYNCHRONIZE`, rechecks path/start/full command hash/encoded-command hash, calls `TerminateProcess` only after identity match, then waits at most 10 seconds. PID/name-only termination is impossible.

Output path opens with exclusive create. Inventory never caches or mutates process state. No remote, GUI, compiler, or repository scan actions are included.

Root command shape: `C:\Python313\python.exe windows_process_inventory.py --mode inventory --output <fresh-json>`. Cancellation is a separate root-issued command: `C:\Python313\python.exe windows_process_inventory.py --mode cancel --control-json <exact-control.json> --output <fresh-receipt.json>`.
