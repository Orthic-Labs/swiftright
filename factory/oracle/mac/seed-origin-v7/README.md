# Seed compiler-origin source admission v7

V7 prepares five remaining seed cases for a future bounded Mac capture:

* `swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258`
* `swiftui.image.recipe.gate-seeded.ca4e13f820f5d258`
* `swiftui.shapes.fill-stroke.recipe.gate-seeded.ca4e13f820f5d258`
* `swiftui.text.bundled-font.recipe.gate-seeded.ca4e13f820f5d258`
* `swiftui.toggle.recipe.gate-seeded.ca4e13f820f5d258`

All rows use seed `14577611000270672472`. Exact gate manifests, recipe JSON, generated source, witness source & negative witness source are archived under `inputs/`. `input-pins.json` joins every path, byte count & hash, including manifest source/witness joins & canonical recipe hashes.

V6 bounded compiler/AX observer source is byte-pinned through `admission/v6-admission-pins.json`; v6 decision is `READY_FOR_BOUNDED_CAPTURE`. Runtime dependency archive contains 23 pinned files. No seed capture, GUI action, Accessibility request, or permission request ran in v7; `captureStatus` remains `NOT_RUN`.

Replay source admission:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-origin-v7/verify_v7.py factory/oracle/mac/seed-origin-v7 --workspace /Volumes/D/claude/swiftright
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-origin-v7/test_v7.py
```

Eight controls reject source drift, altered pins, witness drift, duplicate case IDs, canonical recipe drift, dependency drift, collector drift & permission API insertion.
