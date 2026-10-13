**Verdict: at-risk.** Direction corrected on one block, unchanged on four. Custom Layout is the first honest product-level delivery: the runtime gained CGSize/CGRect witnesses (`probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime/Layout.swift:9-13,65-80`, identical in the compiled factory copy) and the witness now carries only a conditional import (`Witness.swift:2-6`). The same SHA afe77… appears in the Mac manifest (`observed-mac20-r1/run-001/manifest.json:30`), the Windows compile receipt (`actual-final-r1/observation.json:9`) and the pair receipt (`first-pixel-comparison.json:3`). That is the pattern to repeat. Everything else since R8 is host adapters, staging repairs and a host self-check failure.

**Implementation vs machinery**

- Real: runtime Layout overloads; Stack semantic colour fix (diff 9600 to 307).
- Machinery or host substitute: FactoryDefaultBodyFont v8 decides Font.body inside FactoryProbe, not the runtime or product host; the host still hardcodes Segoe UI 16/24 (`main.swift:32-33`). Four Image preflight failures, transport hash repairs, count20 coordinator diagnosis. None moved a block.
- Count20-r4 "failure" is the host's own tick assertion (`main.swift:193`, `fail()` at `:105` requests quit). It fired after 170 commits (`14-host.stdout.txt:855-861`), child exit 1 (`13-final-exit-certificate.json:24`), predicate rejected (`0-coordinator.json:24`). Nothing in the renderer output is implicated. The `factoryOwnedClient` enumerator is in a file I could not read within limits, so pid-filter vs title-filter is unverified. Sixteen captures exist and were never compared. That is the cheapest missing evidence in the repo.

**Original-five status**

| Block | Verified | Gap |
|---|---|---|
| Custom Layout | Same source, 0 diff at 800x600 (`first-pixel-comparison.json:11`); host log shows both Color nodes at 2.5x witness geometry with spacing 10 (`14-host.stdout.txt:853-854`) | Receipt has `bounds: null` (`:12`), so content is inferred from the log, not the receipt. 16 Windows repeats uncompared. One case only |
| Rectangle | R8: fill exact, stroke short by mapper regression | No new evidence in packet |
| RoundedRectangle | Not delivered | SDK default claim unverified; stroke bbox defect unaddressed |
| ZStack/overlay | 307 px diff confined to 430,285-460,333 inside the block, centre RGB equal (`first-pixel-comparison-v1.json:10-42`) | Only the text run differs. Layout is working; text can never be exact across fonts |
| Image star.fill | Not built on Windows | Bottom-up flip persists (`FactorySystemImageProvider.swift:115-117`); descriptor hard-rejects anything but "substitute-provider-unverified" (`:55`), so the block cannot pass by construction |
| Bundled-font Text | Not delivered | lineLimit fix prepared, not run; renderer resolves by family string only (`text.rs:244`) |

Root's 0/5 uses "fresh paired 20" as the bar. Adrian asked for working and verified, not SR0 qualification. A deterministic layout witness with one exact pair plus the 16 repeats compared is verified.

**Strongest counterargument**

Hash-bound identity is what exposed the R8 witness mismatch and the stale-receipt reuse; without it "same witness" would be an assertion. True, and worth keeping. But the identity discipline is already built. The marginal hour now goes to rerunning count20, repairing staging, and rewriting font policy in the fixture, while three blocks have no Windows product code at all.

**Corrective actions**

1. Close Custom Layout. Run the comparator offline over the 16 captured count20-r4 PNGs against the Mac set, add non-white bounds to the receipt, and run one RTL case through the same witness. Do not rerun count20 first.
2. Deliver Rectangle stroke and Rounded through the host mapper fix R8 named (centred-stroke expansion). Settle the Rounded default with one quoted swiftinterface line. If continuous is confirmed, accept bbox equality plus bounded corner delta and record the continuous-corner renderer gap as the sole protected hold.
3. Stop host-side product policy. Font.body resolution belongs in the runtime or the product host that FreshOnBridge uses; compare ZStack non-text pixels exactly and text by bounds. Implement lineLimit in the measurer. For Image, drop the GDI rasterizer for a Segoe Fluent Icons text run through the renderer, or at minimum fix the flip and add a row-profile check; define acceptance as substitute glyph bounds, tint and orientation.

**Genuine holds**

- Renderer bundled-font registration: real while SR0 is OPEN (`docs/sr0-status.md:9`). A per-user Tinos install on the Dell would unblock verification; that is a host change for Adrian to approve.
- Continuous corners: real only if the SDK default claim holds. Evidence not supplied.

**Not holds:** paired-20 as a precondition; the Image "never counts" rule; the HWND ambiguity as a reason to pause Custom Layout.

**Unchecked packet claims:** Mac 20 repeats beyond run-001, Image compile fixes, transport runner fix, Rectangle stroke state. Two packet paths do not exist (`sources/overlay/capture-rectangle-count20-v1.ps1`, `Views/Layout.swift`).

**Next concrete action:** compare the 16 count20-r4 Windows captures against the Mac set offline and attach non-white bounds to the Custom Layout pair receipt.
