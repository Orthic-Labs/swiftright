# Tuple 13 Windows Full16 x20 (19 Oct 2026)

Pins: EXE 87b8cb27, renderer 1aa8ad22 (tuple 13), driver r6 0b95be5b, worker-v5 b039d4dc, coordinator-v5 e85c3c8f, runner run-matrix-v6w 4eb4f324 (same scripts as tuple 12, Dell `.work\sr0-t12-run`); base `.work\sr0-r13\typecheck\src`; admitted F1 smoke receipt worker-35579c20.

## Result: 320/320 qualified
`full16-r1-report.json` from the merged set: 300 Full-run cases (`sr0-t13-full-r1.zip`, runner log `full16-r1-runner.log`) + F6-reduced 20/20 from the F6Reduced rerun (`sr0-t13-f6reduced-r2.zip`, `f6-reduced-r2-runner.log`).
- Full run: 318/320. F6-reduced r3: driver trace lacked `WindowMetrics phase=startup` (worker rejected). F6-reduced r5: worker passed, coordinator exit 1 on `terminal proof ... quiescent=False`, which kept the desktop lock; the r6 coordinator then waited 3.5 h until the stale owner was released by exact-owner compare-and-set (no process left, no termination).
- Assembler v1 now accepts the F6Reduced rerun mode for F6-reduced cases only; control: an F1 case relabelled F6Reduced is rejected (319/320, `matrix-mode='F6Reduced'`).
