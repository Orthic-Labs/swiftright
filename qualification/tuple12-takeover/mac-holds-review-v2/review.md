# Tuple12 Mac signing & W08 recovery holds v2

Status: source-only review. No signing, capture, GUI, permission, TCC, package repair, or remote action is admitted here.

## Evidence reviewed

- `qualification/tuple12-mac-sign-no-ui-v1/root-review.json` is `held-before-signing`: `signingInvocations=0`, `captureInvocations=0`, `tccMutations=0`. Preflight reports `SessionCreate(0,0)=100001`, existing graphic/TTY access, `interactionAllowed=false`, helper exit `78`, unsigned recorder SHA-256 `3f3ec1041e35f598b96e85182aa5499b5b4315b2e7e9fdb03a0871aabeb83b13`.
- `qualification/tuple12-mac-sign-no-ui-v1/sign-process.json` records no signed output: `signedBinarySha256` equals unsigned input, `captureActions=0`, `tccMutationActions=0`.
- Existing signed recorder `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4` is F1-only with stale hardcoded steps; it cannot admit generalized F2-F9.
- `examples/SliceApp/r7-final-transcript.txt` proves notarized Developer ID package acceptance, offline first launch after an explicit quarantine prompt response, row-data preservation, and window-server visibility. It does not prove recorder signing without UI, AX trust, or Screen Recording; transcript states no pixels were inspected because Screen Recording is denied.
- `qualification/receipts/package/win-r5-10-offline/W08-interrupted-update.json` records genuine c6 interruption at staging `+240ms`: old package `0.1.0.0` became `Modified, NeedsRemediation`, launch failed, data stayed intact, and same-version rerun reached `0.1.1.0:Ok`. `qualification/receipts/package-history/win-r5-08-offline/hold-open-W08-state.json` confirms status stayed broken through 10-minute hold; no manual repair occurred.
- `docs/sr0-w08-upstream-handoff.md` & `docs/sr0-w08-upstream-diagnosis.md` require versioned RightKit helper/source, retained feed/MSIX, recovery contract, clean-machine receipts, negative controls, and owner review.

## Safe autonomous steps

1. Preserve current unsigned recorder, build manifest, source commit, plan files, and fresh internal-scratch namespace. Run existing plan/source identity validation for F2-F9 when root schedules pure checks; do not invoke signer or recorder.
2. Keep F1 admission separate using existing signed packet `qualification/tuple12-mac-f1-packet.json`; do not reuse it for F2-F9.
3. Prepare a receipt schema for a future generalized signer result containing source/package/binary hashes, identity, identifier, TeamIdentifier, CDHash, Authority, timestamp, strict verification, and child-process terminal evidence. A receipt with no signed invocation remains truthful `held`.
4. For W08, perform read-only receipt joins & source/package pin review. Request upstream owner handoff with exact helper/feed/package bytes, recovery API, expected states, data preservation, idempotence, and failure receipts.
5. After upstream repair bytes exist, root may run fresh clean-guest cancellation/recovery matrix, then validate relaunch, package state, version, data hash, source availability, signature, and negative controls.

## Real holds

### Mac recorder

- Signer owner must provide process-level evidence that generalized `F1MacRecord` signing cannot show UI or wait for private-key interaction. ACL visibility, `SecKeychainSetUserInteractionAllowed(false)`, `kSecUseAuthenticationUIFail`, or `LAContext` scope alone does not establish this for separately spawned `/usr/bin/codesign`.
- Same-team generalized binary must be signed as `Developer ID Application: Adrian D'souza (6KLGD3LLKF)` with identifier `com.orthiclabs.swiftright.f1macrecord`; stale F1 binary remains ineligible.
- Existing active-user AX trust must be evidenced with `AXIsProcessTrusted()` and zero permission-prompt calls. If trust is absent, only active user may grant it; automation must fail closed.
- Full Mac `16 x 20` capture remains held until signer receipt, AX receipt, fresh output namespace, and no-UI process proof join. Later spoken/Narrator evidence remains human-only.

### W08 recovery

- RightKit/release owner must supply one versioned repair path or rollback-before-registration behavior. Local Settings Repair, same-version redeploy, `RegisterByPackageFullName`, `Reset-AppxPackage`, relaunch-only, or client kill cannot close W08 without owner-backed helper/source & clean-guest evidence.
- Required fresh evidence spans registration cancellation timings `200/240/280/320/360ms` with each attempt recorded as genuine interruption or non-induction, then verifies old/new package state, relaunch, external data hash, idempotent repeat, missing-source failure, wrong identity/feed, corrupt package, and client-kill controls.
- Until this handoff exists, no package mutation or repair invocation is autonomous-safe; preserve c6 hold evidence unchanged.

## Root handoff order

1. Keep both holds open & preserve current receipts.
2. Run only read-only source/plan/receipt checks.
3. Admit generalized Mac signing only after signer owner supplies no-UI proof & fresh signed receipt.
4. Admit W08 recovery only after RightKit owner supplies helper/source/package evidence & clean-guest recovery receipt.
5. Run native capture or recovery only in fresh bounded namespaces after corresponding hold closes.
