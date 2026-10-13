# Tuple12 workload controls v6

Source-only successor over v5. Root owns parser, build, native execution, and lock effects.

v6 retains signed kernel/.NET exit values plus raw DWORD values for PresentMon, workers, and samplers. PresentMon forced-stop path stops exact owned ETW session, polls `logman query` until DataCollectorSetNotFound, then records `session_absent=true`; PM terminal proof stays separate from session absence. Any raw sentinel `259`, signed mismatch, missing handle, or undrained stream fails cleanup proof.

Semantic admission requires exactly three valid runs. Every run must record `--sr0-noactivate`, guarded startup, `HWND_BOTTOM`/`SWP_NOACTIVATE`, `background_noactivate=PASS`, `WORKLOAD-WIN-DONE`, and `aborted=false`. Cleanup proof remains independent, so failed semantic runs can release lock only after exact started-handle/session/task proofs.

Pinned base is `0e201571e4320a3b6ccce14313fd2ad67e523904`; Workload EXE is `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`; renderer is `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
