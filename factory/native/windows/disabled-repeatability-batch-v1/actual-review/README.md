# Independent actual batch review

Offline review validates exactly 20 fresh sequential observations from `actual-r1`, with one owned probe PID/HWND per run, released lock, empty run log, exact 5-file source package, source/case/compile/exe/UIA/PID/HWND/viewport/process-clock joins, raw UIA semantic projection, & exact PrintWindow/screen repeat hashes.

Raw semantic result is `Continue`, `ControlType.Button`, enabled `true`, native size `160x60`. PrintWindow repeat hash is stable across all 20; screen captures have 3 raw hashes as foreground changes between `395622` & `0`.

Mutation controls reject changed source binding, case, PID, semantic enabled/role/name, extra or missing run, & PrintWindow repeat. Original raw files remain unchanged.

Review scope stays observational: `qualifiedWindowsBatches=0`, timing unavailable, hit-testing not attempted, provider readback absent, controlled occlusion unqualified, native parity held, closure unbound. No rerun, SSH, compiler, GUI, Pulse, or source edit.

Run `python3 -B review.py` from this folder. Outputs are `report.json` & `raw-pins.json`.
