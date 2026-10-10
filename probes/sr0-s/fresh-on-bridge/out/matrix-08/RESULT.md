# Matrix 08 — SR0 tuple 08, 20 runs per config

Tuple 08: FreshOnBridge 7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960, renderer
E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93 (9c261d4: AX trailing publish re-arm; 02b3cc0 modal fix),
D:\Claude\sr0-r08\src; every run ARTIFACT_OK. Normal host use, 10 October 2026.

**319/320 PASS; the one failure is external input.** F3 list-0s run 16: the driver posted one key (`x`, targeted, `fg_changes=1`,
`driver_abort=none`) but the row received "and the " as text-store input while the test window held the foreground — typing or
dictation from someone using the Dell, not test input — so `reinserted-index-and-text` read `and the Row 4` (11/12). Rerun of
that config, 3 runs (`rerun-F3-list-0s/`): 3/3 PASS. Three foreground-loss harness retries (F1 r20, F3 list-3s r17, F7 r20),
all passed on attempt 2, per the run-matrix.sh rule. Log: `run-matrix.log`.
