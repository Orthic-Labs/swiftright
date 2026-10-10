# Preference runtime additions

Series starts at `probes/sr0-s/fresh-runtime` commit `08d6ce6b0b7accfad2178a7f0600c714749bbbc6` (see `BASE`). Apply API patches in order; each adds one API.

| Patch | API | Integration commit | Full tests observed |
|---|---|---|---:|
| 01 | `PreferenceKey` & typed shared storage | `a4cf7e2d` | 141 |
| 02 | `.preference(key:value:)` & bottom-up reduction | `976b12ac` | 143 |
| 03 | `.onPreferenceChange` after settled evaluation | `0d7fe2f3` | 144 |
| 04 | `.labelsHidden()` with Toggle layout suppression, AX title retention & visibility cache invalidation | `9060345a` | 147 |

All stages retain all 113 original compatibility tests. Stage counts include added tests. Patches 03 & 04 were tested from private build copy `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/preferences/rebased-976b12ac/stages/`; patch 03 was refreshed against post-02 commit `976b12ac7404834f1eea8f0db07589b0295c53cf`, with `Preferences.swift` normalized to one final newline.

Frozen Windows runtime reference at `factory/native/windows/api-baseline-8e47b89-20261011/runtime` is separate from this additive source. Results cover headless runtime tests; Windows paint & performance acceptance is not recorded. No native parity is inferred.
