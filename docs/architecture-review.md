# Adversarial review of SwiftRight architecture v0.1

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
