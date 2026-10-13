# Workload r10 v4 diagnosis

Observed packet: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v4-r1`.

`result-workload.txt` has all 3 workers terminal 0, all 3 samplers terminal 0, all four streams drained per run, `runs_valid=3 of 3`. Worker `pid` lines omitted handle; handle appears only on later `pid_exit`, so coordinator v3 counted `startedWorkers=0`, `startedSamplers=3`, & selected `malformed-result` cleanup mode. v5 task emits worker handle on start line.

Each run records `background_noactivate=not-requested`. v4 task had no `NoActivate` parameter, so forwarded switch was not bound; v5 declares switch, requires `--sr0-noactivate` before child launch, & keeps targeted branch on `HWND_BOTTOM` plus `SWP_NOACTIVATE` without foreground acquisition.

PresentMon stopped after owned 60-second wait then owned forced stop. Its signed `.NET ExitCode` was `-1`; v4 cast it to `uint32`, producing `4294967295`, then omitted `.NET` value from terminal log after conversion failure. v5 preserves signed exit, records `stop=forced-owned`, compares signed kernel/.NET/exit values, & retains stream drains.

Evidence hashes:

- result: `e82d7df044ae2ad96fb837365d6b3c8eb53109f3386b8e9e90db06682afdd239`
- orchestrator log: `c6762e7fe34e4ed5d9eb1e3bcdfea48130c3cca2efa99bee251f653dc0289013`
- PresentMon session: `b16ea344f1ddd2a5641fc3f821dd8f26409f8f75d37f0bd63248c33d56ff9e5e`
- coordinator receipt: `e43070eefc26b25969a172d3c50eb1742355504681a930983e8cdc43c5022a34`
