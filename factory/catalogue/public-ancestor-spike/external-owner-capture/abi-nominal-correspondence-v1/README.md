# ABI nominal correspondence v1

Bounded raw capture for five Core nominal source declarations whose compiled imported member trees use SwiftUI ABI namespace:

* `AttributedTextFormatting` → `s:7SwiftUI24AttributedTextFormattingO`
* `CustomHoverEffect` → `s:7SwiftUI17CustomHoverEffectP`
* `HoverEffectContent` → `s:7SwiftUI18HoverEffectContentP`
* `TupleContent` → `s:7SwiftUI12TupleContentV`
* `Text.LineStyle` → `s:7SwiftUI4TextV9LineStyleV`

Nested `AttributedTextFormatting.Transferable` is captured separately with exact imported USR `s:7SwiftUI24AttributedTextFormattingOAAE12TransferableV`. Core source declarations, SwiftUI extension lines, SourceKit import refs, pinned SDK/toolchain, typecheck, request, raw output & demangle output remain separately hash-bound. `CustomHoverEffect` & `HoverEffectContent` compile through explicit macOS-unavailable wrapper.

Evidence records observed per-nominal namespace correspondence only. It makes no blanket Core→UI alias, graph-absence exclusion, eligibility, or promotion claim.

Pinned Core interface flags independently show `-module-abi-name SwiftUI` with `-module-name SwiftUICore` & `-public-module-name SwiftUI`; this explains observed ABI spelling while each row remains bound to exact SourceKit ref, source line, kind & access.

Run:

```sh
python3 capture_abi_nominal_correspondence.py
python3 test_abi_nominal_correspondence.py
```
