# SwiftRight architecture review history

Current plan: [v0.5](architecture.md). Historical findings apply to named revisions; [v0.5 dispositions](#v05-sequential-adversarial-review-8-october-2026) include current corrections.

## Original review of v0.1

Reviewed 8 October 2026 against live upstream state. Verdict first, evidence after.

## Verdict

- **Feasible as "shared Swift logic + two native UIs":** yes. Proven by Arc for Windows & by current Swift 6.3 toolchain work.
- **Feasible as written (portable facade over real SwiftUI + SwiftCrossUI WinUI, accessible, packaged, arm64):** unproven & resting on thinner dependencies than §2 claims.
- **Worth doing:** yes for Mac-first products needing Windows parity, provided you accept owning Windows WinRT projections & SwiftCrossUI's Windows backend. Not worth doing as generalized community SDK first.
- **Language bet:** sound. Apple's cross-platform investment is in toolchain (Swift Build default across Linux/Windows, Windows Workgroup Jan 2026, Android workgroup), not in UI. SwiftUI stays Apple-only. UI layer rides on community (SwiftCrossUI, effectively one maintainer) & Browser Company toolchain work.

## Findings ranked by severity

### F1. §2 overstates Windows infrastructure
Doc calls SwiftCrossUI "useful existing Windows infrastructure". Verified state:

| Item | State |
|---|---|
| SwiftCrossUI WinUIBackend dependency | single package `moreSwift/swift-winui` `.upToNextMinor(from: "0.2.2")` |
| Upstream `thebrowsercompany/swift-winui` | archived 16 Oct 2025, pinned Windows App SDK 1.7, x64 only, README calls itself "outdated snapshot ... for illustration" |
| Windows App SDK used by SwiftCrossUI apps | 1.5 runtime per issue #787 repro; 1.7 reportedly out of support since Mar 2026 (third-party claim, verify) |
| `swift-winrt` generator | active (commits 2 Oct 2026), but bindings scripts break on 1.8 NuGet layout; issue #263 open since May 2026, no reply |
| arm64 Windows | no preset in swift-winrt, none in swift-winui |
| SwiftCrossUI Windows tests | no WinUI test target in Package.swift |
| Hot reload | hard-disabled on Windows in Package.swift |
| Accessibility | issue #787 (25 Sep 2026, zero response): UI Automation walk crashes app when window has List, ScrollView, TextField, NavigationSplitView. Simple windows expose one UIA element total. |

Consequence: AD6 "narrow pinned fork only when necessary" is already false. You own projections regeneration, arm64, & a11y fixes from day one. SR0's "accessibility discovery" gate fails today on Windows.

### F2. Facade is the whole project, doc treats it as one workstream
Two choices, both costly:
- **Typealias on Mac** (`SwiftRightUI.View == SwiftUI.View`): keeps real SwiftUI, previews, AppKit escape hatch. But every SwiftUI API compiles on Mac & silently diverges on Windows. Only real lint is Windows CI compile.
- **Wrapper on both**: honest portability, but Mac is no longer "real SwiftUI" at type level; third-party SwiftUI packages & Xcode previews degrade. Contradicts §1.

SwiftCrossUI explicitly refuses SwiftUI API tracking. Modifier return types, result builders, `@Environment` keys, `@FocusState`, `.task`, `.onChange` semantics all need per-API reconciliation. Pick typealias-on-Mac now; make Windows compile the compatibility lint; drop `compatibility-check` tool from v1.

### F3. Observation guidance is off
§6 says avoid Apple-only observation. `Observation` module ships in Swift 6 toolchains on Windows & Linux. Actual conflict: SwiftCrossUI uses `swift-observation-polyfill` for macOS 10.15 back-deploy. Decide: macOS 14+ floor, stdlib `Observation`, upstream or fork flag to drop polyfill.

### F4. Scope sized for SDK company, not founder + AI year
Nine packages, ten services, CLI, compatibility tool, six gates, community release. Cut for v1:
- UpdateService: Sparkle on Mac, MSIX/winget on Windows.
- `tools/swiftright` CLI: Swift Bundler + scripts.
- `compatibility-check`: Windows CI compile.
- Packages: Core, UI, Services + one per platform. Extract more only when second consumer exists.

### F5. Windows performance expectations likely wrong
Doc assumes WebView removal yields wins on both OSes. Windows reality: WebView2 is preinstalled; Swift ships `_FoundationICU.dll` (~37 MB) plus Windows App SDK runtime. Recent spike (ClaudeBar, Oct 2026) measured Swift DLL ~57 MB, full NativeAOT WinUI app ~119 MB, ~112 MB RAM. Expect Mac big win, Windows neutral or worse on package size. Split budgets per OS in §11.

### F6. Threading hazard is real, cite it
Spike found `RunLoop.main` does not drive Swift main dispatch queue on Windows; needed `_dispatch_main_queue_callback_4CF` pumped on 16 ms DispatcherQueue timer. SwiftCrossUI WinUI backend has its own answer; verify in SR0, not assume.

### F7. Packaging gaps
Swift Bundler: generic dir + WiX MSI, no MSIX. Windows App SDK features (notifications, some pickers) want package identity. Decide MSIX or sparse package in SR0. Swift runtime redistribution: Browser Company builds offer static stdlib & SxS manifests; swift.org builds "expected" to follow.

### F8. No kill criteria
Gates define success only. Add exit conditions to SR0 with plan B.

### F9. Swift 6 language mode vs SwiftCrossUI 5.10
SwiftCrossUI manifest is tools-version 5.10. Your Swift 6 strict-concurrency packages will fight its Sendable story at boundary. Budget for it.

### F10. Hidden alternative not weighed
Doc compares against React/Tauri only. Missing option: shared Swift domain logic + SwiftUI Mac + C# WinUI 3 Windows shell over Swift `@c` ABI. Proven today on x64 & arm64, MSIX, NativeAOT, supported Windows App SDK 2.5. Loses shared UI source, gains supported Microsoft stack & zero projection ownership. For utility with under ~10 screens, two thin UIs cost less than facade maintenance across every SwiftUI release. Facade pays only across product line (HeardRight + RustRight dashboard + more).

## Recommended changes

1. Rewrite §2 with table above.
2. SR0 = 4-6 week box: facade vertical slice, UIA tree on Windows with List + TextField, arm64 build, MSIX install on clean VM, own regenerated WinRT projections for Windows App SDK 1.8/2.x committed & reproducible. Kill criteria: a11y crash unresolved, or projections cannot regenerate, or facade needs wrappers on Mac. Plan B: F10 route, or Tauri stays on Windows.
3. Move §9 "ship prebuilt interop artifacts" into SR0 as first deliverable. Nothing else runs without it.
4. Typealias on Mac, Windows compile as lint, macOS 14+ floor, stdlib Observation.
5. Cut per F4.
6. Per-OS budgets per F5.
7. Add arm64 Windows to pinned tuple.
8. Add F10 to doc as explicit rejected or fallback option with reasoning.

## Sources

- SwiftCrossUI manifest & README: https://github.com/moreSwift/swift-cross-ui
- Issue #787 UIA crash: https://github.com/moreSwift/swift-cross-ui/issues/787
- swift-winui archived: https://github.com/thebrowsercompany/swift-winui
- swift-winrt & issue #263: https://github.com/thebrowsercompany/swift-winrt/issues/263
- Windows Workgroup: https://swift.org/blog/announcing-windows-workgroup/
- What's new March 2026 (Swift Build): https://swift.org/blog/whats-new-in-swift-march-2026/
- Browser Company, Swift on Windows year of refinement (Jul 2026): https://speakinginswift.substack.com/p/swift-on-windows-a-year-of-refinement
- Browser Company symbol server & hiring (May 2026): https://speakinginswift.substack.com/p/a-public-symbol-server-for-swift
- C# WinUI over Swift C ABI spike: https://github.com/tddworks/ClaudeBar-Windows/issues/2
- Swift Bundler Windows bundlers: https://github.com/moreSwift/swift-bundler
- Swift Windows install: https://swift.org/install/windows/
- Skip (no Windows target): https://www.infoq.com/news/2026/01/swift-skip-open-sourced

## Addendum: v0.3 decision, 8 October 2026

Second-opinion review (Astra) proposed keeping Apple SwiftUI on Mac, building a SwiftUI-semantics runtime in Swift for Windows, and rendering through GPUI over a C ABI. Accepted with amendments; architecture moved to v0.3.

**Accepted from Astra**
- Drop SwiftCrossUI/WinUI as Windows foundation: removes WinRT projection ownership, archived bindings, and the UIA crash chain entirely.
- GPUI first backend candidate. **Corrected in v0.4:** this review conflated published 0.2.2 with newer upstream source. AccessKit exists in inspected upstream source, not published 0.2.2; dependency selection needs artifact-level qualification.
- Slint second backend behind same protocol, pending written licensing clarification for a redistributable framework.
- Decision slice (editable reorderable list under async insert, custom Layout, interrupted animation, cancellation, IME, a11y activation) replaces v0.2 SR0.
- Corrections to this review: wrapper-as-SwiftUI-view is acceptable; Windows compile is necessary not sufficient; SwiftCrossUI already enables StrictConcurrency; #787 evidence is UIA traversal, Narrator untested; Windows App SDK 1.8 servicing end-date claim unverified in this review (not a current dependency); Observation polyfill asymmetry noted.

**Amended**
- "Full parity against named SDK version" scoped to inventory parity with macOS traces as oracle; SDK version is ceiling. Tokamak archived January 2026; OpenSwiftUI cross-platform graph incomplete after years.
- Bridge is the new hazard: batched diffs, handles, no closures across ABI, Rust owns loop, Swift main actor pumped; bridge cost is a budget item and a kill criterion.
- Runtime seed decided in SR0 by comparing SwiftCrossUI core fork against fresh runtime.
- §1 now states Windows is custom-drawn, Fluent-themed, accessible; not native WinUI. Same class as current Tauri shell.
- C# WinUI fallback removed entirely; breaks one codebase.

## v0.4 corrections, 8 October 2026

Adversarial review of v0.3 identified six plan defects. These dispositions change design & acceptance requirements; no implementation or runtime qualification is claimed.

| Finding | Correction in v0.4 | Required implementation evidence |
|---|---|---|
| Published GPUI conflated with upstream AccessKit | §2 separates published archive from source snapshot; SR0-D qualifies exact distribution before runtime investment | Native x64 & arm64 UIA discovery/action using pinned package/artifact inputs |
| Renderer fallback used for runtime/bridge failures | §12 routes failures by owner; Slint remains unqualified until same ABI probes pass | Root-cause evidence plus unchanged app fixtures through qualified alternative, or runtime repair/reselection |
| Swift & Rust both assigned layout ownership | §§5–6 give Swift final geometry; Rust supplies read-only measurement & painting | Width-dependent text, coherent paint/hit-test/AX bounds, no reentrant pumping, measured crossings |
| Oracle permits false confidence | §11 specifies input replay, controlled app effects, lifecycle observations, normalization, partial orders & accepted/candidate traces | 20 repeatable Mac runs; negative comparator fixtures; Windows replay plus native IME/assistive-technology actions |
| Seed selection precedes its evidence; budgets undefined | §§11–12 put fixtures/oracle before comparison, set numerical limits & bound failed attempts | Both seeds scored on same frozen workload/tuple; every stage reports pass/fail |
| Shared capability/release integration absent | §§7–9 map RightKit owners, adapter gaps, managed builds, local native hosts & existing signing | Exact published pins, working Swift adapters & RightKit-packaged clean-machine qualification |

Retained requirements: one Swift screen codebase, real SwiftUI/AppKit on Mac, Windows runtime ownership, reusable existing engines, no transpiler, second-language shell or runtime AI dependency. Custom `Layout` in SR0 remains a narrow probe; broader protocol support is later inventory growth.

Dependency correction sources: [published GPUI manifest](https://docs.rs/crate/gpui/0.2.2/source/Cargo.toml), [upstream snapshot](https://github.com/zed-industries/zed/tree/b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e/crates/gpui) & [AccessKit integration](https://github.com/zed-industries/zed/pull/56065).

## v0.5 sequential adversarial review, 8 October 2026

Fable 5.1 reviewed v0.4 read-only in native Claude session `95667ca2-6db5-4e91-bd33-d5daae9c8b3f`; transcript records `claude-fable-5-1`. Primary checked findings against plan, workspace owners & primary TSF/SwiftPM/MSIX documentation before integration. No implementation qualification is claimed.

| Fable finding | Disposition |
|---|---|
| H1 external accessibility tree | Accepted: D must publish SwiftRight-owned nodes/actions; B proves ABI route |
| H2 distribution dead end | Clarified: enumerate all platform crates; report unavailable published set as external blocker. No vendoring exception granted; alternate backend may enter D under same rules |
| H3 synchronous text store | Accepted: bounded C function table & native lock protocol; prohibition remains on captured Swift closures & callbacks during measurement/commit |
| M1 Mac Rust services | Accepted: thin services C ABI artifact on both OSes; Mac does not load renderer |
| M2 list lifecycle | Accepted scoped requirement: observable row realization/lifecycle in SR0; exact private overscan excluded, large-scale optimization later |
| M3 shipped-size budget | Rejected relaxation: no baseline measurement proves failure; runtime dependencies explicitly included & measured gate retained |
| M4 SwiftPM binary consumption | Accepted: system-library/module-map payload path plus separate downstream consumer qualification |
| M5 dispatch/RunLoop | Accepted: private drain shim identified & pinned, fail-closed qualification, RunLoop/Timer outside initial Windows contract |
| M6 partial API support | Accepted: absent/unavailable APIs diagnosed by compiler; runtime-value restrictions separately explicit; Combine family initially unsupported |
| M7 imports/modules | Accepted problem, different repair: one conditional target & import block; no underscored re-export required; same-source compile probe |
| M8 shared-stage termination | Accepted: capped shared failures stop SR0; rerun only already-started downstream stages |
| M9 shared adapters/template | Accepted gap preflight with RightKit owner/status; explicit Swift SDK request governs this product's runtime, without changing workspace template defaults |
| M10 arm64 availability | Rejected dropping required architecture; corrected wording to required hosts, whose availability D verifies |
| M11 MSIX migration | Accepted: qualify manifest-dependent paths, endpoint access, rollback reads & user-data preservation |
| M12 paint vocabulary | Accepted: retained primitives plus separate semantic nodes, frozen in C & exercised in B |
| L1–L3 instrumentation/schema | Accepted: observation topology, canonical roles/actions & calibrated visible-response endpoints defined before comparison |
| L4–L5 stale wording/evidence | Accepted: README terminology & unverified historical servicing claim corrected |
| L6 skip second seed | Rejected: two-seed comparison remains intended decision evidence; no measured reason to waive it |

Subsequent Astra & Opus reviews, verified corrections & convergence results follow below.

### Astra round 1

Independent Astra Oracle reviewed v0.5 after Fable integration. All six findings accepted: cooperative cancellation separated from guarded stale results; surviving-row identity separated from removal/reset; SDK-owned single-window bootstrap defined; binary mismatch rejection precedes runtime allocation/callbacks; logical actions map to native shortcuts with separate raw-key tests; current review-version pointer corrected. Apple cancellation, identity, App & shortcut sources support semantic corrections. Primary also clarified D's disposable binary probe & C's declaration stubs to avoid depending on B/S artifacts before they exist.

### Opus round 1

Native Claude session `a9af4704-6e19-4cfa-9d9a-2878136d1227` reports `claude-opus-5-5`; completed read-only with no permission denials. Primary verified IMM32 handlers & GPUI `AppCell` at cited snapshot, plus AccessKit callback-thread documentation.

| Opus finding | Disposition |
|---|---|
| H1 text API mismatch | Accepted: initial path is observed GPUI IMM32; remove unconditional TSF lock/reconversion claims; D/B prove actual path & ownership |
| M1 AX callback thread | Accepted: enqueue/wake only; off-thread-close test |
| M2 GPUI re-borrow | Accepted: drain outside GPUI borrows, independently retained measurement resources & buffered commits |
| M3 main-thread bootstrap | Accepted: synchronous process-initial-thread entry, loop-ready callback, isolation assertions |
| M4 animation clock | Accepted: on-demand display ticks, monotonic timestamps, idle stop & budget accounting |
| M5 Windows repeats | Accepted: 20 correctness runs per seed/architecture, separate from performance samples |
| M6 Mac runtime range | Accepted: explicit support matrix with floor/newest & trace lane for every advertised runtime |
| M7 engine binary isolation | Accepted: separate versioned engine DLL with owner-freed memory, unchanged renderer |
| L1 imports | Accepted explicit Foundation/Observation imports; no transitive-export assumption or dependency-byte exemption |
| L2 executor alternative | Accepted pinned-toolchain availability check; no claim that proposed hook has shipped |
| L3 artifact location/build comparison | Accepted manifests-only Git layout, staged payload/publication distinction & release edit-to-visible endpoint |

### Fable round 2

Resumed same native Fable 5.1 chat; effective model, successful completion & no denied reads verified. Prior repairs held. Eight in-repo findings accepted: published GPUI plus separate AccessKit composition candidate; explicit native service artifacts/Mac arm64 scope; Windows oracle of record; SR4 failure disposition; both Mac modules imported with SDK-symbol compile probe; required editable-text UIA patterns; signed recorder/permission preflight; TSF reference tied to future TSF qualification. Primary independently inspected published crate archives: GPUI exposes HWND & IMM32; AccessKit Windows 0.35.1 includes subclass adapter & UIA text provider. These establish candidate feasibility inputs, not native pass claims.

Ninth suggestion (change workspace-wide Rust/React rule) rejected as outside this repository's plan repair: explicit user-requested Swift SDK scope is already recorded in §7 & governs this product. No general workspace policy or infrastructure change is authorized by this review.

### Astra round 2

Prior six findings resolved. One new wording defect accepted: B now tests measure/commit during permitted Swift drains; native IME callbacks permit only text queries/edits, with attempted frame commit rejected/deferred & reconciliation after unwind. No other actionable findings returned.

### Opus round 2

Prior eleven repairs & Fable/Astra integrations resolved. One remaining modal-loop issue accepted: non-reentrant drain guard across host callbacks, window-targeted wakes, asynchronous Swift modal requests after unwind & B probes for live resize plus a modal request under load. Primary verified Microsoft modal-loop documentation. No other actionable findings returned.

### Fable round 3

Prior integrations held. Accepted named foreground-executor wake/drain candidate with modal cadence/shutdown tests & added B's editable-text UIA range/caret bridge probe. Primary verified published GPUI dispatch/window/event source. Clarified missing required Mac floor capacity blocks O/SR0; rejected automatic floor increase because it weakens declared support. Retained one initial attempt plus one targeted repair per failing stage/candidate; rejected per-probe retry expansion because no execution evidence justifies increasing the existing stage budget. These are explicit policy choices, not hidden prerequisites.

### Final sequential closure

| Reviewer | Final result on unchanged v0.5 |
|---|---|
| Fable 5.1, round 3 closure | No actionable findings; repairs validated & explicit floor/retry policies accepted |
| Astra, round 3 | No actionable findings; prior findings resolved, coherent ownership/gates/policies |
| Opus 5.5, round 3 | No actionable findings; modal-loop closure & final integration checked |

Order was Fable → Astra → Opus throughout, with primary verification & integration between stages. Final architecture & README stayed unchanged across the clean cycle. Primary verified SHA-256: architecture `9c8ea77ff8c7293fabb42981a6585c6321fa498a5b7509af1d6f4100a5a877eb`; README `1ee2bf78f925a51da9d2ad514db1a7ff49f45c6ed1a472a3f4810aee30c67419`. Opus reviewed on-disk files without independently hashing them; hashes are primary verification, not reviewer claims. This closure entry records results only.

Native Claude supervision verified effective model identities (`claude-fable-5-1`, `claude-opus-5-5`), persistent session IDs/transcripts above, submitted review prompts & readbacks, same-ID resume/reconnection, successful terminal completion & no permission denials in final calls. Astra ran as an independent read-only Oracle subagent. Review scope was architecture quality; native runtime/packaging/performance evidence remains governed by explicit delivery gates.

Primary validation: Markdown links/anchors/fences & `git diff --check` pass. All accepted findings are integrated; rejected suggestions retain their rationale above. No product implementation or workspace infrastructure was changed.
