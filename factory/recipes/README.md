# Recipe drafts & case expansion

`data/*.json` contains ten schema `0.1` recipe drafts. Every draft remains in
`candidate` review state. Witness Swift declarations live in `witnesses/`;
recipe loading verifies file hashes and schema before returning them.

Each positive witness contains `{{axis-id}}` placeholders matching recipe axes.
The probe generator must substitute declared values only, reject unknown or
leftover placeholders, and use negative fixtures only for their matching
negative case ID. Instrumentation transparency and negative cases are explicit
members of each expected case set.

```python
from factory.recipes import load_recipes, expand_cases, validate_case_manifest

recipe = next(item for item in load_recipes() if item["block"] == "swiftui.image")
expanded = expand_cases(recipe, measured_tuple, seed=0)
validate_case_manifest(expanded)
```

Pairwise axes use a seeded deterministic greedy covering array. If any axis is
marked `full-product`, all axes for that recipe expand as a full Cartesian
product. The expected-case hash covers sorted `{id, inputs, coverage}` rows,
matching F10. The manifest also binds exact case artifact hashes, so missing or
modified case content fails validation.

Case provenance `createdAt` defaults to recipe's pinned `provenance.createdAt`,
so same recipe, tuple, inputs & seed yield same complete case artifacts across
wall-clock time. API callers can set `snapshot_created_at`; CLI callers can use
`--snapshot-created-at`. Already archived case manifests & capture snapshots are
immutable and are not rewritten by this timestamp change.

Use `python -m factory.recipes --list` to inspect drafts. Expansion requires a
complete measured tuple; no tuple or placeholder hashes are checked in. For
native output, pass `--out-dir factory/recipes/cases` to write `manifest.json`
and one canonical case JSON per case. Font resource pilot artifacts live
separately under `factory/resources/fonts/pilot/` and are not added to the
active `data/` recipe set.

The active text recipe uses its system-font witness. A separate Tinos bundled
font candidate binds its own recipe, witnesses, cases & captures under the
font resource pilot directory; font resolution stays held where a host channel
cannot identify the SwiftUI text face.
