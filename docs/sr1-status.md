# SR1 status: 13 October 2026, evening

Since the 09:21 pause, the session "swiftright-87" has owned SR1 under Adrian's grant (`docs/sr1-decisions.md`). All five original blocks pass their gates on **one product build**: runtime, bridge and the new `packages/SwiftRightHost`, staged as `d124fbe94-bc0c222d`, with factory renderer 0.7 `82513ae0…`. Captures run in the minimised Windows Sandbox (`factory/tools/sandbox/`) through `factory/tools/pair.py`. An independent review is pending on the closure of its first-round caveats.

| Block | Case (under `factory/pipeline/pilot-delivery-five-v1/`) | N | Verdict |
|---|---|---|---|
| Custom Layout LTR | `stack-layout/custom-layout-host-v2/light-centered-execution-v4` | 20 | 20 exact |
| Custom Layout RTL | `stack-layout/custom-layout-host-v2/rtl-original-execution-v1` | 20 | 20 exact (runtime RTL mirroring `ef9e5b35`) |
| RoundedRectangle continuous stroke | `text-shape-image/rounded-stroke-host-v1/continuous-geometry-delivery-v2` (+4 `gen-*` variants, N=3) | 20 | 20 edge-aa≤32 (max 9); variants all pass |
| ZStack + overlay (body font) | `stack-layout/stack-overlay-centered-execution-v9` | 20 | 20 edge-aa≤32 outside the named `+` glyph region (decision 2) |
| Text, bundled Tinos + lineLimit | `text-shape-image/bundled-font-readiness-v6-line-limit-host` | 20 | 20 exact-with-exclusions; text gate 20/20 (ink within 1 px, baseline equal) via ABI 0.7 font registration |
| Image `star.fill` | `text-shape-image/image-system-star-fill-v10` (+16pt and 120x60 N=3; 48pt N=3 via a measured override, which is not evidence of generalisation) | 20 | frame, ink bbox and tint 20/20; glyph shape reported (decision 3) |
| ScrollView (block 6), vertical, offset 0 | `blocks-6-10/scroll-view/vertical-offset0-v1` (`factory/pipeline/`; five colour rows, content 200 pt in a 120x100 viewport, indicators off) | 20 | 20 exact |
| ScrollView, `defaultScrollAnchor(.bottom)` | `blocks-6-10/scroll-view/vertical-bottom-anchor-v1` (programmatic initial offset; `ScrollViewReader`/`scrollPosition` do not exist in the runtime) | 20 | 20 exact |
| ScrollView, horizontal axis | `blocks-6-10/scroll-view/horizontal-axis-v1` | 20 | 20 exact |
| ScrollView, rows of Text (the recipe witness) on a yellow viewport backdrop | `blocks-6-10/scroll-view/vertical-text-rows-v1` | 20 | 20 exact-with-exclusions: only the named row-glyph region (decision 2) differs; clipped ink ends at the viewport bottom on both sides |
| PreferenceKey (block 10), custom `reduce` (max and sum) rendered by the observing parent | `blocks-6-10/preference-key/reduce-max-sum-v1` | 20 | 20 exact |
| PreferenceKey, nil-literal `defaultValue`, first contribution wins, no-contributor default | `blocks-6-10/preference-key/nil-default-first-wins-v1` | 20 | 20 exact |

Tests on the same build: Windows runtime 224, bridge 48, host 35; Mac runtime 216, bridge 48, host 35; 0 failures on either host.

Blocks 6 (ScrollView) and 10 (PreferenceKey) were captured on product stage `0a47f28e7-94d4c4b6` (renderer 0.7 `82513ae0…`, same Sandbox loop, Mac side: offscreen `NSHostingView.cacheDisplay` at scale 2.5 because `ImageRenderer` renders ScrollView blank). Product changes behind them: ScrollView viewport clip in the host paint path (`4a2891c35`), `View.defaultScrollAnchor` (`e2a953403`), nil-literal `PreferenceKey.defaultValue` and the first `onPreferenceChange` delivery of the default value (`a3d47453c`), composite user views in the paint path (`0a47f28e7`). Suites: Windows runtime 242 and host 54 on stage `0a47f28e7`, bridge 51 (1 skipped) on stage `031478e48` (the `0a47f28e7` bridge run had one failure in the W08 `RepairGuardTests.testEmbeddedScriptMatchesSourceFile`, caused by that commit pair predating the guard file rename; not part of these blocks); Mac runtime 245, bridge 52, host 63 on the working tree. 0 failures in the runs reported except that one.

**Known gaps:**
- SliceApp's own backend does not yet use `ResolvedNodePainter`.
- Per-case provenance files (`source-bindings.json`, `plan.json`) describe the old host sources.
- 41 symbol sizes use measured ink overrides.
- Hairline strokes below 1.5 px and scales 1.25 and 1.5 are untested.

**Next:** scale to 10 blocks, then 20, using the same loop.

---

# Earlier checkpoint (09:21, before the handover)

# SR0/SR1 delivery status — 13 October 2026

Recorded after Adrian requested stop & full summary. Work is **paused by user**; both workers stopped, review heartbeat paused. No new implementation, compiler or native dispatch follows this checkpoint. Last owned archive completed at 09:13:58 IST; read-only Dell check at 09:16:58 IST found lock `free`, no Swift/C++ compiler or factory native processes, & three active stages. [Stop evidence](../factory/pipeline/pilot-delivery-five-v1/root-execution/stopped-20261013-0918-ist/dell-state/transport.json.stdout.bin).

**Outcome: SR0 remains OPEN. SR1 original-five milestone is unfinished. One original Custom Layout selected case works & has 20 exact paired observations; no whole original block has completed all recipe/channel obligations. Ten & twenty total have not started.** Rectangle is supporting shape evidence; it does not replace RoundedRectangle or another original pilot.

## What SR0 proved & what remains

Same Swift source compiles against Apple SwiftUI on Mac & SwiftRight on Windows. Tuple11 supplies last qualified baseline: bridge smoke 40/40 & timeout smoke 41/41, rendered-output/text/modal evidence, workload measurements, cross-platform slice observations & package results. This establishes feasibility on bounded slice; it does not establish every SwiftUI feature or a completed release.

[SR0 owner status](sr0-status.md) remains authoritative. Tuple12 candidate renderer & StartupGuard fixture builds passed; fresh Windows F1×20 plus qualified Mac F1×20 have a paired semantic PASS, with timing observational. Remaining tuple12 work includes full 16-configuration matrix, remaining native checks, displayed-workload comparison, packaging/requalification & final runner/freeze. W08 interrupted MSIX update still needs upstream repair proof; Narrator listening is deferred by Adrian. Contract is not frozen. Historical tuple11 observations are retained, not renamed into tuple12 passes.

Factory binds its own hash-verified tuple11 renderer `E280F4A9…CCC93`, ABI0.6 & additive runtime commits. It does not read retired r09 paths. General renderer/ABI edits & protected SR0 trees remain held; candidate block implementation through existing APIs continues independently when resumed.

## Original five: actual delivery state

| Original block | Verified result | Remaining work | Evidence |
|---|---|---|---|
| Rectangle/RoundedRectangle fill/stroke | Rectangle fill has exact full-client paired20 evidence. Original continuous Rounded stroke's earlier circular approximation differs by 572 pixels. New reusable continuous geometry/RGBA API passes 6/6 tests on each host; corrected original Windows host prebuild succeeded. | Final build binding & native capture of new continuous implementation; compare actual stroke/antialiasing, then repair reusable behavior. Full shape block remains unfinished. | [Rectangle full-client pair](../factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-capture-count20-r1/paired-comparison-v1.json), [old Rounded difference](../factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-stroke-native-capture-r16/first-pixel-comparison.json), [new Windows compile](../factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-stroke-boundary-compile-r4/actual-prebuild-r1/observation.json) |
| Image / `star.fill` | Original v10 Windows capture completes with natural exit, sealed streams & released lock. Upright aspect-fit output reduces whole800×600 RGB differences from 2,298 to 767. Current provider is explicitly Segoe Fluent Icons substitute. | Matching original symbol asset/provider behavior. Shape/coverage mismatch remains; do not repeat known failure twenty times or rename substitute into parity. | [Actual comparison](../factory/pipeline/pilot-delivery-five-v1/root-execution/image-native-capture-r7/original-image-comparison-r1.json), [raw coordinator](../factory/pipeline/pilot-delivery-five-v1/root-execution/image-native-capture-r7/actual-native-r1/files/control-count1-r7/coordinator.json) |
| ZStack + overlay | Original blue, size & bounds match; previous whole-client pair retains 307 differing glyph pixels. New host uses reusable actual-DPI Windows body-font resolver; compile request ready. | Build/capture successor & compare. Mac-versus-Windows default-font policy remains unresolved; no per-case font constant or silent edge tolerance. | [Previous actual pair](../factory/pipeline/pilot-delivery-five-v1/root-execution/stack-overlay-native-capture-r3/first-pixel-comparison-v1.json), [successor request](../factory/pipeline/pilot-delivery-five-v1/root-execution/stack-overlay-colors-compile-r5/plan-prebuild-v4.json) |
| Text with bundled Tinos + lineLimit | Source, exact font bytes, private DirectWrite/GDI controls & bounded single-line ellipsis are prepared. Original renderer selection & final host capture remain unproven. | Execute prepared original host & bounded temporary session-registration visibility probe. If existing renderer cannot select exact resource, protected font-loading/ABI integration is needed. Bitmap substitution cannot satisfy original Text shaping/lineLimit semantics. | [Host candidate](../factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host/README.md), [provider investigation](../factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host/font-provider-investigation-v1.md), [unexecuted probe](../factory/pipeline/pilot-delivery-five-v1/root-execution/font-visibility-probe-r1/request.json) |
| Custom Layout | Original two-child LTR witness matches all800×600 RGB pixels in 20 Mac/Windows pairs; all Windows exits/streams/lock cleanup complete. Fresh original RTL Mac Count1 is also captured. | Windows RTL pair & other actual recipe/channel obligations. One selected case is delivered; full block is not promoted. | [20 exact pairs](../factory/pipeline/pilot-delivery-five-v1/root-execution/custom-layout-native-capture-count20-r6/original-custom-layout-comparison-r1.json), [comparison method](../factory/pipeline/pilot-delivery-five-v1/root-execution/custom-layout-native-capture-count20-r6/comparison-method-r1.json), [fresh RTL Mac observation](../factory/pipeline/pilot-delivery-five-v1/root-execution/custom-layout-original-rtl-mac-count1-r1/observe-r1/observation.json) |

## Product implementation completed

[Additive API ledger](../factory/runtime-additions/RESULT.md) records separate tested commits for Rectangle, RoundedRectangle, Circle, ZStack/overlay, frame/padding, Image resizing/aspect-fit, system/custom font metadata, lineLimit, native Layout geometry bridge, scroll axes, preferences & environment support. These are real runtime additions; native rendering support is reported separately.

Recent reusable APIs: Windows system-image glyph coverage/orientation/tint/aspect-fit (`cbb45385`), actual-DPI body-font profile (`06929cf6`), continuous rounded geometry/RGBA stroke (`56dc5838`). Exact matched API6 source passed Windows187/187 & Mac180/180. Rounded's later six tests pass on both hosts; no new combined full-suite total is claimed. Existing timing assertions were unchanged. Earlier timing/TaskID failures remain archived; no established cause or blanket repeatability guarantee follows from one passing suite.

[Windows full-suite raw bytes](../factory/pipeline/pilot-delivery-five-v1/root-execution/image-runtime-api-windows-r1/actual-full-r8/transport.json.stdout.bin), [matched Mac raw bytes](../factory/pipeline/pilot-delivery-five-v1/root-execution/image-runtime-api-windows-r1/actual-mac-api6-release-r6/stdout.bin), [Rounded Mac result](../factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-runtime-api-mac-r1/summary.json), [Rounded Windows raw bytes](../factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-runtime-api-windows-r1/actual-tests-r1/transport.json.stdout.bin).

## Factory work completed

| Area | What exists | Practical limit |
|---|---|---|
| F1 catalogue | SDK symbol graphs, interface/compiler cross-reference, reviewed public-source candidate: 111,576 inventory symbols, including 3,304 appended compiler USRs | Pinned SDK scope; catalogue membership is not implementation |
| F2–F4 | Registry: 10 blocks/65 selectors; 10 candidate recipes, deterministic seeded expansion, same-source probe generation, fixed81 checks:72 valid positives &9 intended negatives | Recipes remain candidates; compile success is not native delivery |
| F5–F7 | Mac host capture, Windows UIA/PrintWindow capture, source/compile/raw archive reader & supervised background hosts | VM permissions remain later; missing capture channels stay visible |
| F8–F9 | Semantic comparison, separate bounded timing controls, actual whole-client pixel comparisons & side-by-side reports | Native timing/provider calibration & complete original-case coverage unfinished |
| F10–F11 | Seeded gate, production archive-byte reader, dependency-aware queue | Gate is not fully qualified for unattended promotion; queue remains staged, no mass rollout |
| F12 | Shell journey inventory & 107-demand mapping; v6 retains5 unresolved &3 ambiguous residual rows | No full-demand resolution or shell completion claim |

Entry points: [catalogue](../factory/catalogue/README.md), [registry](../factory/registry/README.md), [recipes](../factory/recipes/README.md), [pipeline](../factory/pipeline/README.md), [demand mapping](../factory/shell/extended-demand-mapping-v6/README.md). Earlier padding/disabled/scroll/preference captures remain useful separate evidence; they do not replace original five. No golden promotion or full SwiftUI parity is claimed.

## Corrections & review accountability

Nine completed fresh Fable/max reviews are archived through R12; two quota failures & one supervised RSS-limit failure have no completed verdict. Latest review completed 08:23:38 IST on13October, verdict at-risk. [Review ledger](../factory/reviews/fable-max-checkpoint-v1/checkpoint-ledger.json) & [R12 reconciliation](../factory/reviews/fable-max-checkpoint-v1/reconciliation-r12.md) preserve exact model/effort requests, objective/prompt/input hashes, findings & corrections.

Material accepted corrections: stop replacing implementation with receipt machinery; preserve original witnesses; stop counting one-child Custom or circular Rounded substitutes as original completion; fix shared semantic palette/stroke expansion, Image orientation/fit, lineLimit ellipsis & closing lifecycle; separate useful paired observations from full certification; remove invented universal paired20/full-suite-green capture gates. Reviewer mistakes were also rejected using source evidence, including incorrect circular-default claim & stale Custom source readings. No reviewer granted new permission, font policy or pixel tolerance.

Root mistakes after R12 remain visible: missing Image mapping beside actual executable, stale Rounded Package.swift runtime dependency, failed finalizer Python environment & stale resource destination metadata. Successor fixes preserve failed raw evidence. Existing compile helper now checks actual Package.swift dependency against runtime receipt; Image resource deployment derives destination from actual compiler receipt. Current Image runtime already resamples full glyph coverage into target, so worker's stale-v6 clipping diagnosis was rejected rather than implemented.

## Holds & next work on explicit resume

1. Finish Rounded final binding/native pair; build/capture Stack successor & Custom RTL; execute original Tinos host plus prepared visibility probe. These are ready work, not SR0-closure blockers.
2. Resolve Image symbol match, actual continuous stroke residuals & default-font differences through reusable product implementation. Fix observed failures before scaling to10, then20 total.
3. Renderer/ABI0.7, exact bundled-font resource integration if needed, settled-ready metrics guarantees & additional provider/layout/timing exports remain behind protected boundary. Proposal exists under `factory/abi/`; frozen qualification requires recorded SR0 closure.
4. Complete seeded/native channel calibration, remaining recipe cases, trusted rebuild, acceptance review & golden promotion before unattended broad rollout. No universal certification gate prevents candidate implementation.
5. SR0 tuple12 matrix/native/workload/package/W08/freeze work remains distinct from factory block delivery.

Workspaces: terminal Dell stages moved into ignored repo folders by same-volume Move-Item; none deleted over SSH. Current active stages are Custom, Rectangle & Rounded. New Mac native execution uses internal scratch, no permission prompts. Nativehost compiler cap1GiB, full runtime Windows test cap2GiB, controllers128/256MiB; recent owned jobs quiescent. Fable quota failure policy persists: record failure/reset & continue authorized work. Current pause is Adrian's stop request.
