# Tuple 12 Mac x20 references and cross-compare (18 Oct 2026)

Mac: host Mac, macOS 27.0.1 (26A434). Recorder `~/Applications/SwiftRight/F1MacRecord.app` (current source with `--steps`, Developer ID 6KLGD3LLKF, identifier com.orthiclabs.swiftright.f1macrecord, same designated requirement as the previously granted build, so AX trust carried over with no prompt). Hashes in `binaries.txt`.

- Capture: `qualification/tuple12-mac20.sh`, 16 configs x 20 = 320/320 PASS (`mac20.tar.gz`, log inside).
- Compare: `xcmp.sh` pairs Mac n<i> with Windows t12<i> from `tuple12-cross20-r1` (r2 where present), `sr0o-trace compare --adapt cross/<c>/adapt-v0.json`. Result `xcmp.log`, reports in `xcmp.tar.gz`.
- 302/320 pass. 18 fail, all `focusedNodeId` + `selection` actual `<none>` on the Windows side: F3-lazy-1s 8, F5 4, F7 2, F3-list-1s 1, F3-list-3s 1, F3-vstack-3s 1, F8 1.
- F8 t126 vs t125: in-process stages show the app applied the SetValue at 9.15 s vs 6.30 s; the UIA snapshot for `set_value_row3` was taken before the focus landed. Cause class: snapshot-before-settle (recorder settle or Dell stall), unconfirmed for the other 17.
- `sr0o-trace repeat` exited 2 on these traces (it expects a different input schema); repeatability was not checked here.
