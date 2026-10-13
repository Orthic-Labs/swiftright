# Tuple 12 Windows Full16 x20 (2026-10-13)

Pins: source 0e201571, EXE 87b8cb27, renderer 7578cd5d, driver r6 0b95be5b, worker-v5 b039d4dc, coordinator-v5 e85c3c8f. Runner: run-matrix-v6 with the pre-launch lock-free throw removed (coordinator already waits for the shared desktop lock); scripts staged at Dell `.work\sr0-t12-run`.

## Result: 320/320 qualified
`full16-r1-report.json` (sha256 469ba77e61e74a8708afedc220966ce815914865ed3db911cc27d4f348ec82b2), assembled from `full16-r1-merged/` (317 passes from run r1 + F3-list-0s 20/20 from rerun r2).
- Run r1 (`sr0-t12-full-merged.zip`, runner log `full16-r1-runner.log`): 317/320. Failures F3-list-0s runs 14,15,16 (raw: `sr0-t12-f3l0-failed-r14-16.zip`).
- Rerun r2 of F3-list-0s only: 20/20 (`f3-list-0s-r2-runner.log`).

## F3 ready diagnosis (68 s)
r6 diagnostic timing shows the delay is in the harness's synchronous ready-file read, not renderer startup: failing runs log `renderer_ready_file_seen_ms=12 read_ms=51735` and `read_ms=69213`, while passes log `read_ms=1`. Pattern: 3 consecutive cases in one window, then none for 300+ cases. Single F3 vstack-1s r6 run: wait 52 ms, PASS. Classification: host I/O stall (Defender MsMpEng real-time scanning of the freshly-created ready file is the leading suspect, unproven), not product (renderer wrote ready within ms; no runtime/renderer change). No harness code change helps beyond retry; Defender exclusions were not touched.

## Assembler fixes (harness)
qualification/assemble-tuple12-windows-full-v1.py: accept r6 driver pin and matrix-run-v6 kind/F3List0s mode; F6-reduced label is product-emitted `F6-reduced` (same label bug as worker-v4).

# Tuple 12 Windows cross recordings x20 (tuple12-cross20-r1/)
301/320 done: F1..F6-reduced 20/20 each (13 configs), F7 19/20, F8 19/20, F9 3/20. Stopped on coordinator order (Adrian working on the Dell) with lock `free`.
Classification: F3-list-3s t124, F3-lazy-1s t125 recorder `SetFocus returned but element lacks keyboard focus` (recorder flake; product self-test PASS; reruns passed). F7 t129+, F8 t1210+, F9 t124+: scheduled task vanished between register and query (host/other-agent task churn), batch aborted on missing artifacts line; retry loop recovered these. F7 t1211 failed recorder 3x (ok=false; failed attempts in failed-attempts-retry/, not yet diagnosed).
Resume (no GUI until lead says): F7 run 11, F8 run 20, F9 runs 4-20 via win-cross.sh with TAGP=t12 FIRST=n (see qualification/tuple12-cross20.sh env), then diagnose F7 t1211.
Mac references: only F1x20 exists (signed F1-only recorder; generalized recorder signing held). F1 pair-v2 already qualified. F2-F9 Mac 20 refs absent; cross-compare held.
