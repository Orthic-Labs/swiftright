# Tuple12 workload controls v5

Source-only successor over v4. Root owns parser, build, & native execution.

Evidence-driven fixes:

- `run-workload.ps1` preserves signed PresentMon `ExitCode` (`-1` stays `-1` instead of DWORD `4294967295`), compares signed kernel/.NET values, & records `stop=natural|forced-owned`. Forced stop remains explicit owned-process cleanup proof with retained handle & drained streams.
- `task-workload.ps1` accepts `-NoActivate`, requires renderer `--sr0-noactivate` before process launch, applies `HWND_BOTTOM` plus `SWP_NOACTIVATE`, avoids foreground acquisition on this lane, & records worker handle on start line so coordinator can account every started worker.
- Sampler handle, native terminal proof, & both sampler stream drains remain required.

Pinned source base remains `0e201571e4320a3b6ccce14313fd2ad67e523904`; Workload EXE `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`; renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
