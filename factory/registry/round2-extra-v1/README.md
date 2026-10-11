# Round 2 extra source-bound candidates

This packet binds five held Round 2 behavior proposals to exact non-hidden USRs in frozen F1 catalogue. It does not edit active registry, claim behavioral support, or promote coverage.

`generate.py` resolves each exact module-qualified path to one catalogue item & emits `candidate-manifest.json`. `verify.py` re-resolves every path, checks catalogue pin, exact USR selector, item evidence hash, block order/cardinality, held status, empty unproven semantic dependencies, & promotion=false. `test_round2_extra.py` accepts baseline & rejects wrong USR/path, duplicate symbol, invented dependency, promotion, & altered evidence hash.

Current pinned inputs:

- `factory/catalogue/evidence/catalogue.json`: SHA-256 `740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270`
- active registry manifest: SHA-256 `7a2e80bf7ce132955e46b676c4818f96bfaebde279f5d5a4868da5d3bb482cf1`
- active registry evidence: SHA-256 `1ad0a508bb0b721a31f9e2ecdf209a217d20c52d2666a14d3eaf970653d8b983`

Five candidate block IDs: `swiftui.popover`, `swiftui.animation.spring-interruption`, `swiftui.text-field-ime`, `swiftui.environment-font-color-scheme`, `swiftui.context-menu`.

Semantic dependencies remain empty because no source-bound dependency edge is proven here. Recipe owners must add separate evidence. Coverage is identity-only & unsupported; all five stay held.
