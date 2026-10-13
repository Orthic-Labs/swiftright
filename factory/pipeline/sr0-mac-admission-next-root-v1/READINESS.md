# SR0 Mac full16x20 admission readiness v1

Status: **HELD before generalized signing or capture**. Tuple12 Mac F1 packet is usable only for F1; it cannot support F2-F9.

## Bound evidence

- Product source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`.
- Generalized recorder source: `probes/sr0-o/f1-cross/Sources/F1MacRecord/main.swift`, SHA-256 `90de6c1bca7fd114afc754ff2491e8732f9bd8b3922dce76d7aa9e34c7201507`.
- Package manifest: `Package.swift`, SHA-256 `3a30e1894d6379c2ed5c0cbb60fdeb7046fb29eab915eacea78054118622f92a`.
- Unsigned recorder: SHA-256 `3f3ec1041e35f598b96e85182aa5499b5b4315b2e7e9fdb03a0871aabeb83b13`.
- Sign helper source: `qualification/tuple12-mac-sign-no-ui-v1/sign-no-ui.c`, source SHA-256 `4248bf63d79dfc0555c58c74015bd7ee2344fac25aa4f84b92a890942296d37c`; helper SHA-256 `233a0317e1864d9f459e606c81fdb7f237933f6a4cf5458cd359ed2d888fc1bf`.
- Sign attempt receipt: `qualification/tuple12-mac-sign-no-ui-v1/root-review.json`, SHA-256 `611c1892ef94ff9db768027a4fbcab3a364cd1b9cbcb533e133f6bf53f5c58f8`; `signingInvocations=0`, `captureInvocations=0`, `tccMutations=0`, exit 78.
- Existing signed recorder: binary SHA-256 `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`, bundle SHA-256 `a5b8e07e5ad1f2802f2fcc2f8e9824e89e92ed7b9c260b7c9f8f3988829afeb5`, CDHash `5be97a95eac4ae045c1af4ea56db3b29f8fc83f3`. It is F1-only & contains stale hardcoded F1 steps.
- Signer identity available: `Developer ID Application: Adrian D'souza (6KLGD3LLKF)`.
- Read-only Mac-origin gate is PASS: `factory/gate/mac-origin-admission-evidence-v4/test-receipt.json`, receipt SHA-256 `c8e1598eda36fab949d63b816a3db0643c820ae05303d87c0a9a9640e200238d`; compiler/native capture both false.

## Exact blocker

`SessionCreate(0,0)` returned `100001`; existing security session had graphic/TTY access, while interaction was disabled. Helper exited before `/usr/bin/codesign`. This proves fail-closed behavior, not process-level no-prompt signing. No generalized signed binary, CDHash, bundle receipt, or AX trust receipt exists.

AX admission also remains unproven. Required receipt must call `AXIsProcessTrusted()` without options, record trusted state, make zero permission-prompt calls, & bind same generalized binary identity. Existing `examples/SliceApp/r7-final-transcript.txt` proves notarized package launch/window visibility only; it does not prove AX trust or recorder signing without UI.

## Smallest root-ready sequence after signer-owner evidence

1. Preserve unsigned source/build manifest under fresh internal scratch; verify source, package, binary, & plist joins.
2. Sign generalized recorder with exact identity above under process-level no-prompt proof; record signer child PID/start/terminal, exit, stdout/stderr, bundle tree, CDHash, Authority, TeamIdentifier, timestamp, & strict verification.
3. Run AX trust preflight against nonexistent target; require trusted=true & zero prompt/TCC actions.
4. Copy signed recorder, FixtureApp, & F1Assemble into fresh internal scratch; verify signatures & paths.
5. Run existing `qualification/tuple12-mac20.sh` for 16 configs × 20 only after receipts bind source, signed binary, AX trust, plans, stimuli, & fresh output namespace.
6. Assemble offline; retain 320 raw/event/trace triples plus process/signing/AX receipts.

Until steps 2-3 exist, safe work is read-only source/plan/receipt joins or unsigned build preparation. No existing signed F1 artifact can close generalized 16×20 hold.
