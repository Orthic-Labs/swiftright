# SR0 r12 parser repair v2

Actual `actual-run-raw-r3/result-workload.txt` contains one `worker`, one `pid_exit`, one `stream_drains`, `valid=1`, `task_quiescent=1`, & workload exit identity 0. Redirected workload stdout/stderr are correctly zero because frozen task writes lifecycle receipt to result file.

Collector failure `workload exit row count mismatch: 0 vs 1` came from `workload-identity-v7.ps1` regex matching CRLF text without normalizing `\r`: .NET multiline `$` anchors before LF, leaving CR before numeric end token, so `pid_exit` match returned zero. Result completed before collector ended, ruling out publication race.

`workload-identity-v8-crlf.ps1` keeps existing bounds, run count, PID/parent identity, handle, raw/signed/.NET exit, terminal, & stream-drain checks, while canonicalizing CRLF/CR to LF before regex. No row, display, timing, handle, or qualification guard is weakened.

Root command:

```powershell
& .\test-workload-identity-v8-controls.ps1 `
  -ResultPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-run-raw-r3\result-workload.txt' `
  -ControlRoot '<fresh-control-root>' -WrapperPid 58252
```

Use v8 helper in fresh collector only after source hash admission. Existing v1 failure-publication folder is historical rejected hypothesis; do not stage its flush-only fix.
