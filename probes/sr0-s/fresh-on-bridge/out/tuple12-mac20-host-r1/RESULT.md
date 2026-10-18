# Tuple 12 Mac x20 references and cross-compare (18 Oct 2026)

Mac: host Mac, macOS 27.0.1 (26A434). Recorder `~/Applications/SwiftRight/F1MacRecord.app` (current source with `--steps`, Developer ID 6KLGD3LLKF, identifier com.orthiclabs.swiftright.f1macrecord, same designated requirement as the previously granted build, so AX trust carried over with no prompt). Hashes in `binaries.txt`.

- Capture: `qualification/tuple12-mac20.sh`, 16 configs x 20 = 320/320 PASS (`mac20.tar.gz`, log inside).
- Compare: `xcmp.sh` pairs Mac n<i> with Windows t12<i> from `tuple12-cross20-r1` (r2 where present), `sr0o-trace compare --adapt cross/<c>/adapt-v0.json`. Result `xcmp.log`, reports in `xcmp.tar.gz`.
- 302/320 pass. 18 fail, all `focusedNodeId` + `selection` actual `<none>` on the Windows side: F3-lazy-1s 8, F5 4, F7 2, F3-list-1s 1, F3-list-3s 1, F3-vstack-3s 1, F8 1.
- 12 of 18 fail at `initial`. In-process events in failing runs (e.g. F3-lazy-1s t121 vs passing t123) show the same focus events (`source initial`, `source ax`); the UIA side record has no `focusedAutomationId`, so the fixture window was not the OS foreground window at the snapshot. Harness class (foreground lock under the background driver), not a product diff.
- F8 t126 is the one timing case: in-process `AX value applied@9.15s` vs 6.30 s in t125, so the `set_value_row3` snapshot preceded the focus.
- Fix: Windows recorder checks the fixture is foreground (and settles) before each snapshot; re-record the 18 failing tags.
- `sr0o-trace repeat` exited 2 on these traces (it expects a different input schema); repeatability was not checked here.
