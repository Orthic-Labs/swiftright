# Workload R10 v6 failure diagnosis

Frozen packet: `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v6-r1`; receipt is immutable.

Evidence:

- All three worker & sampler lines report kernel terminal `1`, signed/raw/.NET exits equal `0`, stream drains `1`, `run_state valid=1`, `background_noactivate=PASS`, & `task_quiescent=1`.
- Coordinator receipt reports `orchestratorTerminal=true`, `streamsDrained=true`, `taskQuiescent=true`, `presentMonSessionAbsent=true`, but `cleanupProof=false`, `runProof=false`, `semanticRunProof=false`, `exit=9`, & lock retained.
- `result-workload.txt` is CRLF. Coordinator v5 line-anchored `run_state`, `pid_exit`, `resources`, & `stream_drains` regexes use `$` without CR normalization, so valid records are rejected.
- `run-workload.ps1` v6 `Stop-Pm` assigns proof fields inside function scope. Caller line 244 therefore sees initial `$pmKernelTerminal=$false`, `$pmStdoutDone=$false`, `$pmStderrDone=$false`, & `$pmKernelExitSigned=259`, despite log line showing terminal true, signed/raw `-1`, drains true, & session absent true. This directly caused exit `9`.
- PresentMon was forced-owned after 60s natural wait; raw DWORD `4294967295`, signed exit `-1`, & .NET exit `-1` match bit-exactly. Forced stop remains explicit evidence; no proof weakening is proposed.

Immutable successors:

- Workload v7 `run-workload.ps1` SHA-256 `f464e356bec5dbfddb03e35954d19de0f5ef5c50d11d7315593855068d4f94e4` publishes Stop-Pm proof fields to script scope.
- Coordinator v6 SHA-256 `d579ae6d7b640d09519b57326ef2c19e2895f1b78c8f431a3b9f17156981ab5f` normalizes CRLF before strict, semantic, & cleanup proofs.
- Pure controls pass: `qualification/test_tuple12_workload_lifecycle_v7_controls.py` SHA-256 `e39547c65ac0eb1b01470f4ceb45d31e3c6ad55cfc7b02e66719b0b5d4e1796b`; `qualification/test_tuple12_workload_coordinator_v6_controls.py` SHA-256 `2f236891b3b035ffafb9adec23895bb2655d122b9b7d60e9f0683ab7ed565e62`. Coordinator control exercises CRLF anchor failure & normalized success.

Root must parse/typecheck successors before any native rerun. Frozen v6 packet remains unchanged.
