# Generalized Mac recorder signing hold

Read-only review: no signing, capture, or TCC mutation was admitted.

- Identity is available: `Developer ID Application: Adrian D'souza (6KLGD3LLKF)`; matching key ACL allows `/usr/bin/codesign`, but ACL visibility does not prove noninteractive private-key use.
- Existing helper receipt `qualification/tuple12-mac-sign-no-ui-v1/root-review.json` is `held-before-signing`, with `signingInvocations=0`, `captureInvocations=0`, `tccMutations=0`, receipt SHA-256 `611c1892ef94ff9db768027a4fbcab3a364cd1b9cbcb533e133f6bf53f5c58f8`.
- Preflight reports `SessionCreate(0,0)=100001`, then disables user interaction (`interactionAllowed=false`) & aborts before `/usr/bin/codesign`; no prompt-enabled fallback was attempted. Helper exit is `78`; unsigned generalized recorder SHA-256 is `3f3ec1041e35f598b96e85182aa5499b5b4315b2e7e9fdb03a0871aabeb83b13`.
- Existing signed recorder SHA-256 `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4` is trusted for prior F1 only & contains stale hardcoded F1 steps; it cannot admit generalized F2-F9 capture.

Generalized 16-config Mac capture remains held until same-team generalized binary receives existing AX trust evidence plus process-level proof that signing cannot display UI. No new signer route is admitted by this review.
