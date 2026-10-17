# Pulse hub in SwiftUI: SwiftRight track

Updated 17 October 2026.

## Decision and ownership

- Adrian chose Pulse as SwiftRight's first real consumer. The Pulse hub (React and Tauri today) is being rebuilt in SwiftUI. The hub goes first because its Tauri baseline makes the §11/SR4 budgets reachable. The Pulse notch's Win32 baseline is 10.9 MB private memory, which a SwiftRight port is unlikely to meet (see [pulse-notch-demand-map.md](pulse-notch-demand-map.md) §6).
- RightKit owns the shared base: RightKitHub (shell, section registry, theme tokens, settings kit, components, platform-service protocols) and RightKitEngine (an EngineClient over the rightkit-job-queue C ABI). The Mac uses a supervised child; on Windows the hub attaches to the Rust notch's engine over rightkit-daemon.
- The Pulse Swift chat builds the Pulse sections. SwiftRight builds the Windows hub exe and proves its controls.

## What SwiftRight provides (requested by RightKit session Rk3, 14 October)

Evidence was checked against the repository on 17 October. "Complete" means the artifact exists and does what its row says; it does not mean the hub is finished.

| # | Deliverable | Path | State | Evidence |
|---|---|---|---|---|
| 1 | Machine-readable proven-control list, with a `--check` drift mode | `docs/proven-controls.json`, `factory/tools/proven-controls/generate.py` | complete | `generate.py` `main()` (line 457) returns 1 with "drifted from its sources" when `--check` is in argv and the output differs, else prints "is current"; `statusDate` is 2026-10-17 (issue #14 closed). Caveat: the drift check was not run in this lane, and no CI workflow or pre-commit hook invoking `--check` was found under `.github`. |
| 2 | MarkdownUI (gonzalezreal/swift-markdown-ui) Windows probe | `docs/probes/markdownui-windows.md` | complete (probe result: FAIL) | Verdict FAIL, 14 October: swift-markdown-ui 2.4.1 does not compile against the SwiftRight runtime; `import SwiftUI` does not resolve, and with a probe-only shim 90 unique errors remain in 34 groups (a lower bound). Errors: `docs/probes/evidence/markdownui-windows-errors.txt`. Nothing rendered. Windows logs stay on the Dell. |
| 3 | Hub-base gap check: a compile probe per candidate API | `docs/probes/hub-base-gap-check.md` | complete | 33 probes in `probes/hub-base-gap/Sources/` (generator `make_probes.py`, runner `run.ps1`). All 33 type-check on the Mac. Windows results are on the Dell (`D:\Claude\swiftright\.work\hubgap-run2-20261014\`), not in the repo, so the per-probe Windows outcomes are unverified here beyond the table in the doc. Compile evidence only; no rendering or behaviour claim. |

## Constraints the base must respect

- Build only from proven controls. Block 13 (TextField) is NOT-DELIVERED until the bezel text-inset fix passes review; blocks 14 and 15 inherit it. Re-delivery of blocks 7, 13 on HEAD is still open (issues #4, #5, 17 October).
- No Canvas and no Swift Charts; charts are drawn with shapes. Path itself is not yet a delivered block.
- Expect these to be missing or unproven until delivered as blocks: Path, Circle().trim, ProgressView, sheet/confirmationDialog (round 4), searchable, NavigationSplitView/NavigationStack, toolbar, Form/Picker/Slider. The gap check confirms each. Slider (block 37) has since landed; see "Since 14 October".
- Known Windows differences: text fields draw no focus ring; IME on real hardware is deferred; toggle label widths differ; ImageRenderer renders a ScrollView blank on the Mac.

## Since 14 October

- **Pulse rounds 5-9 (`docs/pulse-hub-windows-port.md`).** Round 5 (15 October) closed the 20 compile gaps (19 SwiftUI API gaps, one Foundation gap that is Pulse's) and rendered all 12 sections in light and dark, 24 of 24 pictures. Round 6 (16 October) repeated that at Pulse `3e8b6b29` with PulseFit on and off and closed Text in priority groups. Rounds 7-9 drew app icons: `canImport(SwiftRightHost)` is now true in RightKitHub, and round 9 (Pulse `7ef8d10ab`) shows five distinct icons on screen. Chess Night's icon is verified only at fixture-byte level. The pictures are static first frames, not pixel-comparable to the Mac.
- **Block 27 `swiftui.layout-priority` (`docs/sr1-status.md`).** Text layout rules L1-L8 cover eight Text cases at N=20; the block is delivered-with-caveats. An Oracle re-review of the lifted narrowing is open (issue #12).
- **Blocks 37-41 (`docs/sr1-status.md`).** 37 slider: 13/13 at N=20. 38 on-hover: delivered-with-caveats (Oracle PASS, CI run 38916701641). 39 uia-walk: delivered-pending-review (H24), Oracle review open (issue #9). 40 ime-traps: 4/4 CI N=20 with pixels report-only (H28, issue #3 closed); Oracle review open (issue #10). 41 compat: delivered-with-caveats after the transaction rework (commit `7796b0b81`, CI run 38916914529); open edges A and B are in its row. Issue #2 (completion deferral) is coded but not yet built or tested.
- **17 October backlog.** Every pending SR1 block, review and SR0 close-out row is a GitHub issue in Orthic-Labs/swiftright, #4 to #28 (#28 added the same day for the Mac capture hosts' install identity). This issue (#26) tracks the three rows above. Issues #4-#28 are open except #3, #14 and #27, which are closed.

## Next blocks this track drives

Round 4 picks its blocks from the gap check and the hub's real screens, ordered by how many hub sections need each. Blocks 21-36 were built in rounds 4-5; blocks 20, 28 and 34 are still not-delivered (issues #6-#8), and the rest are in "Since 14 October". The next picks are the open issues above, in the order Adrian sets.
