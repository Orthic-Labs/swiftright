Last updated: 2026-10-11T10:34:11Z


State: plan changed by Adrian's answers (relayed by Right Mac, 2026-10-11): W08 must be fixed; apply the two small held fixes (startup window size, selection highlight) so 0.6 is frozen correct; then requalify and run the 20 comparison runs on that final 0.6; then freeze. Order of work: items A, B, C below.
# SwiftRight — pending (SR0 close-out lane)

| # | Item | State |
|---|---|---|
| A | Apply held patches 01 (selection highlight) and 02 (ready metrics, renderer + bridge); build and test | in progress |
| B | W08: a cancelled MSIX update must not leave the app unopenable | open: cannot be prevented from inside the package (an unopenable package cannot repair itself); the fix belongs to the release/update tooling (RightKit); options sent to Right Mac |
| C | Requalify on the new 0.6 build (tuple 12): matrix, smoke, pixels, text, modal, R9, R10, MSIX, cross-compare at 20 runs per side | waiting on A; MSIX needs signing: the Windows certificate expires 2026-10-12 05:16 Dell local and the standing rule says no signing: needs Adrian: sign the tuple 12 packages before the certificate expires, yes or no? |
| 1 | Final qualification runner pass on tuple 11 | done: all stages pass except package Windows W08 (item 4); `qualification/out/r8-tuple11/` |
| 2 | Dell stage trees moved under D:\Claude\swiftright\.work, script paths updated | done |
| 3 | Narrator speech content | Adrian: "I'll listen later"; fixture ready to run on his word |
| 4 | W08 | answered: must be fixed (see B) |
| 5 | Comparison repeat count | answered: run the contract's 20 per side, on the final 0.6 (see C) |
| 6 | Freeze | decided: not yet; after A, B, C |
| 7 | Retry-cap overruns | acknowledged by Adrian ("Let it run") |
| 8 | Unproven recorder items (CROSS-ALL.md) | R8 settled (8f548ef8). R5 closed: the two start sizes are constants of the two test hosts (Mac fixture 480x560, Windows host 640x480), not SwiftUI behaviour; an optional probe F5-nosize is committed, not run. R6: proposed accepted-limitation (needs a Mac input-source change) |
| 9 | Selection highlight not painted (caret only) | written, held for Adrian (unbuilt, untested, applies cleanly; note beside it): /Volumes/D/claude/tasks/handoffs/2026-10-11/patches/swiftright-01-selection-highlight.patch; held for Adrian |
| 10 | Renderer ready metrics report the wrong height before the window settles (docs/sr0-findings.md §12) | confirmed by a factory run (findings §12). Held patch now covers both halves: renderer stores width, height and scale together before emitting the event (a short-circuit in paint_root left height and scale stale when only one changed) and refreshes before ready; bridge `metrics` equals the event payload. Written, unbuilt, held for Adrian |
| 11 | IME candidate list does not follow a mid-composition layout move | written, held for Adrian (unbuilt, untested, applies cleanly; note beside it): /Volumes/D/claude/tasks/handoffs/2026-10-11/patches/swiftright-03-ime-candidate-follow.patch; held for Adrian |
| 12 | SR1 factory | owned by the Codex factory session; renderer/ABI edits held until SR0 status says closed |

Conflict note: the relayed rule says dev builds only, no signing. The tuple 10 Windows packages were signed under Adrian's direct SR0 instruction before that rule reached this chat; no further signing is planned.
