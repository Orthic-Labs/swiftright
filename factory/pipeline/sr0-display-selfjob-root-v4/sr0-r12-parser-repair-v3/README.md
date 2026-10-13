# SR0 r12 parser repair v3

Actual `actual-run-raw-r3/result-workload.txt` contains one `worker`, one `pid_exit`, one `stream_drains`, `valid=1`, `task_quiescent=1`, & workload exit identity 0. Redirected workload stdout/stderr are correctly zero because frozen task writes lifecycle receipt to result file.

Collector failure `workload exit row count mismatch: 0 vs 1` came from `workload-identity-v7.ps1` matching CRLF text without normalizing `\r`: .NET multiline `$` anchors before LF, leaving CR before numeric end token, so `pid_exit` match returned zero. Result completed before collector ended, ruling out publication race.

`workload-identity-v8-crlf.ps1` keeps existing bounds, run count, PID/parent identity, handle, raw/signed/.NET exit, terminal, & stream-drain checks, while canonicalizing CRLF/CR to LF before regex. No row, display, timing, handle, or qualification guard is weakened. v3 control mutates handle to `0`; prior `2812→2813` mutation was ineffective because parser did not compare that value.

`materialize-parser-v3.ps1` copies explicit collector/helper sources into fresh output, replaces exactly one collector `Resolve-WorkloadIdentityV7` call with `Resolve-WorkloadIdentityV8` when present, rejects ambiguous/missing calls, & records source-hash refresh requirements. It never executes collector.

`materialize-observer-v3.ps1` copies explicit observer/admission sources into fresh output. `observer-early-failure-v3.ps1` invokes same admission predicate with 1100s observer, 900s transport, & 120s cleanup-margin fields; it returns held transport evidence only, never qualification or lock-release eligibility.

Root command:

```powershell
& .\test-workload-identity-v8-controls.ps1 `
  -ResultPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-run-raw-r3\result-workload.txt' `
  -ControlRoot '<fresh-control-root>' -WrapperPid 58252
```

Negative controls use one-second completion grace. Root refreshes collector/helper hashes after materialization & before any staged run. Actual fixture is 2,837 bytes, SHA-256 `c841626334d8b7a2ad9c13a1e72a4db49f6e64077b6e9bc622f2e4b387d0ae3e`; controls retain CRLF source bytes & perform no additional normalization before parser call.

Existing v1 failure-publication folder is historical rejected hypothesis; do not stage its flush-only fix.
