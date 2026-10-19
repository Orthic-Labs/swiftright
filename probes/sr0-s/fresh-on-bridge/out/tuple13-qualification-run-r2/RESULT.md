# Tuple 13 combined qualification run r2 (19 Oct 2026, after the MSIX rebuild)

`combined/`: mac-oracle 336 pass + 1 fail, compare 85, workload, native, smoke, package 6 (Windows 15/15 on the rebuilt MSIX with renderer 1aa8ad22, Mac 12/12), exit 1 on the one mac-oracle fail.
- The fail: mac-oracle F5 (Mac SwiftUI reference, resize fixture) produced 2 distinct canonical traces in 20 runs: one run logged extra transient narrow/wide layout states during the live resize (`f5-nondeterministic-candidate/diff.txt`). Mac reference timing, not a Windows or renderer result; F5 was 20/20 in the r1 combined run.
- `f5-rerun/`: mac-oracle F5 x20 alone: 22/22 pass, exit 0.
Tally for F5 on the Mac reference today: 59 of 60 runs on the accepted trace.
