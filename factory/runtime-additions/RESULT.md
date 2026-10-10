# Additive runtime results


| API | Commit | Full Mac suite |
|---|---|---:|
| Alignment | `3a10ab8e` | 114 |
| Rectangle | `a89474e5` | 115 |
| RoundedRectangle | `17949bfd` | 116 |
| Circle | `f7745d45` | 117 |
| ZStack | `15c0501c` | 118 |
| overlay | `320e79b8` | 119 |
| Fixed frame | `83338c8b` | 123 |
| Scalar padding | `8f222dac` | 124 |
| Color as View | `619421d5` | 125 |
| Native Layout geometry bridge | `22172ff2` | 126 |
| Image.resizable | `c99b1d6b` | 127 |
| scaledToFit | `1a4044f5` | 129 |
| Font.system design | `309aa166` | 132 |
| Font.custom family | `2458bd1e` | 133 |
| lineLimit | `db29fd6d` | 135 |
| ScrollView axes | `08d6ce6b` | 139 |
| New RoundedRectangle SDK-default correction | `d1ca1e47` | 140 |
| PreferenceKey storage | `a4cf7e2d` | 141 |
| preference reduction | `976b12ac` | 143 |
| onPreferenceChange | `0d7fe2f3` | 144 |
| Toggle labelsHidden | `9060345a` | 147 |

Every row passed its full suite before commit, preserving original113 tests. Root integration used `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/integration` with internal `build-baseline` scratch; no fresh binary ran from `/Volumes/D`. Independent review checked new-feature gating, source compatibility, cache invalidation & SDK signatures. Layout geometry bridge supplies partial source compatibility; provider paint/layout/timing qualification follows explicit SR0 closure.

Four preference/visibility APIs were integrated as separate commits from base `08d6ce6b0b7accfad2178a7f0600c714749bbbc6`: `PreferenceKey` storage (`a4cf7e2d`, 141 tests), `.preference(key:value:)` reduction (`976b12ac`, 143), settled `.onPreferenceChange` (`0d7fe2f3`, 144), & Toggle `.labelsHidden()` (`9060345a6e757fe18208683a536d9fbd98be01aa`, 147). Every observed suite had zero failures; all original 113 compatibility tests remained green.

Final runtime subtree at 04 commit: `a9758090d0ecfc3487ca11468bd30f493e50f08d`. Worker staged suites ran in private build copy `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/preferences/rebased-976b12ac/stages/`; 03 & 04 ran against post-02 base `976b12ac7404834f1eea8f0db07589b0295c53cf`.

Patch SHA-256: 01 `5931549382932259eaff5f7564d9d967c4b2475167b18f912546f01fb745a6a3`; 02 `2a54782b06ed7e4b7535fef0d68138ee4edfcf7c3b0cb657a62c0b52bbdf0e84`; 03 `f449501cf2d21a5d7168856de5e2d33e1e2daf7ca564321c191798660156cd32`; 04 `ed00373bbcbabf775b3b8a181a90eebdfb77974149b69fc56072f78a076e2d94`.

The frozen `8e47b89` Windows runtime reference remains separate. Windows performance & paint acceptance is not recorded; no native parity is claimed.
