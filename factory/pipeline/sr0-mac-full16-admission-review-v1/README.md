# SR0 Mac full16 admission review

Status: **HELD**. Review is source/evidence only; no signer, TCC, native, or process action was performed.

## Evidence

Existing recorder evidence is `factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/evidence/recorder-capabilities.json` (SHA-256 `51c51709094e182f3eed93733596e42204676dfce9b6853208d59e1df52a7710`). It records `axTrusted: true`, `permissionRequests: false`, `externalAX: HELD`, `genericProtocolSupported: false`, `sourceBinaryProtocol: F1-only`, and preflight exit `2`. Its copied executable is `F1MacRecord` SHA-256 `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`.

Identity evidence (`recorder-identity.stderr.txt`, SHA-256 `b2180fabf5a21ec7868df5587844226e5230516c077067485f3972203662caff`) records Developer ID Application `Adrian D'souza (6KLGD3LLKF)`, identifier `com.orthiclabs.swiftright.f1macrecord`, hardened runtime, sealed resources, and CDHash `5be97a95eac4ae045c1af4ea56db3b29f8fc83f3ad3f3bd3e4473dacf2ab308d`.

No-prompt preflight (`recorder-no-prompt-preflight.stderr.txt`, SHA-256 `0f1cd1f38d64cafa44bce31eced92dfd410ede152ba114da02b1a937469ede04`) failed only after attempting intentionally missing fixture. Protocol evidence (`recorder-binary-protocol.stdout.txt`, SHA-256 `eebad99198babbaa9dcc2466be7c8a3fafdc633d174ceb6ba118bdab32faeccc`) exposes F1-specific `--fixture`, `--events`, and `--out` usage; it does not expose generic 16-case `--steps` or equivalent input.

Fresh host build evidence (`host/host-build-r1.json`, SHA-256 `ab38be841b62900958a63f9b7f83867e35420fe2410511303dfd9279393f6769`) is `candidateOnly: true` with `nativeWindowActions: 0`; it is not signed-recorder admission evidence.

## Decision

`axTrusted: true`, screen-capture fields, or Developer ID identity do not establish permission for a different recorder or prove no-prompt use. Existing signed binary is F1-only, rejects current generic protocol, and is explicitly barred from reuse for full16. A fresh signed generic recorder receipt is missing: source hash, executable/bundle hashes, CDHash, authority/team/timestamp, strict verification, unchanged `AXIsProcessTrusted()` preflight, zero prompt calls, and successful missing-fixture preflight.

No safe full16 launch command exists from current evidence. Root may perform read-only hash/receipt review; full16 admission requires signer-owned fresh generic recorder evidence under `docs/sr0-tuple12-mac-recorder-recovery.md` (SHA-256 `c038470337dae5208b35598baaf044df06bbb76597d5d92aaad5ff4c82be715d`).
