# SR1 root-metadata coordinator review v1

Read-only review of prospective Count1 coordinator, SHA256 `0d4c1c99ab8b571d949ebd82e01543eceef278ba69eda3817b0cc9dc54bc42f6`.

## BLOCKED_PENDING_MANIFEST_JOIN

- Actual Count1 packet stopped before lock at `Integration binding manifest drift`.
- Cause is exact: `root-metadata-controls-v1/resume-issued-coordinator.ps1:38` reads `$bindingEntry[0].hash`; actual `root-stage-manifest.json` uses `sha256` plus `bytes`. Current binding bytes/hash are 4764 / `e78fa3c182c89968bad4d6c84ad94775eb3d11207b6966699dc8d516fc7afd27`.
- Prospective v2 source line 40 uses `.sha256` plus byte length, & its packet manifest pins coordinator SHA256 `a385b3688550edfa505563ac83d0a588ad70569163cec8beb2c8c859e15ae1f2`; this correction is unexecuted, so overall coordinator review remains blocked until Count1 reruns with patched source.

## Fixture join audit

Actual fixture `root-actual-controls-v1/observed-metadata-r1/coordinator-single-r1` independently matches candidate tuple hash/bytes `40b1a3cb...` / 11041, schema hash/bytes `d319f074...` / 3784, verifier hash/bytes `4ab3aedc...` / 2678, source archive hash/bytes `21fe0b64...` / 1641, issued run nonce `466d32af...`, source hash `b969817f...`, exit 0, & zero native/window/GUI/remote/lock actions.

All 12 `candidate-context.macContext.sourceRefs` map to unique tuple keys; each local file matches declared path, SHA256, & bytes. Candidate tuple, candidate binding, issued metadata, source binding, schema receipt, source archive, & common schema layout joins match captured fixture values. These fixture matches do not certify coordinator execution after manifest correction.

Required root rerun: preserve frozen v1 receipt; run patched prospective coordinator against fresh Count1 namespace only after parser/manifest hash checks, then archive stdout/stderr, coordinator result, exact source hash, & updated manifest receipt. Do not claim PASS from current v2 source review or prior native-unrun controls.
