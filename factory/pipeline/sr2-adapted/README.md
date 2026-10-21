# SR2 adapted APIs (issue #55)

- **numeric-text-v1:** two counters under `.contentTransition(.numericText())` change with no animation transaction (9 -> 10, 41 -> 42). Static case (steps wait 600), copied from `sr2-effects/.../minimum-scale-v1`: glyph bands excluded, semantic frames gated (role, name, count, order, boundsY).
  - It covers the settled text and layout only. The roll cannot be compared: in CI 39585953303 the Mac host showed the settled text at clock frame 0 and identical frames afterwards (SwiftUI runs numericText in its render server, not on the factory's manual clock), while Windows rolled as designed (9 up and fading, 10 from below, clipped to the line box; 4 stays, 1 rolls to 2). The roll is verified by `Issue55NumericTextTests` (runtime) and `Issue55NumericTextPainterTests` (host) only; travel distance and fade curve remain unmeasured against SwiftUI.
  - The first version used a manual clock (0 to 1 s); it produced no semantic dumps (those exist only for static cases, so semantic pairs=0) and its glyph bands missed the second row.
- **glassEffect:** no case. It stays an adaptation (no material); see docs/sr2-plan.md.
