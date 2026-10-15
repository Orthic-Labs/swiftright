# SwiftRight prior art survey

Fetched and dated 15 October 2026. Author: Alchemist (research route), for Adrian's question "how thoroughly have we looked at existing products attempting what we're doing?"

## 0. The honest answer, and what changed today

Before this document, SwiftRight had examined exactly two prior products in depth. The first was SwiftCrossUI, which was source-assessed and then forked and disqualified as a runtime seed in SR0 (`docs/sr0-findings.md:120` and `:286`, probes under `probes/sr0-s/`). The second was WinUI with C# or the swift-winrt chain, which an adversarial review rejected and GPUI replaced (`docs/sr0-findings.md:286`, `docs/architecture-review.md:12-28`). `docs/architecture.md` §2 also mentions Tokamak, OpenSwiftUI and Slint in one paragraph each, but with no recorded test of what they had measured or specified. That is a thin survey for a project whose core claim is parity with a moving Apple target.

This survey fills the gap using public sources only. Nothing was cloned or built. Evidence was gathered with the GitHub API and raw file fetches, with page fetches for non-GitHub sources, all on 15 October 2026. Where a claim comes from a search snippet or from a secondary blog it is labelled as such, and anything with no fetched source is labelled **(unverified)**. The research route receipt for the first three sources (OpenSwiftUI README, swift-cross-ui issue 789, the swift.org Windows workgroup post) is `research-6614a182ec306f66`. The `legion research` route accepted those records and returned `status: ok`; the remaining sources below were fetched as direct reads and are cited inline.

Three findings matter more than the rest:

1. OpenSwiftUI is not a runtime SwiftRight can adopt, but it is the first source that proves a method SwiftRight has been building alone: running the same Swift test source against real SwiftUI on a Mac and against a reimplementation. Its dual-compiled test suite is reusable as a source of cases under the MIT licence (section 1).
2. SwiftCrossUI's main branch has not moved since SR0's fork base. The fork was taken at `0f3ec3958b79`, which is both tag `v0.10.0` and the head of `main` today. Issue 789 is open and has a clear root cause that points at the same wrapper layer SR0 found impossible to repair (section 2).
3. Two independent projects (Flutter and Avalonia) still run Windows text input through the legacy IMM32 path and carry open Korean, Japanese and reconversion defects. That supports SwiftRight's TSF `TextStore` direction and supplies concrete IME cases (section 7).

## 1. OpenSwiftUI (priority)

**What it is.** OpenSwiftUI is an MIT-licensed open-source reimplementation of SwiftUI (`github.com/OpenSwiftUIProject/OpenSwiftUI`). Its README states two purposes: building GUI apps on non-Apple platforms such as Linux and Windows, and diagnosing SwiftUI issues on Apple platforms. It also says the project is "in early development" and warns that "this package use a lot of hidden API and private framework on Apple platform" and must not go into App Store builds. It sits on top of OpenAttributeGraph (C++ reimplementation of Apple's private AttributeGraph, MIT, `github.com/OpenSwiftUIProject/OpenAttributeGraph`, README says it powers "the underlying computing and diffing") and, as an alternative backend, `OpenSwiftUIProject/Compute` ("A reimplementation of the AttributeGraph framework", MIT). The `OpenGraph` name redirects to OpenAttributeGraph.

**Status and activity at fetch.** The main repository was last pushed on 14 October 2026, has 2,497 stars and 28 open issues. OpenAttributeGraph was last pushed 28 September 2026 and Compute on 11 October 2026. The suggested toolchain is Swift 6.3.3 with Xcode 26.6. The README platform table gives macOS and iOS builds with tests, Ubuntu 22.04 only with a "stdout renderer" (no Linux UI integration), and states Windows and Android as "Not supported yet" with no CI. Open issues 593 to 596 track Android. The README note says "The cross-platform OpenAttributeGraph is not fully implemented", and "Non-Darwin text layout is not supported yet". `Docs/SwiftUICompatibilityGaps.md` (last updated 24 September 2026) lists complex `Path` and shape geometry, the gradient and shape style system, non-Darwin text and font resolution, and material and tint resolution as the large remaining gaps.

**How it verifies itself.** `Docs/Status.md` defines a two-axis status. Coverage is Empty, Partial, Blocked or Complete. Verification is Verified ("implementation confirmed against reference binary"), Generated or Stubbed, and "Complete implies Verified". Each source file carries a header such as "Audited for 6.5.4, Status: Complete, ID: 00690F48... (SwiftUICore)" (seen in `Sources/OpenSwiftUICore/Layout/Stack/StackLayout.swift`). I fetched the first twelve lines of all 638 Swift files under `Sources/OpenSwiftUICore` (the Protobuf folder excluded). Of those, 545 are marked "Status: Complete" with a handful of "Complete" variants, 33 are WIP, 7 are Empty and about 20 are blocked on a named dependency; 21 files carry no status. Non-Complete files cluster in View (22), Graphic (11), Render (9), Shape (8). Layout has one, Animation two, Data four. The audit baseline is mostly SwiftUI "6.5.4" (461 files) and "6.0.87" (106 files); `Status.md` says 6.5.4 corresponds to the Xcode 16.4 SDK. SwiftRight's Mac oracle is macOS 27. So the specification is at least two OS generations behind SwiftRight's oracle. These status headers are self-reported and I did not check any of them against a Mac.

**What it has captured, by the areas you named.** All paths are under `Sources/OpenSwiftUICore/` at the fetch date.

- *Layout proposals.* The `Layout` folder has 65 files: `Layout.swift`, `LayoutComputer`, `LayoutProxy`, `Stack/StackLayout.swift`, `FixedSizeLayout`, `AspectRatioLayout`, `SafeAreaInsets`, `PlacementContext`, `SpacingLayout`, `Alignment`, `LazyContainer`. Tests live in `Tests/OpenSwiftUICoreTests/Layout` (`ProposedSizeTests`, `AlignmentGuideTests`, `FrameLayoutTests`, `SpacingTests`, `ViewSpacingTests`, `LayoutTraitsTests`, `SafeAreaInsetsTests`, `ScrollGeometryTests`). One file in the folder is not Complete.
- *View identity and diffing.* `View/Graph/ViewGraph.swift`, `View/Input/ViewList.swift`, `Data/DynamicProperty` (including `ChangedBodyProperty`), and dual-compiled tests `IDViewCompatibilityTests`, `AnyViewCompatibilityTests`, `EquatableViewCompatibilityTests`, `IdentifiedViewTreeCompatibilityTests`, `IdentifiedViewProxyCompatibilityTests`. One fetched test asserts that `onAppear` fires again when `.id(_)` changes if the `id` modifier is applied after `onAppear`, and does not when it is applied before. That is exactly the identity and teardown semantics in `docs/architecture.md` §5 ("Removal, ... reinsertion or ID change follows the pinned Mac fixture's teardown/reset behavior").
- *Dependency graph and invalidation.* The `Graph` folder in OpenSwiftUICore is five files, and the graph engine itself lives in OpenAttributeGraph (C++) and Compute. On Apple platforms the default `OpenAttributeGraphShims` backend uses Apple's private AttributeGraph (README of OpenAttributeGraph). SwiftRight's runtime uses stdlib Observation instead, so this layer is not a drop-in. It is useful only as a statement of which body re-evaluates on which change.
- *Animation and transactions.* The `Animation` folder has 57 files, including `Transaction/Transaction.swift`, `TransactionModifier`, the full `Animation` family, transitions and the `Spring` types. The spring implementation is credited to the separate MIT project Respring (`CREDITS.md`). The compatibility tests include `AnimationCompatibilityTests` and `AnimationCompletionCompatibilityTests`.
- *Environment.* `Data/Environment` (`EnvironmentValues`, `EnvironmentKeyWritingModifier`, `EnvironmentKeyTransformModifier`, `CachedEnvironment`) with dual-compiled tests `EnvironmentValuesCompatibilityTests`, the two key-modifier tests and `Environment+ObservableCompatibilityTests`.
- *Preference keys.* `Data/Preference` (`PreferenceKey`, `PreferenceCombiner`, `PreferenceList`, writing, transform and action modifiers). The compatibility test directory listing I fetched contains no preference-key test, so I could not confirm that preference semantics were checked against Apple SwiftUI (unverified).
- *Text.* Text is built on CoreText (`View/Text/Font/CoreText+Private.swift`, `CoreFont`, `TextStyle`) and works on Darwin only. It offers nothing for Windows shaping, line breaking or IME.

**Reusable as a specification?** Partly, with limits.

- *As test cases and a test oracle: yes.* `Tests/OpenSwiftUICompatibilityTests` has 34 files whose README says the public API is tested "against with SwiftUI on Apple Platform" by switching one `#if OPENSWIFTUI import OpenSwiftUI #else import SwiftUI` line. A second suite, `OpenSwiftUISymbolDualTests`, calls non-public SwiftUI symbols through a `SymbolLocator` stub. These tests are behaviour written in public API, validated on real SwiftUI, and cover lifecycle (`onAppear`, `task`, value-change actions), `@State`, bindings, environment, identity and animation completion. That is the same dual-run discipline as `docs/architecture.md` AD5. Their harness (`triggerLayoutWithWindow` with `PlatformHostingController`) needs UIKit or AppKit, so SwiftRight would port the view bodies and expectations, not the harness.
- *As a layout or identity specification: only as hypotheses.* The source is derived from reverse engineering of Apple's binaries (the `ID:` hash names `SwiftUICore`, and `Status.md` speaks of confirmation "against reference binary"). It is audited against an older SDK than SwiftRight's oracle. SwiftRight's own rule, "macOS is the oracle", means any OpenSwiftUI behaviour must be re-measured on the pinned Mac before it is accepted.
- *As code: not recommended.* Technically it is MIT, and the SwiftRight repository is public, so copying with attribution is licence-compatible. Two cautions apply. `CREDITS.md` says part of its header files come from Apple Open Source "which is licensed under APSL", so those headers are not MIT. The code's provenance from binary analysis is a legal and trust risk I cannot assess from public sources, so I recommend against importing source into a product SwiftRight ships. The SwiftRight repository also has no root `LICENSE` file, so I could not check SwiftRight's own outbound licence (unverified).

**What it solved that SwiftRight still has open.** A much larger inventory of SwiftUI value types and modifiers than SwiftRight's current inventory, 146 core unit test files, and a working pattern for running one test source on both implementations.

**What failed or is missing.** No Windows support or CI; no non-Darwin text; an incomplete cross-platform graph; reliance on private Apple API; and a stated "learning and research" posture.

**Action: adopt as a spec reference and add test cases.** Adopt `Tests/OpenSwiftUICompatibilityTests` and the layout tests as a seed list for SwiftRight Mac-recorded cases, starting with the identity and lifecycle files named above. Port the view bodies, record the expectation on the pinned Mac, and replay on Windows. Do not import OpenSwiftUI source. Re-check status annotations before trusting them. Revisit if OpenSwiftUI gains a Windows renderer (open issues 593-596 track Android only).

## 2. SwiftCrossUI

**What it is.** A SwiftUI-like (not SwiftUI-compatible) cross-platform framework, MIT licensed, `github.com/moreSwift/swift-cross-ui`. Its README says it "does not attempt to replicate SwiftUI's API perfectly".

**Status and activity at fetch.** 1,776 stars, 219 open issues. The last push was 30 September 2026. Releases are v0.7.0 (3 June), v0.8.0 (2 July), v0.9.0 (19 August) and v0.10.0 (30 September 2026). The head of `main` is `0f3ec3958b79` dated 21 September 2026, and tag v0.10.0 points at the same commit. SR0's fork base was this same SHA (`probes/sr0-s/scui-fork/RESULT.md:8`). Since the fork nothing has landed upstream. v0.10.0's headline is `@Observable` support (PR 526), plus Windows fixes and backend refactors. Sources include backends for AppKit, UIKit, Android, WinUI, GTK 4, GTK 3, Curses, Qt and LVGL, plus `_SwiftCrossUIPortingKit`. The README rates AppKit as "Supports all SwiftCrossUI features" and the others as "most". Its LLM policy (`LLM_POLICY.md`) restricts generated contributions, which matters if SwiftRight ever upstreams agent-written patches.

**Windows backend state.** Open issue 787 (25 September 2026) reports that UI Automation clients such as Narrator crash the app inside `Microsoft.UI.Xaml.dll` when a window contains `List`, `NavigationSplitView`, `ScrollView` or `TextField`. The reporter links it to the open WinUI bug `microsoft/microsoft-ui-xaml#11028` (a null dereference during automation-peer walks of controls built in code), and notes that non-crashing windows expose only one UI Automation element. Open issue 707 (August 2026) proposes a future Win32 backend. Issue 204 and 470 (update WinUI, regenerate bindings) remain open. The Browser Company's `swift-winui` and `swift-winrt` lineage is covered in section 5. This independently re-confirms the reason SwiftRight left the WinUI path (`docs/sr0-findings.md` section 4, item 1), now with a date.

**Issue 789: root cause.** The title is "Index out of range crash when `View`'s body ends with `.onHover` or `.onTapGesture`", opened 9 October 2026 and still open with no comments. I read the code at `0f3ec39` to check the reporter's diagnosis, and it holds.

In `Sources/SwiftCrossUI/Views/View.swift`, the default lifecycle for a composite view (one that has a `body`) is asymmetric. `defaultAsWidget` (line 171) creates the widget through a synthetic wrapper: `VStack(content: body).asWidget(children, backend:)`. But `defaultCommit` (line 229) and `defaultComputeLayout` (line 197) forward straight to `body.commit(widget, ...)` and `body.computeLayout(widget, ...)`, passing that VStack-made widget. When `body` is itself a stack, the types coincide and nothing visibly breaks. When `body` is an `OnHoverModifier`, whose own `asWidget` (`Handlers/OnHoverModifier.swift:33-39`) would have called `backend.createHoverTarget(wrapping:)` to build a two-subview container (the child, then the hover target), its `commit` (lines 55-70) calls `backend.updateHoverTarget(widget, ...)` on the VStack's widget instead. AppKit's `updateHoverTarget` (`Sources/AppKitBackend/Features/HoverGestures.swift:35`) does `container.subviews[1] as! NSCustomHoverTarget`, which indexes past the end. Wrapping the body in a `VStack { }` works because the widget shape then matches. Issue 725 (an explicit `return` in `body` opting out of `@ViewBuilder`) is the same defect. Its author names the same three methods and reports that forwarding all three fixes it, though I did not test that fix.

In one sentence: widget creation and widget update are routed through different view types, so a modifier that stores backend state in the widget it creates is handed someone else's widget. I read the AppKit backend and the core; I did not read VStack's widget code or the GTK, UIKit and WinUI `updateHoverTarget` implementations, so the claim that those backends fail identically is **(unverified)**. The reporter says only AppKit crashes at that line.

**Why it matters to SwiftRight.** SwiftRight's SR0 assessment predicted a family of this kind (stale commits, a wrapper layer with no identity of its own; `docs/sr0-findings.md` section 3.1). Issue 789 is a concrete instance where "the view's lifecycle is delegated to a differently typed stand-in". The lesson is not about hover. It is that composite views must be transparent to identity, layout and commit, which SwiftUI guarantees and SwiftRight's fixtures should state outright.

**Draft SwiftRight regression case.** Proposed block `swiftui.gestures` (new), case `body-ends-in-modifier-v1`, following the existing `<block>/<case>-v1` layout and FACTS file convention in `factory/pipeline/blocks-6-10/`. The runtime fork in `probes/sr0-s/scui-fork` is the only place `onHover` and `onTapGesture` exist in this repository today, so the interactive variants are blocked on those modifiers entering the inventory. The structural variants below can be run now with `.padding`, `.frame`, `.opacity`, `.disabled` and `.onAppear` as the terminal modifier.

```swift
// Witness.swift (shared source, Mac and Windows)
struct Leaf: View {                       // body ends in a modifier, no container
    @State private var taps = 0
    var body: some View {
        Text("taps \(taps)")
            .frame(width: 120, height: 40)
            .background(Color.blue)
            .onTapGesture { taps += 1 }   // variant H: .onHover { hovering = $0 }
    }
}
struct LeafExplicitReturn: View {         // issue 725: opts out of @ViewBuilder
    @State private var taps = 0
    var body: some View {
        let t = taps
        return Text("taps \(t)").frame(width: 120, height: 40).onTapGesture { taps += 1 }
    }
}
struct Nested: View { var body: some View { Leaf() } }        // composite of composite
struct Wrapped: View { var body: some View { VStack { Leaf() } } }
struct Witness: View {
    @State private var unrelated = 0
    var body: some View {
        VStack {
            Leaf(); LeafExplicitReturn(); Nested(); Wrapped()
            Button("bump") { unrelated += 1 }
        }
    }
}
```

Stimuli: first commit; pointer click at the centre of each of the four leaves; a click just outside the frame of one leaf; pointer enter and leave over one leaf (variant H); a click on "bump"; a second click on the first leaf.

Assertions, each as a semantic observation rather than pixels: (a) the first commit completes on both platforms (no trap, no empty zero-sized container); (b) the semantic node count, role and bounds of `Leaf` equal those of the same leaf inside `Wrapped`; (c) each centre click adds exactly 1 to that leaf's `taps` and none to the others; the outside click adds 0; (d) the accessibility tree exposes one pressable node per leaf with the same label; (e) after "bump", `taps` is preserved (identity is unchanged by an unrelated state write); (f) `LeafExplicitReturn` is indistinguishable from `Leaf`. Mac N=20 on the pinned runtime per the oracle contract; Windows N=20; the comparator must reject an injected wrong-node tap. Note that decision 2 in `docs/sr1-decisions.md` keeps glyph pixels out of the gate, so the case compares semantics and geometry only.

**Reusable.** The `DummyBackend` idea (record the widget tree instead of drawing) and the Given/When test style are already used by SR0's `TestSinkBackend`. The MIT licence permits reuse with attribution. Core code is not reusable as a runtime (SR0 result).

**Action: ignore as a seed; add test case.** Add the `body-ends-in-modifier-v1` family. Re-run the assessment only if upstream changes its commit and layout passes, and track issues 787 and 789 for evidence about the WinUI UIA chain.

## 3. Skip (skip.tools, now skip.dev)

**What it is.** Skip builds native Android apps from SwiftUI source, either by transpiling Swift to Kotlin and Jetpack Compose ("Lite") or by compiling Swift natively and bridging ("Fuse"). `skiptools/skip` is MPL-2.0; `skip-ui` (the SwiftUI reimplementation on Compose), `skip-unit`, `skip-model`, `skip-lib`, `skip-fuse` and `skip-fuse-ui` are also MPL-2.0.

**Status and activity.** `skip` was pushed 13 October 2026 (3,238 stars); `skip-ui` 14 October 2026, release 1.63.0 on 14 October and 1.62.0 on 9 October 2026 (330 stars). This is the most actively maintained product in the survey.

**Coverage table format.** The `skip-ui` README ends with "Supported SwiftUI", a table with four support levels (full, high, medium, low, shown as check mark, green, yellow and orange circles) and per-API collapsible notes listing exact limitations, for example `@AppStorage`: "Optional values are not supported". It says "Anything not listed here is likely not supported." The format puts a limitation next to each API and has a four-level scale instead of a binary, and it is exactly the kind of published inventory `docs/architecture.md` §1 promises. It is hand-maintained prose in a README, not machine-checked. Whether it is generated or validated by tests I could not determine (unverified).

**Testing approach.** From `skip.dev/docs/testing` (the page carries no date): `skip test` runs the same Swift tests natively on the host and on Android and prints a per-test table with Darwin and Android columns and a percentage, so that "a test that passes on Darwin but fails on Android stands out immediately." Lite modules transpile XCTest and Swift Testing to Kotlin/JUnit on the JVM (under Robolectric on the host JVM, or on an emulator or device for higher fidelity); Fuse modules compile tests natively and support Swift Testing only. Parameterized tests, traits and tags are not yet transpiled for Lite. The page does not cover snapshot or UI tests, so Skip's evidence is behavioural parity, not pixel parity.

**What it solved that SwiftRight has open.** A published, graded support table, a single-command paired pass/fail report, and an actual user base for the "same Swift source, native elsewhere" claim.

**What failed or does not transfer.** Skip targets Android with a mature Compose renderer. It has no Windows target, and its semantics come from mapping to Compose, not from a SwiftUI-semantics runtime.

**Reusable.** The table format and report layout (ideas, not code). Code is MPL-2.0, which is file-level copyleft; I would not mix it into SwiftRight sources.

**Action: borrow the format.** Publish SwiftRight's inventory in Skip's graded form with a limitation note per row, and produce the paired Mac and Windows result table in `pair.py`'s report, with a percentage line.

## 4. Tokamak and Adwaita for Swift

**Tokamak.** `TokamakUI/Tokamak` (Apache-2.0, 2,834 stars) is "SwiftUI-compatible framework for building browser apps with WebAssembly" with DOM, static HTML and GTK renderers. At fetch the repository is flagged archived. The last release is 0.11.1 (29 November 2022) and the last commit on `main` is 4 February 2023; there have been none since 1 March 2023. The repository's last push is 23 March 2024. The README still says it implements "a very basic subset of SwiftUI", and `docs/progress.md` lists views only (three statuses: blank, some features, complete) with no modifiers, layout or lifecycle rows. The archive date and the maintainers' reasons are not stated in anything I fetched, so the architecture document's "archived in January 2026" is **(unverified)**. I found no statement from the maintainers explaining the stall. What the evidence shows is the following.

- Layout was never solved upstream. Pull request 379, "Experiments and hacks attempting to implement SwiftUI-like layout flow", was never merged (last updated 11 April 2022). Its description says layout "should actually reside in `TokamakCore` with only a slim api to the renderer" and calls the code "horrible". The test targets include `TokamakLayoutTests` and `TokamakReconcilerTests`, so a layout engine and reconciler were attempted.
- Open work at the end is feature-by-feature (stack implementation changing from grid to flex, collection property wrappers), not conformance.
- The reasons are my inference: an unbounded API surface with no oracle to say when a view is right, one renderer-by-renderer rewrite per backend, and volunteer capacity. I label this inference **(unverified)**.

**Adwaita for Swift.** A GNOME/libadwaita UI framework with "an API similar to SwiftUI" (its own words: "similar to", not compatible). The GitHub repository `AparokshaUI/adwaita-swift` is archived with the notice "This project has moved", last pushed 17 October 2024, MIT. The live home is `codeberg.org/aparoksha/adwaita-swift`, whose last commit is 3 October 2026 ("Merge pull request 'Improve fullscreen'"); the page shows one tag and does not name the licence, so the current licence is **(unverified)**. It is a wrapper over native GNOME widgets, so it never faced the layout-proposal problem.

**What each solved and failed.** Neither provides a parity oracle or a Windows path. Tokamak's useful artifact is the negative example above. Adwaita shows that a native-widget wrapper with SwiftUI-like syntax stays alive cheaply and gives up parity.

**Action: ignore both** as sources. Record Tokamak's PR 379 as supporting evidence that layout proposals are the stall point, which SwiftRight already counters with a Mac oracle and measured layout cases.

## 5. The Browser Company: Swift on Windows

**What they did.** "Swift, meet WinRT" (Browser Company's Substack "Speaking in Swift", 30 October 2023) says "There is no UI framework for Windows written in Swift", releases Swift/WinRT as an open-source bindings generator, and says WinUI 3 "is what we are using to build Arc on Windows". They did not build a SwiftUI-like layer; the UI layer is WinUI 3 through generated WinRT bindings, built beside their macOS UI. The post does not discuss toolchain pain or whether UI is shared with macOS, so I cannot say what code they shared (unverified).

**Repositories at fetch (GitHub API, 15 October 2026).** `thebrowsercompany/swift-winrt` (BSD-3-Clause, 859 stars) was pushed 2 October 2026, built with a Swift 6.2 release in CI, and "is based on the Microsoft created cppwinrt project". It generates the C ABI and the Swift bindings. `swift-build` ("Swift toolchain builds by The Browser Company") was pushed 13 October 2026 and hosts a symbol server. The pre-built binding repositories `swift-winui`, `swift-windowsappsdk`, `swift-uwp`, `swift-cwinrt` and `swift-windowsfoundation` were all archived on 16 October 2025; the `swift-winui` readme calls itself "an outdated snapshot ... provided for illustration purposes" and tells users to generate bindings with swift-winrt. This matches SwiftRight's own review date for the archived chain (`docs/sr0-findings.md` section 4, item 1). `swift-webdriver` (a Swift client for WebDriver and WinAppDriver UI automation) was last pushed 2 May 2025.

**Status of the product (secondary sources, approximate).** A search result summary (not a primary page; I did not open the underlying articles) says Atlassian agreed in early September 2025 to buy the company for 610 million dollars, with the deal reported closed on 21 October 2025, that Arc entered maintenance mode in May 2025, and that its latest Windows build is dated 22 May 2026. I could not confirm a Windows version of their newer product. Treat all of this as **(unverified)**. It implies that the best-known commercial Swift-on-Windows UI shell is not on an active feature track, though the toolchain work continues, as the repository dates above show.

**Reusable.** swift-winrt (BSD-3-Clause) is reusable for calling Windows APIs from Swift if SwiftRight ever needs a WinRT surface, which today it avoids (the v0.3 decision to "remove WinRT projection ownership", `docs/architecture-review.md:100`). `swift-webdriver` (BSD-3-Clause) is a Swift-native UI Automation client pattern. Their Windows Swift toolchain builds and symbol server are a real alternative when the official toolchain lags.

**Action: borrow tool.** Borrow `swift-webdriver`'s approach, or a direct UIA client, for the out-of-process UIA walk SwiftRight's Windows accessibility gate requires. Otherwise ignore swift-winrt for now.

## 6. Uno Platform and Avalonia

**Uno Platform.** `unoplatform/uno` (Apache-2.0, 10,080 stars) reimplements WinUI APIs on Skia and other renderers. Last push 15 October 2026; release 6.6.184 on 6 August 2026. It has a Win32 runtime host (`src/Uno.UI.Runtime.Win32`).

- *Parity testing.* `src/Uno.UI.RuntimeTests` runs tests inside the real app on each platform (the docs say they are "relatively cheap ... whilst still allowing functionality to be verified across all supported platforms") and a second project file, `Uno.UI.RuntimeTests.Windows.csproj`, sits beside the Skia one, which suggests the same tests also run on actual WinUI as a reference (I did not read how it is used, so this is **(unverified)**). `Uno.UI.TestComparer` compares screenshot test results across runs, and `Uno.ReferenceImplComparer.Tests` compares assemblies against a reference. The helper `SkiaImageAssert.ArePixelsEqual` demands exact pixel equality (it loops over every pixel with no tolerance). The contributor guidelines separate in-process measurement tests from `SamplesApp.UITests` that simulate user input and check final screen output.
- *Accessibility.* `doc/articles/features/accessibility/index.md` says that on Windows (Win32) Skia-rendered apps expose a UI Automation provider tree for Narrator, mirroring a semantic tree kept beside the visual tree, with the same on macOS (VoiceOver) and a hidden ARIA DOM on web. A tested path for screen readers is documented in `testing-with-screen-readers.md`. This matches SwiftRight's AccessKit plan (retained semantic tree beside the paint tree).
- *Text, fonts, images.* Rendering is Skia-based, and `SkiaImageDecoder` in `Uno.UI.Composition.Skia` decodes images through Skia. A custom-fonts guide exists. I did not read how its text pipeline shapes text or how IME works on the Win32 host (unverified).
- *What it solved.* A large WinUI-parity implementation on a custom renderer with a documented UIA path.
- *What does not transfer.* It re-implements WinUI (XAML, C#), a different programming model from SwiftUI, and has no Mac oracle.

**Avalonia.** `AvaloniaUI/Avalonia` (MIT, 31,661 stars). Last push 15 October 2026; release 12.1.4 on 9 October 2026. Its `tests` folder is the best example of tooling SwiftRight could borrow.

- *Cross-toolkit comparison.* `Avalonia.RenderTests.WpfCompare` describes a scene once as a toolkit-neutral `CrossControl` tree and renders it in WPF through `RenderTargetBitmap` into reference PNGs; `Avalonia.Skia.RenderTests` renders the same scene in Avalonia. This is the closest shape to SwiftRight's pairing, but with the roles reversed (one neutral description rendered by two toolkits).
- *Out-of-process input.* `Avalonia.IntegrationTests.Appium` drives a real app through WinAppDriver on Windows and Appium on macOS (readme), including keyboard, pointer, drag-and-drop, menus and window tests, with video recording config.
- *Headless.* `Avalonia.Headless` (with xUnit and NUnit adapters) runs UI logic with no window.
- *Windows text and accessibility.* `src/Windows/Avalonia.Win32/Input/Imm32InputMethod.cs` and `Imm32CaretManager.cs` implement IME through IMM32. Open issues 21948 ("Support Windows IME reconversion via TSF ITfFnReconversion", updated 9 August 2026), 21249 (Japanese reconversion does not work in TextBox, July 2026) and 22168 ("Structured text input: a shared text contract for IME and accessibility", 11 September 2026) show the IMM32 limits. A separate `Avalonia.Win32.Automation` project exposes UI Automation providers by pattern (Value, Toggle, Scroll, Selection, RangeValue, ExpandCollapse). There is also an AT-SPI project for Linux. The text-formatting code is in `Avalonia.Base/Media/TextFormatting` with a `HarfBuzz` source folder.
- *Image decoding.* `Avalonia.Skia/ImmutableBitmap.cs` decodes through `SKBitmap.Decode` and `SKCodec`.
- *What it solved.* UIA pattern coverage per control, a headless unit path and an Appium integration path.
- *What failed.* IMM32 limits: TSF reconversion is still open.

**Reusable.** Uno is Apache-2.0 and Avalonia is MIT; both are .NET, so reuse is of ideas, not code. The neutral-scene-description idea, the Appium input rig and the per-pattern UIA list are the parts to borrow.

**Action: borrow tool and adopt as spec reference.** (1) Use Avalonia's Appium suite structure (one test per control kind and one per input modality) as the shape of SwiftRight's UIA walk and interaction tests. (2) Adopt Avalonia's UIA pattern list as a checklist for `docs/architecture.md` §11's accessibility gate. (3) Keep SwiftRight's exact-RGB `pair.py` gate (it already matches Uno's strict pixel assert) and its edge-AA exception (decision 5).

## 7. Flutter, Compose Multiplatform and React Native Windows (brief)

**Flutter** (BSD-3-Clause, pushed 15 October 2026). Its Windows embedder uses the IMM32 API for text input (`engine/src/flutter/shell/platform/windows/text_input_manager.cc` calls `ImmGetContext`) and a UIA accessibility bridge (`accessibility_bridge_windows.cc`, `flutter_platform_node_delegate_windows.cc`). Open Windows issues as of the fetch date include 189491 (Hangul syllable loss), 191196 (IME composition survives a text-client change and leaks into the next TextField, 17 September 2026), 166400 (Korean to Hanja conversion fails on Windows 10), 74547 (IME reconversion), 192781 (NVDA announces "not selected" on every checkbox and switch because every node is marked selectable), 127125 (a UIA text provider broke Narrator) and 189719 (no proactive UIA notifications). Lesson: IME composition lifecycle across focus changes, Hanja and reconversion, and per-node UIA state flags are where mature custom-drawn stacks still break. I did not find a published performance budget for Windows in what I fetched (unverified).

**Compose Multiplatform** (Apache-2.0, pushed 14 October 2026). Its changelog (sampled up to 100,000 characters of 591,149; the rest unread) shows desktop fixes in the 1.11 to 1.13 range: "[A11y, Windows] Fixed the accessibility hierarchy, allowing NVDA traversal commands to work correctly" (1.11.0, May 2026), a crash in `setComposingRegion` with an inverted or invalid region (1.12.0, August 2026), "Pinyin - Simplified" input leaving composed text uncommitted (1.11.0), and an RTL cursor crash with emoji and combining marks (1.12.0). Lesson: composing-region bounds and bidi cursor positions with combining marks are recurring crash classes.

**React Native Windows** (MIT per its `LICENSE` file; GitHub reports no SPDX id). The new-architecture (Fabric) tracking issues are open: 11898 "Accessibility for Fabric" and 11422 "E2E testing for Fabric" (both December 2025), 11905 "Aria Props on Fabric". The documentation page I fetched did not cover rendering, accessibility or performance, so I draw no performance lesson (unverified). Lesson: even a Microsoft-owned stack had to rebuild accessibility and end-to-end testing when it changed renderer, which is the same cost SwiftRight pays by owning the renderer.

**Action: add test cases.** Convert the failure list above into IME and UIA cases (section 9, actions 3 and 4). Ignore the rest.

## 8. Other projects found

**SwiftOpenUI** (`codelynx/SwiftOpenUI`, MIT, 43 stars, pushed 11 October 2026) was announced on the Swift Forums on 20 March 2026 as "SwiftUI for Linux, Windows and Web -- Still Experimental", rendering through "Win32/Direct2D on Windows" and claiming "~95% feature parity" without saying how it is computed. It has "14 runnable examples with automated screenshot comparison across all four platforms". In the thread the author said most code was written by Claude and reviewed by other models, that no x86 or physical Windows machine was used, and that in September 2026 "the project suspended so just sitting for a while". It is the closest direct competitor in intent (SwiftUI source on Windows with its own renderer), but it has no Mac oracle and its parity figure is unmeasured. **Action: ignore, watch** for a Mac-recorded comparison.

## 9. Apple-side signals

- **Windows Workgroup.** The swift.org post "Announcing the Windows Workgroup" is dated 26 January 2026. Its goal is "to ensure ongoing support for Swift on Windows", enabling Windows application development, improving the official distribution, recommending improvements to Foundation and Dispatch, and recommending "best practices for bridging between Swift and the Windows API". The page does not mention UI frameworks, SwiftUI or Swift Build in connection with the workgroup. A web search found no Apple or Swift.org statement about SwiftUI on Windows in 2026 (search summary, not a primary source). So the working assumption in `docs/architecture.md` §2, "SwiftUI itself remains Apple-only", stands as of this date.
- **Swift Build and SwiftPM.** The `swiftlang/swift-build` README says Swift Build "is the default SwiftPM build system in nightly snapshots of Swift's `main` branches" and that it can be enabled in Swift 6.2 and 6.3 with `--build-system swiftbuild`. SwiftPM's latest release at fetch is `swift-6.4.0-RELEASE` (15 September 2026), and the README text I read does not say whether 6.4 changes the default (unverified). Windows-specific defects are open in both projects, for example SwiftPM issue 322 "Hangs while building with Windows using SwiftPM" (2 August 2026) and swift-build issue 1641 "Windows: Touch task on a bundle directory copies its contents into the working directory" (15 August 2026), with older Windows import-library and linker issues (251, 310, 611) still open. SwiftRight's dispatch-drain probe ran on Swift 6.4.0 (`docs/sr0-findings.md`, "Dispatch drain via libdispatch" row), the same version as the SwiftPM release.
- **AccessKit** (BSD-3-Clause; `accesskit_windows` 0.35.1 released 25 September 2026) is the Windows UI Automation adapter in SwiftRight's chosen composition, so its release cadence is a dependency signal.

## 10. Summary table

| Project | Verdict | Primary action |
|---|---|---|
| OpenSwiftUI | Test oracle seed, not a runtime | Adopt tests as spec reference; add Mac-recorded cases |
| SwiftCrossUI | Already disqualified; upstream unchanged since fork | Add the issue 789 regression family |
| Skip | Best peer on process and reporting | Borrow graded support table and paired report |
| Tokamak, Adwaita | Stalled or wrapper-only | Ignore |
| Browser Company | Toolchain peer, UI is WinUI 3 | Borrow UIA client approach; ignore swift-winrt for now |
| Uno, Avalonia | Closest test tooling | Borrow Appium and UIA pattern checklists |
| Flutter, Compose, RNW | Failure catalogues for IME and UIA | Add IME and UIA cases |
| SwiftOpenUI | Intent competitor, no oracle | Ignore, watch |
| Windows workgroup, Swift Build | No UI statement; build in flux | Keep toolchain pinned |

## 11. Ranked top five actions

1. **Adopt OpenSwiftUI's dual-compiled compatibility tests as a spec reference and seed new Mac-recorded cases (identity first).** Port `IDViewCompatibilityTests`, `AnyView`, `EquatableView`, `IdentifiedViewTree`, `State`, the environment key tests, `TaskModifier`, `ValueActionModifier`, `AppearanceActionModifier` and `AnimationCompletion` view bodies and expectations into SwiftRight's case format, record on the pinned macOS 27 host at N=20, and replay on Windows. Treat any OpenSwiftUI expectation that differs from the Mac measurement as OpenSwiftUI's defect. MIT licence; no source import. This is the largest unreviewed body of already-written SwiftUI behaviour and supports architecture AD5 and AD7.
2. **Add the `body-ends-in-modifier-v1` regression family from issue 789 now.** Run the structural variants today with `.padding`, `.frame`, `.opacity`, `.disabled` and `.onAppear` as the terminal modifier, and add the tap and hover variants when gestures enter the inventory. It is cheap, guards a failure class SR0 already hit, and tests identity transparency of composite views.
3. **Add IME cases from the Flutter, Avalonia and Compose failure lists.** Cover composition committed on focus change (Flutter 191196), Hangul syllable loss, Korean Hanja and Japanese reconversion (Flutter 166400 and 74547, Avalonia 21948 and 21249), an invalid or inverted composing region, and RTL caret movement across combining marks and emoji. Drive them through the existing in-process `TextStore` script (`docs/sr1-decisions.md` B6) and queue the real-IME runs for hardware.
4. **Add a UIA walk of every control kind as an early gate, modelled on SwiftCrossUI issue 787 and Avalonia's Appium suite.** The walk must complete without a crash, expose more than one element per window, and report each node's role, name, value and state flags (Flutter 192781 shows why state flags need checking). Use an out-of-process client; `swift-webdriver` or a direct UIA client are options.
5. **Publish the inventory in Skip's graded-table format and print Skip-style paired Mac and Windows result rows.** Use four support levels with a limitation note per API, and add a per-case Mac and Windows column with a percentage to the `pair.py` report. It makes the parity claim legible to a reader and replaces the single prose status.

## 12. Gaps in this survey

- I did not read OpenSwiftUI's layout code against SwiftUI behaviour, so "Complete" is its own claim, not a finding.
- I did not read the GTK, UIKit or WinUI `updateHoverTarget` implementations or SwiftCrossUI's `VStack` widget code.
- I did not open Uno's or Avalonia's text-shaping code or IME code on Windows beyond the file names and open issues cited.
- No performance-budget source for Flutter, Compose or React Native Windows was found.
- Tokamak's archive date and reasons, Adwaita's current licence, the Browser Company's acquisition status and Arc's current state, and whether Swift 6.4 changes the SwiftPM default build system remain unverified.
- Several sources were summarised by a fetch tool before I read them (the swift.org, Skip testing, Substack, Compose changelog and forum pages). Quotes from those pages come from that summary, so a reader should check wording before quoting externally.

## 13. Sources, all fetched 15 October 2026

- OpenSwiftUI repository, README, `Docs/Status.md`, `Docs/SwiftUICompatibilityGaps.md`, `CREDITS.md`, `Tests/OpenSwiftUICompatibilityTests/` and `Tests/OpenSwiftUISymbolDualTests/` READMEs, `Sources/OpenSwiftUICore` file headers: https://github.com/OpenSwiftUIProject/OpenSwiftUI
- OpenAttributeGraph: https://github.com/OpenSwiftUIProject/OpenAttributeGraph; Compute: https://github.com/OpenSwiftUIProject/Compute
- SwiftCrossUI repository, releases, `View.swift`, `OnHoverModifier.swift`, `AppKitBackend/Features/HoverGestures.swift` at `0f3ec39`: https://github.com/moreSwift/swift-cross-ui ; issues 789, 725, 787, 707: https://github.com/moreSwift/swift-cross-ui/issues/789
- WinUI crash referenced by issue 787: https://github.com/microsoft/microsoft-ui-xaml/issues/11028 (cited as quoted in issue 787; not fetched directly)
- Skip: https://github.com/skiptools/skip-ui (README), https://skip.dev/docs/testing/
- Tokamak: https://github.com/TokamakUI/Tokamak (README, `docs/progress.md`, pull 379)
- Adwaita for Swift: https://github.com/AparokshaUI/adwaita-swift and https://codeberg.org/aparoksha/adwaita-swift
- The Browser Company: https://speakinginswift.substack.com/p/swift-meet-winrt (30 October 2023); https://github.com/thebrowsercompany (swift-winrt, swift-winui, swift-build, swift-webdriver); Atlassian and Arc status from a web search summary only (secondary)
- Uno Platform: https://github.com/unoplatform/uno (`src/Uno.UI.RuntimeTests`, `src/Uno.UI.TestComparer`, `doc/articles/features/accessibility/`); https://platform.uno/docs/articles/uno-development/creating-runtime-tests.html (search summary)
- Avalonia: https://github.com/AvaloniaUI/Avalonia (`tests/Avalonia.RenderTests.WpfCompare`, `tests/Avalonia.IntegrationTests.Appium`, `src/Windows/Avalonia.Win32`, issues 21948, 21249, 22168)
- Flutter: https://github.com/flutter/flutter (`engine/src/flutter/shell/platform/windows`, issues 189491, 191196, 166400, 74547, 127125, 192781, 189719)
- Compose Multiplatform changelog: https://github.com/JetBrains/compose-multiplatform/blob/master/CHANGELOG.md
- React Native Windows: https://github.com/microsoft/react-native-windows (issues 11898, 11422, 11905)
- SwiftOpenUI: https://github.com/codelynx/swiftopenui and https://forums.swift.org/t/swiftui-for-linux-windows-and-web-still-experimental/85463
- Swift Windows Workgroup: https://www.swift.org/blog/announcing-windows-workgroup/ (26 January 2026)
- Swift Build and SwiftPM: https://github.com/swiftlang/swift-build , https://github.com/swiftlang/swift-package-manager (release `swift-6.4.0-RELEASE`, issues 322 and 1641)
- AccessKit: https://github.com/AccessKit/accesskit (release `accesskit_windows-v0.35.1`)
