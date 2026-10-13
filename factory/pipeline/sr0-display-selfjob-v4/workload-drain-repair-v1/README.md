# Workload stdout drain repair v1

Factory-only prospective packet. Frozen `qualification/tuple12-takeover/workload-controls-v8/task-workload.ps1`, raw receipts, & strict parser remain unchanged.

## Diagnosis

Failed raw evidence:

`factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/actual-native-raw/result-workload.txt`

- nested WorkloadWin exit identity is valid: `exit=0 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=0 dotnet_exit=0`;
- `stream_drains ... worker_stdout=0 worker_stderr=1`;
- nested `r1/stdout.txt` is `<stdout-drain-timeout>`; nested `r1/stderr.txt` contains renderer shutdown evidence;
- `run_state ... valid=0 reason=stream-drain-timeout`, `runs_valid=0 of 1`.

Prior same-executable evidence at `factory/pipeline/sr0-display-selfjob-root-v4/observer-r6/actual-native-raw/` has `worker_stdout=1`, `worker_stderr=1`, `run_state valid=1`, & `runs_valid=1 of 1`. This isolates issue to nondeterministic pipe completion or wait ordering, while archived v5 remains genuinely held.

Frozen task polled `HasExited`, then waited `ReadToEndAsync` tasks. Repair adds explicit bounded `Process.WaitForExit(Int32)` synchronization before stream waits, with one monotonic deadline shared by terminal & both drains. It records process/stream fault state, & preserves exact four-field `stream_drains` line consumed by frozen parser. No stream is closed or discarded on timeout.

## Files

- `task-workload-drain-v1.ps1`: factory copy with pinned helper & repaired wait ordering.
- `workload-drain-helper-v1.ps1`: production `Complete-WorkloadDrainV1` function.
- `test-workload-drain-controls-v1.ps1`: invokes same production helper against real owned child cases exit 0, natural exit 17, delayed output, inherited-pipe delay, & nonterminal timeout.

## Root controls command

Refresh helper hash, then run on Windows:

```powershell
pwsh -NoProfile -File .\test-workload-drain-controls-v1.ps1 `
  -DrainHelperPath <staged>\workload-drain-helper-v1.ps1 `
  -DrainHelperSha256 <helper-sha256> `
  -OutputPath <fresh-output>\drain-controls.json `
  -WorkRoot <fresh-output>\drain-cases
```

Prospective scheduled task must pass `-DrainHelperPath` & `-DrainHelperSha256`; collector must preserve `stream_drains` parser shape. A successful helper control does not qualify archived v5; next native receipt must still show terminal, drained streams, task quiescence, & strict display evidence.
