# SR2 adapted APIs (issue #55)

- **numeric-text-v1:** two counters under `.contentTransition(.numericText())` change under `.linear(duration: 1)`: 9 -> 10 and 41 -> 42, manual clock 0, 0.25, 0.5, 0.75, 1. Built from `sr2-effects/.../paint-colour-v1` (manual clock); only the witness and `pair.json` are the case's own.
  - Gate: glyph bands excluded (Segoe UI Variable against SF), semantic frames gated (final text, bounds). PROVISIONAL: the roll's travel distance, fade curve and line-box clip are unmeasured in the runtime; the first CI pair's mid frames decide them.
  - Risk: the Mac side drives SwiftUI through a custom-animation clock (`FactoryAnim.wrap`); whether the numericText roll follows that clock is unverified. If the Mac mid frames show the settled text, the case degrades to the settled frames and the unit tests (`Issue55NumericTextTests`) carry the mid-frame evidence.
- **glassEffect:** no case. It stays an adaptation (no material); see docs/sr2-plan.md.
