# Seed compiler-origin shared compiler receipts v6

V6 preserves v5 & routes every Swift compiler invocation through one bounded process/tool/source/binary receipt collector. It adds an auxiliary AXClient compiler receipt, raw streams, exact source joins, & read-only preflight output. No GUI or seed capture runs before review.

Fresh main control: `positive-control/evidence/compiler-receipt.json` sha256 `38e49bff71f2e2ea432ae516a27492ed604a44b6dc34ab70ab6eba3dec32454c`, compiler PID `85518`, resolver PID `85511`, exit `0`, binary sha256 `515bbc6a5cbd1d7a7bb434b870a8f1a2a44849ab6dcbc39f69d060b32d862b90`.

Fresh auxiliary AX control: `auxiliary-ax-control/evidence/ax-compiler-receipt.json` sha256 `a7fc8c9a6d17b8d060e9bce2379fc17b7be7f873dead025f0437be6b2c0109c2`, compiler PID `81415`, resolver PID `81408`, exit `0`, binary sha256 `7f1013de103feefabf35a525bfedd28a2abbe60763761c8e0372530f8a051581`; preflight reports `axTrusted=true`, `permissionRequests=false`.

Runtime dependency closure has 23 entries; test_v6 ran 10/10. Failed path-resolution control remains archived & records compiler not invoked. V6 remains compiler/preflight evidence only.
