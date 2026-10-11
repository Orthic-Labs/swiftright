# Public ancestor evidence

## Current bounded source accounting

`public-ancestor-evidence-v2.json.gz` is a lossless, deterministic gzip (`mtime=0`) of a 138,987,898-byte proof payload. `public-ancestor-artifact-v2.json` binds stored SHA-256 `7fbcab45c711446d93b4e0fb9d9161379ada01a414934b6f47ff95db0d4e6baa`, raw SHA-256 `8af5faea52769717aadadd3b98ef74237a05304f3d6eff025fdc9572b7fe07f1`, & raw byte count. Production `exact_public_ancestor.load_artifact` checks both hashes & size, hydrates pinned inputs, rebuilds full resolution, & returns only after exact acceptance.

Final reviewed resolution reports `complete-source-public-api-accounting` for captured SwiftUI & SwiftUICore interface source under pinned SDK/compiler inputs. It enumerates 17,846 non-extension declaration starts, 2,386 nominal scopes, & 2,597 extension scopes; all 12,635 v12 anchors reconcile, with 5,211 additional starts. All 19,185 compiler records are classified; held reasons are empty. Source rows include 11,070 eligible compiler-mapped declarations, 4,244 inactive branches, 624 locals, 1,005 nonpublic source declarations, 31 nonpublic compiler-access records, 848 macOS-unavailable declarations, & 24 documentation-hidden declarations. The primary compiler catalogue has 11,942 USRs, including 3,304 absent from original 836 graph closure. Accessor accounting retains 2,190 observed records, 2,018 typed-public accessors, 5 accessors capped by nonpublic owners, & 2,013 effective-public child records (2,008 unique USRs); held child/compiler-component counts are zero.

This is source/API accounting for these pinned interfaces & observed compiler records. It does not certify every SDK module, generated/compiler-only API family, future SDK, or public-ancestor eligibility beyond captured evidence. Original 108,272 symbol-graph objects & 836 raw graph inputs remain unchanged. Graph fallback is lossless: [raw symbol-graph archive](/Volumes/D/claude/swiftright/factory/catalogue/raw-symbolgraph-archive-v1/README.md) verifies each original input descriptor & whole-file hash before exposing reconstructed bytes; it does not bundle SDK sources or compiler tools.

Independent final review: report `32837c8307898c1b1f8a81c960fcc1a6b1a33afd5b4a075382948dd70b122ee7`; supplemental report `ad90b620c0bd6aee4a79236ea9059c6a240a02cf3c27479757bac6ebc29f5ed4`; full-v2 clearance `f65d60710a30aea8a9e61c2bc493c24bf0a445f6725f22e58a886ec972400089`; stage packet `95da2cf516f4bf45212c57c1d6874be40aa182d13680b3208dc1bd27947a8546`. Review replay reconstructed the pinned artifact & resolution; 34 producer fault controls passed. Producer's final stage/fault receipt should be retained beside these refs when available.

To force compressed proof hydration with exact compressed & raw pins, then run the 34-control production suite:

```sh
PYTHONPATH=. factory/.venv/bin/python factory/catalogue/public-ancestor-spike/test_public_ancestor.py
```

The test reads `public-ancestor-artifact-v2.json` for raw digest & size and calls `load_artifact(..., expected_raw_sha256=..., expected_raw_bytes=...)`; production review additionally forces archive replay. Do not replace either pin with values calculated from the artifact under test.

## Historical census v1

`raw/ancestor-census-v1.json` remains an immutable historical snapshot, not a current-reproduction claim or eligibility result. Its original lexical parser hash was `88c8ee0f71e18288f5502df757f55879cf16b1a470732c75f999618d0ab04f63`, but those parser bytes are unavailable & have no known Git object. The shared parser changed, so v1 generator fails closed; do not recreate source from pycache or overwrite v1.

The v1 capture recorded 20,379 parser starts plus 57 audit-anchored supplements, 19,185 SourceKit entities, 12,635 v12 rows, & 541 nonempty SwiftUI extensions targeting SwiftUICore. Its output SHA-256 is `ba84859f8387d3c1361b3287a5adf458fd256ffb8c8d900c72997cf43cdaf174`; internal census hash is `sha256:472d9252adac670826d062595c2ee67553c43fe4d2f684f810d5166119fb2295`. V1 is historical & unrepeatable; corrected enumeration & proof are separately versioned above.
