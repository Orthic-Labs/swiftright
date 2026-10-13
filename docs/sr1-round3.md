# SR1 round 3: blocks 11–20

Chosen 13 October 2026 by a Sage review of the demand map (`factory/shell/`). Only the `slice-editor` journey shows SwiftUI demand: rows f12-001/002/004/006/045. The plan also names presentation, animation, IME and environment. `swiftui.sheet` waits for round 4: it needs a decision between an owned second window (an ABI addition) and an in-window overlay.

| # | Block | Verification | Lane |
|---|---|---|---|
| 11 | swiftui.button | control gate + Sandbox click | A |
| 12 | swiftui.binding | semantic + rendered text | B |
| 13 | swiftui.textfield | pixels with text excluded + UIA value | B |
| 14 | swiftui.focus-state | semantic focus + Tab in Sandbox | B |
| 15 | swiftui.ime-marked-text | interaction + semantic (real-hardware IME deferred) | B |
| 16 | swiftui.list | pixels + arrow keys; onMove semantic | A |
| 17 | swiftui.alert | semantic only (native chrome) | D |
| 18 | swiftui.animation | time-sampled geometry, manual clock | C |
| 19 | swiftui.opacity-transition | time-sampled pixels (Image fade excluded until ABI 0.7 group opacity) | C |
| 20 | swiftui.color-scheme | static pixels, dark appearance | D |

Factory changes come first:
- **F1, manual clock** (lane C).
- **F2, Sandbox interaction job:** key/char/click/IME steps plus a UIA dump.
- **F3, semantic comparator:** compares the Windows UIA tree with the Mac in-process window tree.

One integration owner merges changes to `ResolvedNodePainter.emit` and `Graph.swift` serially.
