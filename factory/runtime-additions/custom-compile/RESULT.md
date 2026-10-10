# CustomLayout runtime153 result

Patch source: current runtime152 at `probes/sr0-s/fresh-runtime/`; oracle receipt: `156aafa820c8906bf0bf4be3b08c8eaf1f99175b4735233b135d54d7b2370106`.

Cause: missing `EnvironmentValues.layoutDirection` made generic `.environment(\.layoutDirection, .leftToRight)` resolution time out, with diagnostic reported at inner `Color.red.frame(...)`. Geometry overloads & custom layout witness were not causal.

Patch adds `LayoutDirection` enum & environment storage only. It does not implement automatic RTL placement; provider bidirectionality remains separate.

Receipts:

- Repo-prefixed patch dry-run passed.
- Internal patched runtime suite: 153 tests, 0 failures, exit 0.
- Exact unchanged witness body typecheck against patched module: exit 0.
- `Witness-A.swift` SHA-256: `77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b`.
- `Witness-B.swift` SHA-256: `77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b`.
- Patch SHA-256: `e76b4da2637b1528517e9205090cc280eb99fd9e2661293683bf01d5451d5a84`.
- Included `LayoutDirectionTests.swift` SHA-256: `d74a112f5470edd59ce030bd20efbfd45f2157c1d6b5f7c802d1e514180f8ada`.

Patch file: `01-layout-direction.patch`.
