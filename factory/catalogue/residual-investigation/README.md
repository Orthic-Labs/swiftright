# F1 residual investigation

`investigate.py` reads pinned v6 declarations, current SourceKit `indexsource` output, request identities, SDK interface hashes, & compiler USRs. It emits `residual-evidence.json` without changing catalogue, strict adapter, or existing evidence.

Assigned baseline contains 213 held rows:

- 206 wrong-context rows: raw public kind/name exists at exact line, but raw SourceKit enclosing context differs from v6 context.
- 1 conditional-no-index-entity: `SwiftUI` `WidgetBundleBuilder.buildLimitedAvailability` line 28491; cursor receipt selects inactive `#else` overload under `compiler(>=5.3) && $InlineAlways`, with zero raw index entity.
- 1 wrong-kind row: `_ImpossibleActor` line 18132 is emitted by SourceKit as `source.lang.swift.decl.class`, while v6 kind is `actor`.
- 5 duplicate-sourcekit-usr rows: each retains two raw occurrences with same compiler USR; cardinality blocks promotion.

Current strict input exposes 51 access-only control rows where raw effective access is public but v6 signature has no explicit access token. They remain listed in `accessOnlyControlKeys` & are excluded from assigned 213-row baseline, preserving prior 208 non-duplicate + 5 duplicate count.

Run from repo root:

```sh
python3 factory/catalogue/residual-investigation/investigate.py
```
