# Mac r11 source-bound Count20 candidate

This packet contains source-only bootstrap inputs for fresh Mac Count20 capture. Historical r09 case/captures & Windows r7 records remain immutable. Bootstrap case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11` is a template; recorded Mac host hash `13bfe5...` is historical context, not a preclaim for future build output.

Root first builds host on internal disk with `prepare-r11-host.py`, then binds actual binary bytes with `materialize-r11-case.py`. Materializer emits fresh case ID, tuple ID, manifest, source copy, & actual Mac host hash. `capture_origin_r11.py` requires that hash & fails with `HOST_HASH_DRIFT` before preflight/native launch when rebuild differs. Drift requires fresh materialization & fresh capture IDs.

Capture uses copied, source-reviewed AX client path. Existing signed recorder is F1-only; no generic recorder claim is made. Accessibility trust must already exist. `verify-r11-output.py` accepts only fresh host-bound r11 case/tuple with exact source, host, case, tuple, & 20-run joins.

Prospective Windows replay rules are in `WINDOWS-REPLAY-PLAN.md`: reuse existing executable only after exact fresh-case source/witness/compiler closure admission; otherwise compile fresh source-bound host before Count20. No historical Windows record is relabeled.
