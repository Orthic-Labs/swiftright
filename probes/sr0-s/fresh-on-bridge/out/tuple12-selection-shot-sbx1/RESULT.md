# #25 selection highlight: tuple 12 frame evidence (19 Oct 2026)

Windows Sandbox on the Dell, tuple 12 FreshOnBridge `87b8cb27…` + renderer `7578cd5d…` (hashes in the logs), `--fixture F1` (launch focus selects all of "Row 1"; the cross recordings' UIA reads focus `row/…0001/field`, selection 0+5 at `initial`).

- `sel-shot-F1.png` (window as launched) and `sel-shot-F1-active.png` (after `AppActivate` returned True): no selection highlight (0 pixels of 0x99C9EF) and **no caret** in Row 1.
- Code at a9556b77f (`BridgeBackend.swift:504`, `:527`): both highlight and caret draw only when `row == focusedRow`. UIA, published from the same focus record, reports the focus, so the painted frame most likely predates the launch focus commit (no repaint after focus), or `focusedRow` is unset at paint time.
- Verdict (corrected 19 Oct): INCONCLUSIVE. Both frames were taken with GDI `CopyFromScreen`, which can return a stale frame for a flip-model (DirectComposition) window; the code paints caret and highlight whenever `row == focusedRow`, and `giveInitialFocus` commits right after launch. Needs a PrintWindow(PW_RENDERFULLCONTENT) or WGC capture. SR1-owned (#25); not a tuple gate.

## PrintWindow re-capture (19 Oct, tuple 13 build: FreshOnBridge 87b8cb27 + renderer 1aa8ad22)
`sel-shot-F1-printwindow.png` via `PrintWindow(hwnd, PW_RENDERFULLCONTENT)` after `AppActivate` returned True (`sel-shot-printwindow.log`). Row 1 field (`row1-zoom.png`) holds only white, the text colour 0x1F1F1F and border greys: no selection tint and no caret colour 0x111111. Two capture methods agree. Verdict: **not painted** on this build after launch focus, although UIA reports focus 0+5 (cross recordings). Likely cause to check in SR1: the frame is not repainted after the launch focus commit, or `focusedRow` is unset when the frame is built. SR1 (#25).
