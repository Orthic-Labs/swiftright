Last updated: 2026-10-11T09:12:02Z

# SwiftRight — pending (SR0 close-out lane)

| # | Item | State |
|---|---|---|
| 1 | Final qualification runner pass on tuple 11 | done: all stages pass except package Windows W08 (item 4); `qualification/out/r8-tuple11/` |
| 2 | Dell stage trees moved under D:\Claude\swiftright\.work, script paths updated | done |
| 3 | Narrator speech content | asked via Right Mac; needs Adrian: listen to Narrator on the Dell for about 2 minutes while the fixture runs |
| 4 | W08 (cancelled MSIX update leaves NeedsRemediation) | needs Adrian: accept as a known limitation with the three measured recoveries? |
| 5 | Cross-compare used 3 runs per side; contract says 20 | needs Adrian: accept the deviation, or run the 20-run version (about 4 h on the Dell)? |
| 6 | Freeze: CONTRACT.md v1.0-rc to v1.0, ABI 0.6 frozen | needs Adrian: sign off the freeze? |
| 7 | Retry-cap overruns after 9 October | needs Adrian: acknowledge (recorded in docs/sr0-retry-ledger.md) |
| 8 | Unproven recorder items (CROSS-ALL.md) | R8 settled (8f548ef8: Mac and Windows both reject late results after close, 0 effects diffs in 3/3 pairs; all 16 Mac baselines unchanged with the new opt-in fixture variant). R6: proposed accepted-limitation (needs a Mac input-source change). R5 (F5 initial window size): next, needs a Mac fixture variant and a paired Windows run |
| 9 | Selection highlight not painted (caret only) | open, SR1 |
| 10 | Renderer ready metrics report the wrong height before the window settles (docs/sr0-findings.md §12) | open, SR1 (ABI 0.7 proposal has it) |
| 11 | IME candidate list does not follow a mid-composition layout move | known limitation, SR1 (TSF) |
| 12 | SR1 factory | owned by the Codex factory session; renderer/ABI edits held until SR0 status says closed |

Conflict note: the relayed rule says dev builds only, no signing. The tuple 10 Windows packages were signed under Adrian's direct SR0 instruction before that rule reached this chat; no further signing is planned.
