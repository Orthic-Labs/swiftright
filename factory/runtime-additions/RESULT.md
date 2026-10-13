# Additive runtime results

**13 October current status:** [delivery summary & exact evidence](../../docs/sr1-status.md). Work paused by Adrian; originalfive incomplete. Historical results below retain original scope. Latest matched API6 suite: Windows187/187 & Mac180/180; later Rounded focused tests6/6 each. Candidate renderer is tuple11, not a frozen tuple10 closure.


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
| Legacy-node additive-feature lookup isolation | `a8e00740` | 147 |
| displayScale environment | `a1ec1fe3` | 150 |
| Toggle style metadata | `14cbbfb4` | 152 |
| layoutDirection environment | `e2875c5f` | 153 |
| Constrained flexible frame | `67b841fb` | 167 |
| Additive shape snapshot storage isolation | `bbceb5a1` | 171 |
| Additive font metadata storage isolation | `37429120` | 175 |

Every row passed its full suite before commit, preserving original 113 tests. Root integration used `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/integration` with internal `build-baseline` scratch; no fresh binary ran from `/Volumes/D`. Independent review checked new-feature gating, source compatibility, cache invalidation & SDK signatures. Layout geometry bridge supplies partial source compatibility; provider paint/layout/timing qualification follows explicit SR0 closure.

Four preference/visibility APIs were integrated as separate commits from base `08d6ce6b0b7accfad2178a7f0600c714749bbbc6`: `PreferenceKey` storage (`a4cf7e2d`, 141 tests), `.preference(key:value:)` reduction (`976b12ac`, 143), settled `.onPreferenceChange` (`0d7fe2f3`, 144), & Toggle `.labelsHidden()` (`9060345a6e757fe18208683a536d9fbd98be01aa`, 147). Every observed suite had zero failures; all original 113 compatibility tests remained green.

Final runtime subtree at 04 commit: `a9758090d0ecfc3487ca11468bd30f493e50f08d`. Worker staged suites ran in private build copy `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/preferences/rebased-976b12ac/stages/`; 03 & 04 ran against post-02 base `976b12ac7404834f1eea8f0db07589b0295c53cf`.

Patch SHA-256: 01 `5931549382932259eaff5f7564d9d967c4b2475167b18f912546f01fb745a6a3`; 02 `2a54782b06ed7e4b7535fef0d68138ee4edfcf7c3b0cb657a62c0b52bbdf0e84`; 03 `f449501cf2d21a5d7168856de5e2d33e1e2daf7ca564321c191798660156cd32`; 04 `ed00373bbcbabf775b3b8a181a90eebdfb77974149b69fc56072f78a076e2d94`.

Current runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` has subtree `85dce315a6fb89a9c2749dbb0885f7c19e97dd6a`; all 175 Mac tests pass. `displayScale` exposes source environment values; actual device-scale injection remains provider work. Toggle style supplies marker/metadata support; custom style bodies remain outside this partial API. Shape/font additions use immutable value-equal optional storage, preserving allocation-free legacy constructors. Font retains synthesized equality/hash semantics, including optional discriminants; retained-snapshot & cache regressions pass.

[Fresh Windows compiler-only build](../native/windows/module-provenance/independent-final-actual-review.json) independently binds unchanged `37429120` source to actual compiler/process observations & exact archived module outputs. Natural build exit is zero; 27 verifier controls pass. [Final archive](../native/windows/completed-module-origin-freeze-v2-20261011.json) preserves all earlier failed controls & original timestamp rejection. Existing test & fixed81 receipts retain their original provenance.

Windows release builds through `bbceb5a1` pass. Its 171-test run retains typing 2.5633ms≥2ms & scroll 4.2643ms≥4ms assertions; 170 tests pass. [Paired cached timing](../native/windows/api-shape-bbceb5a1-20261011/cached-paired-analysis.json) retains eight actual runs. Three nonwarm median typing/scroll/row-edit times change from `67b841fb` 4.4046/5.7334/4.7238ms to `bbceb5a1` 2.8682/4.8684/4.2885ms. Every nonwarm pair improves all three metrics; warmups do not universally improve. [Interpretation correction](../native/windows/postshape-timing-interpretation-corrigendum-20261011.json) preserves original analysis bytes. CPU varies 26–72%; measurements do not prove causation. Windows `37429120` release build passes; full 175 retains two performance assertions plus original TaskIDTests.testSameIdDoesNotRestartTask empty-result failure. Ten unchanged-binary processes retain three isolated TaskID failures: two postshape & one font-storage; all four class processes pass. Five cached original-runtime controls pass. Identical test/lifecycle source bytes & process receipts remain archived. [Nine message-only diagnostic processes](task-id-investigation/trace-results/independent-observed-results.json) retain one original-runtime & one postshape failure, both with only “start a” at assertion time. Seven pass; original failure bytes stay preserved. No lifetime, scheduler or font-only cause is established. Eight font/postshape cached timings retain every failed threshold attempt; nonwarm medians are 4.1808/7.0258/4.5396ms → 3.6921/5.2359/4.2900ms. One pair slows all metrics; two improve. Original test bytes & 2/4/15ms thresholds stay unchanged.

Frozen `8e47b89` Windows reference remains separate. All ten unchanged Windows pilot declarations & GUI hosts compile/link, including custom Layout with `layoutDirection`. Fresh corrected81 checks meet 72 positive compile expectations & nine invalid-member failure expectations; old import failures remain archived. Flexible-frame min/max sizing, alignment & Spacer bounds have 14 regressions; malformed bounds use conservative finite headless normalization. `idealWidth`/`idealHeight` & native Layout parity remain separate. New provider qualification follows tuple10 closure; every historical archive retains its original binding.
| Mirror child frames under rightToLeft layoutDirection (SwiftUI semantics) | `ef9e5b35` | 190 (Windows 197) |
| SF Symbol layout metrics for `Image(systemName:)` (ink box, aspect-fit, device-pixel calibration; `Graph.imageFitIntrinsicSize`) | `599e9a26` | 211 (Windows 218) |
