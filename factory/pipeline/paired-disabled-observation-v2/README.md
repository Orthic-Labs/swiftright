# Paired disabled observation v2

This report keeps three source batches independent: 20 new macOS external AX enabled-state reads, 20 historical macOS paint captures, & 20 Windows `actual-r1` UIA observations. Historical paint records remain unchanged & are never decorated with AX enabled values from new runs.

Run `python3 factory/pipeline/paired-disabled-observation-v2/build_report.py` from repository root to revalidate every pinned input byte & rebuild `evidence/report.json`. Frozen input manifest contains 1,131 path/byte-count/SHA-256 references, including complete raw batch files & independent review receipts. No input normalization or raw capture rewriting occurs.

Cross-platform semantic map is explicit: macOS `AXButton` maps to Windows `ControlType.Button`; label must equal exact `Continue`; `AXEnabled.value` & UIA `enabled` must both be exact JSON booleans. Report observes `true` in 20/20 runs per platform batch. Batches are independent; no per-run pairing is asserted. Windows PrintWindow repeat captures have one shared raw hash across 20 runs.

Report remains observational only: accepted golden count is zero. Callback/hit-testing, qualified timing, controlled occlusion, frozen tuple binding, & native parity remain held. Raw timestamps remain in source files without qualification. Windows screen capture retains raw variants; identical PrintWindow output does not prove controlled occlusion.

Run targeted checks with `python3 -m unittest discover -s factory/pipeline/paired-disabled-observation-v2 -v`. Tests reject altered raw bytes, non-boolean enabled values, wrong AX role, duplicate target, stale analysis linkage, & PrintWindow repeat mismatch.
