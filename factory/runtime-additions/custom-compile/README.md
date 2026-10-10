# CustomLayout compiler diagnostic

Current runtime152 source: `probes/sr0-s/fresh-runtime/`; patch paths are repo-prefixed in `01-layout-direction.patch`.

Oracle receipt `156aafa820c8906bf0bf4be3b08c8eaf1f99175b4735233b135d54d7b2370106` defines `LayoutDirection` as an environment value. Patch adds only `LayoutDirection` & `EnvironmentValues.layoutDirection`; it does not claim automatic RTL layout or provider bidirectionality.

Unchanged witness body typechecked against patched runtime module with exit 0. Child arithmetic, `ForEach`, custom `Layout`, geometry overloads & outer `.frame` were already passing; missing `.environment(\.layoutDirection, .leftToRight)` key path caused reasonable-time diagnostic at inner `Color.red.frame(...)`.

Validation:

- `git apply --check --unsafe-paths 01-layout-direction.patch`: pass.
- Internal current suite: 153 tests, 0 failures.
- Unchanged witness body typecheck: exit 0.
- Witness A/B source hashes retained: both `77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b`.

Private scratch: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/custom-compile`.
