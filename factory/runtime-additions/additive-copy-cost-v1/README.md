# Additive copy cost v1

Scratch-only source diagnosis for original runtime `api-baseline-8e47b89-20261011` vs current runtime `module-origin-37429120-20261011`.

## Evidence

Compiled with `/usr/bin/swiftc` Swift 6.4 arm64 macOS 27 using `-O`.

| Type | Original size/stride | Current size/stride | Scratch candidate size/stride |
|---|---:|---:|---:|
| `ResolvedNode` | 417 / 424 | 545 / 552 | 384 / 384 |
| `ResolvedStyle` | 49 / 56 | 57 / 64 | 8 / 8 |
| `Font` | 16 / 16 | 24 / 24 | 24 / 24 |

Current `ResolvedNode` stores five additive fields directly on every resolved value: labels-hidden, toggle-style, image-sizing, color, & shape storage. Current `ResolvedStyle` also carries a `Font?` whose metadata addition raised its stride by 8. Candidate moves both groups into lazily allocated immutable reference storage. Legacy nodes with no additive values keep storage nil, so no per-node additive allocation occurs; public fields remain computed properties with same values.

The 200-row existing-API-only probe created 1,202 live nodes. Outputs are saved under `logs/*-run.stdout.txt`. One sequential run reported median flush: original 0.804375 ms, current 0.852417 ms, candidate 0.834333 ms after the corrected no-allocation candidate; this timing is diagnostic only & does not establish causality. Struct layout reduction is direct evidence.

The additive API parity probe returned identical values for current & candidate: custom font family `Probe`, red foreground, blue Color, image sizing present, & `labelsHidden=true`.

## Candidate design

Apply `runtime-candidate-sources/SwiftRightRuntime/Graph.swift` changes to a review branch only after independent review:

1. Replace direct additive `ResolvedNode` fields with one optional `ResolvedNodeAdditions` reference. Allocate it only when at least one additive field is non-nil.
2. Replace direct `ResolvedStyle` fields with one optional `ResolvedStyleStorage` reference. Keep nil storage for unchanged default style.
3. Keep `Font` metadata storage unchanged; its 24-byte value is already indirect for metadata.
4. Re-run parity checks, then compare matched cold-process probes with the existing workload before any production adoption.

## Exact commands

```text
swiftc -O -module-name SwiftRightRuntime <pinned runtime>/Sources/SwiftRightRuntime/*.swift CopyCostProbe.swift -o <probe>
/usr/bin/time -p <probe>
swiftc -O -module-name SwiftRightRuntime <pinned runtime>/Sources/SwiftRightRuntime/*.swift AdditiveAPIProbe.swift -o <api-probe>
<api-probe>
```

## Pins

```text
baseline Graph.swift  fb5deb378cb9f13c2b829b6494c4511675bce7c01ed26c7e80c523ca208a7af7
current Graph.swift   c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f
current Controls.swift 646f42253fb783e10c02c37210bb936a9c3dda5b7347a0ed18a24c213732e4d1
candidate Graph.swift 775526e1f667f656adb5c7946e880a7079e9462d5d9815edc9a8a2d4dc4bba93
CopyCostProbe.swift d2004389e107e89087adc24c1249d76b92ae573b95c55bf576a1905d6e041b68
AdditiveAPIProbe.swift 7c77d559a4fdb186822f953aa3661010be3a17b6efdc62f4b52688763cfe3783
```

Process/tool receipt: `receipt.json`; complete build/run stdout, stderr, & binary hashes are retained in `logs/` & `SHA256SUMS`.
