**Verdict: off-track.** Rectangle fill progress is genuine, but the path chosen for the other four blocks cannot complete them under the implementing agents' own rules, and the last interval produced no new Windows observation for any block.

**Direction finding.** The decisive blocker on block 1 is factory host code, not the runtime and not the protected renderer. The runtime at `probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime/Shapes.swift:79` already records corner radius, corner style and centered stroke width as plain data. The host mapper at `factory/pipeline/pilot-delivery-five-v1/text-shape-image/rounded-stroke-host-v1/package/Sources/FactoryProbe/FactoryShapePrimitive.swift:18` throws for continuous corners, then maps circular corners to the same ABI rect radius and border fields a few lines later. The raw r13 stdout confirms window, viewport and centered bounds were ready before that throw, and the exit certificate records a natural exit from the original witness binary. Root's retracted "invented blocker" reading was therefore correct in substance even though its circular-default premise was stale. The diagnosis's recommendation to keep the hold until renderer capability exists makes block 1 unachievable under the SR0 renderer freeze. By the diagnosis's own account, r12 was also lost to a policy that holds on any nonempty requirement list. Two native runs in one hour consumed by self-authored gates is the pattern the brief asked me to test for, and it is present.

**Block status.** Verified from receipts and source unless marked as a claim.

| Block | Windows evidence | Status |
|---|---|---|
| Rectangle fill | 20 of 20 PrintWindow rasters byte-exact to Mac at 800×600; strict Mac and Windows joins | Working, under declared host centering on both sides |
| RoundedRectangle stroke | None; host guard rejects runtime default | Self-blocked |
| Image star.fill | None; one 34×30 fixture with yellow baked into every pixel | Fixture, not Image semantics |
| ZStack/overlay | None; source-only | Not attempted |
| Custom Layout | None; R3's build-and-Count1 action not done | Not attempted |
| Bundled-font Text | None; host measurer rejects any non-body font | Self-blocked |

The Rectangle comparator's negative controls run the production Mac reader, and its scope string at `compare-centered-paired20-v1.py:266` admits Windows fault coverage is absent. The semantic channel is set to none by design at line 446. For a static shape, AX and displayed-frame timing are not relevant to "working"; one unoccluded screen capture per host would settle residual doubt cheaply. The star.fill host at `main.swift:18` throws for any font other than body, so the bundled-font block is gated in host code before any renderer question arises. Whether the star witness itself requests yellow is unverified; either way a per-case baked raster cannot scale to ten or twenty blocks.

**Strongest counterargument.** Mapping continuous corners onto the renderer's circular radius and inset border yields pixels that cannot match Apple, and a lenient comparator could later pass a wrong corner. That risk is already mitigated: the comparator is byte-exact RGBA, so any corner or edge delta surfaces as a measured bounding box. Refusing to render produces no measurement at all, which is worse for "fix mistakes".

**Corrective actions, ranked by user value.**
1. **Remove the continuous guard**, map both styles to ABI rect, rebuild, run Windows Count1 against the fresh Mac reference, and report the diff bounding box. That box is the exact protected-code-need evidence, or shows a runtime-side rasterization path suffices.
2. **Build and run Count1 for ZStack and custom Layout now.** Both are runtime-only behaviors needing no provider and no adapter beyond the declared root-centering translation.
3. **Rasterize symbol glyphs in the host at render time** from resolved size and tint, dropping the sidecar packaging step, and extend the measurer to accept custom font metadata so the bundled-font witness can at least attempt a run.

**Holds.** Genuine: SR0 renderer and ABI protection, W08 upstream repair, Narrator listening, desktop lock serialization, memory caps, and Mac recorder signing for SR0 full16 only. Unnecessary or stale for the five: the continuous provider hold, the sidecar-before-native rule, displayed-frame evidence for static paint, parity promotion as a prerequisite for "working", and the dispatch pause pending review. The user asked for hourly reviews, not an idle lane whenever the review channel fails.

**Review resources.** R5 ran on claude-fable-5-1 and was killed without a verdict after unscoped Glob and Grep.

| Peak group RSS | Cap | Wrapper exit |
|---|---|---|
| about 777 MiB | 768 MiB | SIGTERM |

The repository's per-run receipt sprawl makes unscoped search unaffordable. Packet-scoped reads are sufficient, as this review shows.

**Unverified.** Star and rounded Mac witness sources, whether ABI 0.6 can load a bundled font file, custom Layout packet contents, the r12 policy code, and the r4 HTTP 429 receipt.

**Next action.** Root deletes the continuous guard in a fresh copy of FactoryShapePrimitive.swift, rebuilds the rounded-stroke host, and runs Windows Count1 against the observed-mac20-r3 reference.
