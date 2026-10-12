# Centered ZStack/overlay source packet

Original `Witness_stack_overlay` bytes are preserved: trailing `ZStack`, blue 48×32 rectangle, red 12×12 circle, bottom-trailing `Text("+")`, light scheme. Runtime source remains pinned to additive `37429120`; renderer remains tuple11 `e280f4a9`; bridge remains ABI 0.6.

Current runtime behavior is intrinsic: `ZStack` uses overlap planning, measuring children under proposal while returning max child size; `overlay` uses first child as base size & places overlay content inside that base. With 320×240 root proposal, this witness resolves to roughly 48×32 logical root rather than full viewport. Host packet therefore computes `dx/dy = centered viewport − resolved root pixel origin` & applies same translation to every resolved node subtree. Full viewport background remains separate. No runtime, renderer, bridge, or witness changes.

Root materializes fresh case/tuple/source hashes, then builds with canonical runtime/bridge/renderer inputs & captures compile, lifecycle, screenshot, UIA, and layout channels. Existing stack-overlay packets remain untouched.
