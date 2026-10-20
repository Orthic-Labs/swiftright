# #25 selection highlight: Windows Graphics Capture (20 Oct 2026)

Dell desktop, tuple 13 FreshOnBridge `87b8cb27…` + renderer `1aa8ad22…`; every presented frame of the fixture HWND recorded by FactoryWGCRecord (CI run 39352780878, sha256 3fddddb9…), 10 s, 597 frames at 1606x1275 (`wgc-f5.ps1`, `f5-frames.jsonl`).

- `--fixture F5`: app events show `focus source=initial` on Row 1 right at ready (`app-stdout-f5.txt`). Every frame holds the selection highlight over "Row 1" (5,623 px of 0x99C9EF) and the caret (`f5-launch-crop.png`, `f5-frame-000001.png`). **Painted.**
- Earlier "not painted" records were wrong fixture choices: F1 and plain F3 (List) have no launch focus (F3 events show none; `f3-list-no-launch-focus-crop.png`), so no caret or highlight is expected there.
- Remaining difference (SR1 parity, cosmetic): the fixture host paints 0x99C9EF (153,201,239); the Mac-measured emphasized selection is (179,215,255) (docs/sr1-status.md, swiftui.textfield/FACTS.md:12).
