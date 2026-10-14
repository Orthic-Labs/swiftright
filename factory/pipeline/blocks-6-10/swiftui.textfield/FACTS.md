# swiftui.textfield, focus-state, ime-marked-text: measured SwiftUI facts (macOS 27, SR1 round 3 lane B)

Method as in `../swiftui.binding/FACTS.md` (offscreen `NSHostingView`, scale 2.5 for pixels, synthetic events, `NSTextInputClient` calls for composition).

## TextField look and size (pixels at scale 2.5 on white; `.automatic`, `.roundedBorder`, `.squareBorder` are identical)
- `AppKitTextField` fills the width it is offered; height 24 pt bezeled, 16 pt `.plain` (no bezel, text at x = 0). Ideal size (`fixedSize`): text width + 8 pt (the placeholder when empty: `TextField("Name")` 48 x 24, "Hello" typed 43 x 24, prompt "Enter" 44 x 24). `frame(width:)` gives exactly that width.
- The text STARTS 6 pt in, in a 16 pt line, vertically centred; a long text is clipped at the cell's content rect, 4 pt from each side, so its ink reaches 4 pt from the right edge (no ellipsis; measured: last ink column 214 in a frame ending at 225). 6 = the cell's 4 pt content inset
  (`NSTextFieldCell.drawingRect(forBounds: 120x24)` is (4,4,112,16); `cellSize` of "Hello" is 43x24 = text + 2 x 4, which is why the ideal width uses 4) + the
  field editor's `NSTextContainer.lineFragmentPadding` of 2 pt (probe: `factory/tools/appkit-probe`). Measured on the captures: the selection highlight of a
  selected field starts at x = 40 px (frame at 25, scale 2.5) = 6 pt; the clip of `filled-truncated-v1` is 4 pt inside the 80 pt frame's right edge. An
  earlier version of this file said 4 pt (the cell inset alone): wrong by the 2 pt padding. The unbezeled `.plain` field has no cell inset (text at x = 0).
- Selection highlight: `NSColor.selectedTextBackgroundColor`, aqua: (0.7020, 0.8431, 1.0) = (179,215,255) on white (the accent (0,122,255) at 30%); the Mac captures draw exactly
  this (the window answers `hasKeyAppearance`, so the field editor is emphasized). Unemphasized (a window that is not key) is (220,220,220); darkAqua emphasized (63,99,139).
  Marked text is drawn with a yellow background on the Mac and an underline on Windows (not gated: its start follows the glyph advances).
- Bezel: the 1 pt border is drawn OUTSIDE the frame; border colour black at 15% (217 on white, (217,195,43) on yellow), outer corner radius 7 pt, frame corner radius 6 pt (circular arcs; a least-squares fit gives 0.48 grey levels mean error); fill white at about 98% (255,254,251 on yellow).
- Text colours (darkest glyph pixel): typed 33 (0x212121), placeholder 118 (0x767676) bezeled, 64 plain.
- A `Toggle`-like AX label does not exist: the AXTextField carries `AXPlaceholderValue` = the title (or prompt) and `AXValue` = the text.

## Editing, submit, focus
- Pointer click focuses the field; the caret goes to the click position (past the end = end). Tab and `@FocusState` assignment (`focus = .x`, `flag = true`) focus the field with its **whole text selected** (selection 0 + count); `focus = nil` / `false` leaves the first responder.
- Return: runs `onSubmit` actions **outer first, then inner**; the field keeps focus and selects its whole text (0 + count), with or without an `onSubmit`.
- Typing `x` writes the binding at once. The setter is also called with the unchanged text when a field gains focus (a counting setter sees an extra call).
- Two focus-bound fields: Tab visits them in tree order and wraps (first -> second -> first); Shift-Tab goes back. `@FocusState` moves nil -> .first -> .second as it happens; clicking another field reports `first -> nil` and then `nil -> second`.
- **Marked text**: `setMarkedText("ni")` on the field editor shows "abni" with the marked range 2 + 2 and the binding keeps "ab" (no setter call); replacing the marked text with another keeps the binding; `insertText("你")` commits and the binding becomes "ab你" (one call). Tab while composing commits the composition (binding gets it) and moves focus. A synthetic Return while marked commits AND submits, because no input method consumes it; a real IME consumes Return, so this is recorded, not mirrored (the runtime commits and submits nothing).
- Marked text replaces a non-empty selection (the selected text leaves the binding at once).

Product: `TextFieldStyle` and the four styles, `TextField(_:text:prompt:)`, `onSubmit`, `Graph.pressReturn(inTextField:)`, field layout in `LayoutEngine.measureTextField`, select-all on focus gain (`FocusTraversal.noteFocus`), implicit focus for unbound fields, `FocusState<Bool>` and `.focused(_:)`; host: `TextFieldArtwork`, `TextFieldPainter`, `HostTextInput`. Tests: `TextFieldBlockTests` (runtime), `TextFieldPainterTests`, `HostTextInputTests` (host).
