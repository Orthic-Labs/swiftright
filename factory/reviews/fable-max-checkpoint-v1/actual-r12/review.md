**Verdict: at-risk. Direction must change.** Real runtime code landed, but the critical path for three of the four unfinished blocks now runs through a self-built gate that a pre-existing timing test keeps shut. No new Windows capture exists for Image, Stack, Rounded or bundled font since R11, and R11's RTL case and scoped ask to Adrian were not done.

**Direction finding.** The compile helper binds any non-static runtime only through a qualified receipt at `prepare-pilot-five-compile-v1.py:24-25,133`. That receipt must show exit 0 and a "0 failures" summary on both hosts at lines 97-98 and 125-128. The typing guard fails on both hosts by under 0.1 ms, and `factory/HELD.md:25,57` records it failing before this work began. So the provider, body-font and continuous-corner code cannot reach a Windows capture until a wall-clock unit test passes. Adrian's recorded decision at `docs/sr1-plan.md:35` is that performance is reported, not gated. The "green both hosts" rule traces to the SR0 owner's release condition at lines 8-9 of that plan, not to Adrian. The packet's "user rule" label is unverified. Second misdirection: the Custom count-20 repeated one deterministic image pair twenty times, since every row carries the same Mac hash and the same Windows hash. Third: SR1 metadata coordinator packets at `factory/HELD.md:137-149` have produced zero captures while the simple coordinator delivered the Custom result.

**Original five.**

| Block | Verified by me | Unchecked or disputed |
|---|---|---|
| Custom Layout | Working and verified for one LTR case. The runtime runs the witness's own callbacks through LayoutRoot at `Layout.swift:104-130`. Host log places the layout 80x35 at 360,283 with 30x25 and 40x35 children. Receipt shows zero differing pixels, equal bounds, no normalisation. Coordinator shows natural kernel exit 0, no cleanup errors, lock released | "Whole 800x600 RGB": the receipt has no width, height, channel or comparator fields. The Witness.swift I read has 12x10 and 16x14 children, not the logged sizes, so I could not bind SHA afe77cd to a source. The witness needs a Windows typealias block, so source compatibility is partial |
| Image star.fill | Not working: inverted and cropped per R11-verified receipts. Provider now in runtime with top-down rows and exact face check at `WindowsSystemImageProvider.swift:136,178`, never compiled on Windows | The 2298 count is irrelevant. SF glyphs cannot ship, so the bar is upright, aspect-fit, bounds within a pixel, tint, declared substitute |
| ZStack/overlay | Nothing new verified. `NativeWindowsBodyFont.swift:65-70` resolves the Win32 message font. That is an unmade product decision | Equal bounds, text-only differences |
| Rounded fill and stroke | Real geometry with Apple's coefficients at `ContinuousRoundedGeometry.swift:25-31`. Sixteen-sample coverage at `ContinuousRoundedRasterizer.swift:60-73` cannot match CoreGraphics edges exactly | No Windows capture. Rectangle fill and stroke absent from two consecutive packets |
| Bundled-font Text | Blocked on renderer font loading, protected while SR0 is OPEN | No ask made, no capture |

**Memory and processes.** Verified from the R7 transport receipt: 2 GiB cap, 1.15 GB peak, cap not exceeded, streams sealed, natural child exit 1 from test failures. The 184-test and six-assertion counts sit in binary stdout I could not read. The Codex renderer load is unverified. If true, those are the unsupervised processes, and no timing conclusion is valid while they run.

**Useful implementation versus machinery.** Useful: the Layout path, continuous geometry and rasterizer, the GDI provider, the body-font resolver, the NUL-decode fix. Machinery: the qualified-runtime gate, count-20 repetition, the allocator-cap iterations, and the metadata coordinator packet chain.

**Strongest counterargument.** Identity joins caught the R8 witness mismatch and stale receipts, so binding an unqualified runtime risks capturing the wrong code. Answer: commit and blob binding at lines 72-86 of the helper already gives that assurance. The suite-green clause adds no identity and re-asserts a test that was intermittent before this code existed.

**Corrective actions, by user value.**
1. **Unblock captures.** Let the receipt name the archived timing method as a known failure, hash-pinned, with no bound loosened, or bind by commit and tree alone. Compile Image v10 once, capture once, report bounds, centroid sign and tint against Mac.
2. **One message to Adrian with three decisions.** A scoped additive font-loading entry in the renderer while SR0 is OPEN, the Windows Font.body policy, and the accepted edge tolerance for Rounded and Image. AD7 at `docs/sr1-plan.md:73-76` makes tolerances maintainer-owned, so nobody can infer them.
3. **Custom Layout.** Declare case one verified. Run the RTL case once at count 1. Add width, height and comparator identity to the receipt. Put Rectangle fill and stroke status in the next packet.

**Genuine holds.** Renderer and bridge protected while SR0 is OPEN. No permission prompts. No Dell deletion. Not holds: quota review debt, paired-20 before implementation, a green full suite before any capture, and idling all jobs for a review if that rule is self-imposed.

**Next action:** edit the qualified-runtime check in `prepare-pilot-five-compile-v1.py` to accept the named archived timing failure, build the receipt from the existing R5 and R7 runs, compile Image v10, capture once.
