# Additive copy cost integration review v1

Source-only review of candidate Graph `775526e1f667f656adb5c7946e880a7079e9462d5d9815edc9a8a2d4dc4bba93` against protected current Graph `c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f`.

## Judgment

Candidate preserves value semantics in bounded controls for `ResolvedNode` additions & `ResolvedStyle`: both storage classes are immutable, `Equatable`, & `Sendable`; synthesized outer equality compares storage values through their `==` implementations. Nil defaults stay nil. Copying shares immutable storage, so copied snapshots retain values without copy-on-write mutation risk. Resolve logic computes same locals & public values. Controls are semantic evidence only & do not establish integration safety.

Candidate is not promotion eligible. Root reports unchanged typing/scroll assertions failed on both hosts with candidate: approximately 6.35/10.77 ms on Mac & 6.49/11.52 ms on Windows against 2/4 ms limits. Concurrent Dell Rust builds prevent causal attribution; retain this as a rejection signal, not as proof that boxing alone caused deltas.

Candidate changes representation deliberately:

- `ResolvedNode.labelsHidden`, `toggleStyle`, `imageSizing`, & `color` change from public stored `let` to public get-only computed properties.
- `ResolvedNode.shape` remains get-only, but its private storage joins `ResolvedNodeAdditions`.
- `ResolvedStyle.font` & `foreground` change from public stored `let` to public get-only computed properties.
- `ResolvedNode` & `ResolvedStyle` internal memberwise construction shape changes because private storage replaces fields.
- `Mirror` child layout & `MemoryLayout` change; renderer/ABI review remains held.

Repository search found no existing test construction of `ResolvedNode` or `ResolvedStyle`, no mutation of these fields, & no reflection assertions. These representation changes still require explicit source/API review before integration.

Candidate allocates `ResolvedNodeAdditions` only when additive values exist & `ResolvedStyleStorage` only when font or foreground exists. Legacy nil-style nodes avoid these allocations, but common styled/foreground mutations can allocate a new `ResolvedStyleStorage` & incur reference retain/release work. This entire-style box is the primary source-level risk.

Safe narrower proposal: keep current `ResolvedStyle` direct fields unchanged; keep current `Font.metadataStorage` unchanged; lazy-box only new `ResolvedNode` additive payload fields. Preserve existing `ResolvedShapeStorage` separately so shape equality/storage behavior stays as current. See `safe-narrower-candidate-plan.json`.

## Bounded test proposal

Use `factory/runtime-additions/additive-copy-cost-v1/actual-r3-controls.swift` as same-source scratch control on Mac & Windows. Root captures fresh process argv, cwd, PID, UTC start/end, exit code, tool/executable hashes, exact current/candidate source manifests, & raw stdout/stderr.

Require current & candidate to match on:

- independently constructed equal `ResolvedStyle` values & independently constructed unequal values;
- default nil style, custom font metadata, & foreground color;
- independently constructed equal whole snapshots & unequal addition payloads;
- copied snapshot retention after mutating copied child storage;
- shape geometry/paint, default image sizing nil, resized image sizing present;
- equal `SwitchToggleStyle`, unequal toggle style, & labels-hidden controls;
- Swift 6 `Sendable` compile plus detached read/equality of retained snapshots.

Run existing 175-test suite unchanged on both hosts. Add payload assertions only in candidate review tests; do not weaken original tests or alter workload. Keep r1 performance claims & 25-flush profile=nil result unchanged.

## Integration path

1. Root keeps current & candidate full-suite failures recorded & does not promote current candidate.
2. Review narrower source plan with current direct `ResolvedStyle`, then run unchanged 175-test suite on both hosts.
3. Run r3 controls with source/executable pins, then review public API shape (`let` versus get-only computed), internal `@testable` construction, `Mirror`, & ABI impact. Renderer/ABI approval remains separate.
4. Run host-approved matched performance workload including legacy nil-style nodes & styled/additive nodes. Accept narrower candidate only when semantic gates pass & performance evidence is independently reviewed.
5. Integrate only after both hosts pass; retain immutable additive storage, nil fast paths, explicit equality, & `Sendable` declarations.

No production runtime, renderer, bridge, or original test files are changed by this review.
