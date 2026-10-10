# R6 result: Mac SwiftUI oracle re-record (10 Oct 2026, HEAD 2da92ab, macOS 27.0.1 arm64)

Recorder: signed `F1MacRecord.app` (`com.orthiclabs.swiftright.f1macrecord`, team 6KLGD3LLKF, Developer ID, `codesign --strict` valid, executable sha256 `39ae7c9c08e0cb46...`; sign receipt `probes/sr0-o/f1-cross/out/signed/sign-receipt.json`). Run from a copy under the session scratchpad; Accessibility was granted (AXIsProcessTrusted passed, no prompt). FixtureApp built from committed tree `1b4affaf44f8` with `--scratch-path` under scratchpad (`SR0A_BUILD_ROOT`/`SR0A_OUT_ROOT`); nothing ran from /Volumes/D. Tuple 08 Windows trace: `qualification/out/r8-tuple08/win-trace-v0.json`.

## F1 to F9 (runner mac-oracle, 3 launches each, all 16 configs)
All 16 configs (F1, F2, F3 plus list/vstack/lazy 1s/3s, F4, F5, F6, F6-reduced, F7, F8, F9): 3/3 self-test PASS, canonical trace equals the accepted baseline. Log: `mac-oracle-3runs-events.jsonl`. (F6 happened to be 3/3 stable in that sample; see the 100-run sample.)

## F1 signed-recorder re-record and cross-compare
3 recordings (`f1/trace{1,2,3}.json`, F1Assemble `--keep-lists`). Versus `conformance/accepted/F1/trace-v0.json`: comparator 0 diffs each; the files differ byte-wise only in 10 `mono_ns` timestamp lines (same count in run1 vs run2). Versus the tuple 08 Windows trace: 0 diffs each (`f1/compare-vs-*.json`). Runner compare stage (`--win-candidate` = tuple 08 trace): pass, 0 diffs (`compare-F1.json`, `compare-F1-events.jsonl`). Accepted baseline NOT replaced.
Not compared: F2 to F9 have no Windows schema-v0 trace and the recorder and the runner compare stage are F1 only; their Mac side is the mac-oracle self-test trace above.

## F6 100-run sample (F10)
`run --stages mac-oracle --fixtures F6 --runs 100`: 100/100 self-test PASS. 96 canonical traces equal the accepted baseline, 4 differ (runs 13, 23, 24, 25: clustered, not spread).
Interrupted-animation completion order in the burst-insert step (second A/B pair):
- A before B: 96/100 (baseline order)
- B before A: 4/100 (runs 13, 23, 24, 25)
The first animation pair was A then B in all 100 runs. The runner wrote candidate `conformance/candidates/F6/20261010T082727.113Z` (untracked, NOT promoted); its diff is the A-complete event moving after the row-200 appear lifecycle event, same diff as the earlier candidate `20261009T075330.086Z`. Event files for runs 1, 13, 23, 24, 25: `f6/`; runner log: `f6/f6-100-events.jsonl`.
Reading: 4% swap rate on this Mac (earlier 1/20 = 5%) is consistent genuine SwiftUI completion-order variance; the clustering of 3 consecutive runs suggests sensitivity to host load/timing (other agent sessions were possibly active). Contract decision (permitted ordering or per-node order) belongs to the lead; no declaration made here.
