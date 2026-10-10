Offline compare of the committed recordings after the 10 Oct 2026 review (`../../CROSS-ALL.md`, section "After review").
`compare-<config>.json` is the comparator report of each of the 16 configs (diffs, allowed diffs with their allowance id and status);
`compare-events.jsonl` is the runner event log of the same run (16 compare verdicts and 65 negative controls).
Produced by `qualification/run.py`'s `run_compare` with a comparator built from the working tree
(`--stages compare --win-candidate-dir probes/sr0-o/f1-cross/cross`); no Mac GUI and no Dell were used.
The directory `../runner-compare/` holds the pre-review run (unscoped allowances) and is superseded.
