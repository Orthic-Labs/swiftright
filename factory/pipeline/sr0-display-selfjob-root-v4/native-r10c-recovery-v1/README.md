# SR0 native r10c recovery packet

This packet keeps qualification failure intact while emitting read-only owner-release eligibility. It never opens a PID, terminates a process, edits `desktop.lock`, or relabels historical receipts.

`assess-owner-release-v1.ps1` verifies exact owner text, original retained-handle terminal identities, launcher aggregate self-only/active=1/memory flags512, collector WorkloadWin/PresentMon handle identities, coordinator parent kernel/.NET identity, observer schedule/transport terminal proofs, then hashes every file listed by immutable `export-manifest.json`. It emits `eligible-for-owner-cas-review` only when every raw hash/byte check & transitive owned-tree proof pass. Any CAS must be performed separately using expected owner text; output keeps `qualificationClaim=false` & historical failure status.

Actual r10c evidence remains held: collector `failed` from early workload identity row-count observation, coordinator `held`, observer `held`; later sealed `result-workload.txt` is raw evidence only. PresentMon forced stop `-1` & stop command `0` are retained. No stream or display qualification is inferred.

`workload-identity-v7.ps1` retries only bounded incomplete worker/exit row-count observations for 30 seconds after workload terminal, then applies v6 identity checks unchanged. `collector-selfjob-v8-drain-pidjoin.ps1` is fresh copy with v7 identity helper pin/call. `run-once-v8-status.ps1` reads child receipts after terminal even when child exits nonzero, records child status/exit fields, & returns nonzero when held; this prevents transport success from masking held receipts.

## Root-owned review invocation

From repository root on Windows, after creating fresh output parent & choosing a fresh output file:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\assess-owner-release-v1.ps1 `
  -ArchiveRoot .\factory\pipeline\sr0-display-selfjob-root-v4\actual-native-r10c `
  -OutputPath .\.factory-work\sr0-display-selfjob-v4\native-r10c-recovery-v1\owner-release-review.json
```

Expected current result is `held` unless all transitive original receipt fields & export hashes match. A held result must preserve desktop ownership for independent root review; no automatic mutation is present.
