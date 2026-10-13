# Mac full16x20 no-prompt admission readiness v2

Status: **HELD before signing/capture**.

## Exact evidence

- Generalized source: `probes/sr0-o/f1-cross/Sources/F1MacRecord/main.swift`, SHA-256 `90de6c1bca7fd114afc754ff2491e8732f9bd8b3922dce76d7aa9e34c7201507`.
- Package manifest SHA-256: `3a30e1894d6379c2ed5c0cbb60fdeb7046fb29eab915eacea78054118622f92a`.
- Unsigned generalized recorder SHA-256: `3f3ec1041e35f598b96e85182aa5499b5b4315b2e7e9fdb03a0871aabeb83b13`.
- Sign helper source/helper SHA-256: `4248bf63d79dfc0555c58c74015bd7ee2344fac25aa4f84b92a890942296d37c` / `233a0317e1864d9f459e606c81fdb7f237933f6a4cf5458cd359ed2d888fc1bf`.
- Sign-attempt receipt SHA-256: `611c1892ef94ff9db768027a4fbcab3a364cd1b9cbcb533e133f6bf53f5c58f8`; `signingInvocations=0`, `captureInvocations=0`, `tccMutations=0`, exit 78.
- Identity available: `Developer ID Application: Adrian D'souza (6KLGD3LLKF)`; read-only ACL evidence does not prove noninteractive signing.
- Existing origin gate PASS receipt SHA-256: `c8e1598eda36fab949d63b816a3db0643c820ae05303d87c0a9a9640e200238d`; compiler/native capture both false.

## Smallest blocker

`SessionCreate(0,0)` returned `100001`. Existing security session reported graphic/TTY access, then helper set `SecKeychainSetUserInteractionAllowed(false)` & aborted before `/usr/bin/codesign`. No process-level signer receipt exists. Existing signed recorder is F1-only: binary SHA `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`, CDHash `5be97a95eac4ae045c1af4ea56db3b29f8fc83f3`; its `genericProtocolSupported=false` & stale F1 protocol cannot bind F2-F9.

Existing `axTrusted=true` evidence is bound to that F1 binary. It cannot transfer to unsigned generalized source. Full16x20 therefore needs exactly two fresh same-binary proofs: process-level signing with interaction disabled, plus `AXIsProcessTrusted()` true with zero prompt/TCC actions. `CGPreflightScreenCaptureAccess()` may be recorded as preflight only; no request API is admissible.

## Bounded work that needs no prompt

1. Preserve source/package/unsigned binary under fresh internal scratch & verify hashes against pins above; run only existing offline origin-admission checks.
2. Prepare signer receipt schema requiring signer child PID/start/terminal, exit, stdout/stderr hashes, bundle hash, CDHash, Authority, TeamIdentifier, & interaction-disabled state. Receipt must say `signingInvocations=1` only after root performs approved signing.
3. Prepare AX preflight schema binding `AXIsProcessTrusted()` result to fresh generalized binary hash, with `permissionRequests=0` & no TCC mutation. Reject stale F1 hash, missing trust, or any prompt route.
4. Admit full16 only after both fresh receipts join source, package, binary, case plans, & output namespace. Existing F1 artifact remains historical evidence.

No source/runtime/renderer edit closes blocker. This packet records readiness only; it performs no signing, session creation, permission change, process launch, or capture.
