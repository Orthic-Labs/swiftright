# SR0-C same-source probe: RESULT

Contract: `docs/architecture.md` §5 "Source/module contract" and "Application entry".
Scope: one shared SwiftUI screen file compiles unchanged on macOS (SwiftUI) and Windows (declaration-only `SwiftRightUI` stubs).

## Verdict

| Platform | Result | Notes |
|---|---|---|
| macOS arm64 (Swift 6.4, Xcode 27 RC, SDK MacOSX27.0) | **PASS** | `swift build` clean, no warnings, Swift 6 mode. Probe not launched. |
| Windows x64 (Swift 6.4-RELEASE, x86_64-unknown-windows-msvc) | **PASS** | `swift build` complete. Screen compiled unchanged against stubs. Probe constructs nothing at runtime (stubs trap by design). |
| Negative fixture `NavigationSplitView` | **PASS (as expected)** | macOS typecheck exit 0; Windows exit 1 with `cannot find 'NavigationSplitView' in scope`. |

The screen file is **not identical to the brief's sample**. One change was required and is shared by both platforms (no platform fork). See "Contract issues".

## Layout

```
probes/sr0-c/same-source/
  RESULT.md
  SameSource/                         SwiftPM package (tools 6.2, swiftLanguageModes [.v6])
    Sources/SwiftRightUI/Common.swift          sdkVersion (all platforms)
    Sources/SwiftRightUI/WindowsStubs.swift    #if os(Windows) declaration-only SwiftUI shape
    Sources/SharedScreens/ReorderableEditorScreen.swift   THE SHARED SCREEN
    Sources/SharedScreens/PublicRoot.swift     non-screen glue (makeProbeRoot)
    Sources/Probe/ProbeApp.swift               #if os(macOS): SwiftUI App, one Window
    Sources/Probe/WindowsEntry.swift           #if os(Windows): synchronous @main, no rendering
  Negative/NavigationFixture.swift    not in the package; typechecked separately
```

No `main.swift` exists (see error 1 below). Nothing outside `probes/sr0-c/same-source/` was written, and nothing was committed, branched or pushed.

## Shared screen import block (verbatim, unchanged from brief)

```swift
import Foundation
import Observation
#if os(macOS)
import SwiftUI
import SwiftRightUI
#else
import SwiftRightUI
#endif
```

## SDK actor-isolation contract (quoted from the pinned SDK)

`/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`

```
17482: @_typeEraser(DebugReplaceableView) @_typeEraser(AnyView) @preconcurrency @_Concurrency::MainActor public protocol View {
17488:   @SwiftUICore::ContentBuilder @_Concurrency::MainActor @preconcurrency var body: Self.Body { get }
```

The Windows stub mirrors this: `@MainActor @preconcurrency public protocol View` with `@ViewBuilder @MainActor var body: Body { get }`. `Never`, `Optional`, `TupleView`, and each stub view declare `@MainActor var body: Never`.

SDK SwiftUI-owned symbol used by the screen: `Array.move(fromOffsets:toOffset:)` is declared at `SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface:17814` (`public mutating func move(fromOffsets source: Foundation::IndexSet, toOffset destination: Swift::Int)`), i.e. a SwiftUICore export, not part of Foundation.

## Commands

macOS (from `probes/sr0-c/same-source/SameSource`):

```
swift build
```

Windows (package synced via the bridge; PATH fix from the brief):

```
scripts/sync-to-win.sh <abs>/probes/sr0-c/same-source/SameSource 'D:\Claude\sr0c-same-source'
win "$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User'); Set-Location 'D:\Claude\sr0c-same-source'; swift build"
```

Negative fixture (same typecheck recipe on both platforms; `SwiftRightUI` emitted as a module from the same sources):

```
# macOS
swiftc -emit-module -parse-as-library -swift-version 6 -module-name SwiftRightUI -emit-module-path <scratch>/neg-mac/SwiftRightUI.swiftmodule SameSource/Sources/SwiftRightUI/*.swift
swiftc -typecheck -swift-version 6 -I <scratch>/neg-mac Negative/NavigationFixture.swift     # exit 0

# Windows (Negative/ synced to D:\Claude\sr0c-same-source\Negative)
swiftc -emit-module -parse-as-library -swift-version 6 -module-name SwiftRightUI -emit-module-path neg-win\SwiftRightUI.swiftmodule (Get-ChildItem Sources\SwiftRightUI\*.swift).FullName
swiftc -typecheck -swift-version 6 -I neg-win Negative\NavigationFixture.swift                 # exit 1
```

Not run: launching the macOS Probe (GUI) and running the Windows Probe (stubs trap when called, by design). Both are compile proofs only.

## Errors encountered and fixes

Maximum 6 fix iterations per platform. Windows used 5 (1 stub-level sweep, then targeted fixes). macOS used 2.

### macOS

1. `Sources/Probe/main.swift:6:1: error: expressions are not allowed at the top level`
   Top-level expressions inside an inactive `#if os(Windows)` block are still rejected on macOS. Fix: deleted `main.swift`; Windows entry is now a `@main` type in `WindowsEntry.swift` with `@MainActor static func main()` (synchronous, not async).
2. `SharedScreens/PublicRoot.swift:8:5: warning: call to main actor-isolated initializer 'init()' in a synchronous nonisolated context`
   Fix: `@MainActor` on the glue function `makeProbeRoot()` (non-screen file). The screen file itself was never edited for this.

After these, macOS built clean. The screen compiled first try with the `{ $row in ... }` form (see contract issue 1).

### Windows

1. `WindowsStubs.swift:271-273: error: static property 'zero'/'unspecified'/'infinity' is not concurrency-safe because non-'Sendable' type 'ProposedViewSize' may have shared mutable state`
   Fix: changed to computed `static var`. Same member shape; avoids a global-variable diagnostic.
2. `WindowsStubs.swift:71:1: error: conditional conformance of type 'Binding<Value>' to protocol 'RandomAccessCollection' does not imply conformance to inherited protocol 'BidirectionalCollection'` (also `Collection`, `Sequence`)
   Fix: declared `Sequence`, `Collection`, `BidirectionalCollection`, `RandomAccessCollection` conformances, each with the same `where Value: MutableCollection, Value: RandomAccessCollection` clause.
3. `WindowsStubs.swift:24:39: error: cannot convert return expression of type 'TupleView<Never>' to return type 'Never'` (every `body`)
   Cause: the SDK requirement is `@ViewBuilder var body`, so a witness whose body is a bare `fatalError()` is result-builder-transformed. Fix: `var body: Never { return fatalError() }` (an explicit `return` disables the transform).
4. `WindowsStubs.swift:266:9: error: return type of instance method 'onMove(perform:)' requires that 'Never' conform to 'DynamicViewContent'`
   Fix: `onMove` returns a concrete `DynamicViewStub` instead of an opaque `fatalError()` result.
5. `SharedScreens/ReorderableEditorScreen.swift:66:43: error: cannot use property wrapper projection parameter`
   Triggered by `ForEach($editable.rows) { $row in`. Attempts: (a) added the SDK's `Binding<C>` overload of `ForEach` (`_disfavoredOverload`) to the stub; error unchanged. (b) root-cause probe: a local `@propertyWrapper` closure parameter `each { $x in ... }` is rejected by the **macOS** compiler too, so the rule is generic; macOS accepts the SwiftUI form for a reason not visible in the SDK `.swiftinterface`. Not resolved further. Fix that works on both: `ForEach($editable.rows) { row in TextField("Row", text: row.text).focused($focus, equals: row.id) }`. `row` is `Binding<Row>`, so `row.text` uses dynamic member lookup and `row.id` uses `Identifiable`.

After fix 5, Windows `swift build` completed. The `Binding<C>` overload stays in the stub as a faithful SDK mirror (it is unused by the final screen).

Non-error Windows noise: `reference to type 'wchar_t' broken by a context change` warnings from the WinSDK module; not from this probe.

## Negative fixture

`Negative/NavigationFixture.swift` uses `NavigationSplitView`, which is outside the stub inventory.

- macOS: typecheck exit 0 (real SwiftUI resolves it).
- Windows: exit 1, `NavigationFixture.swift:11:9: error: cannot find 'NavigationSplitView' in scope`.

## Contract issues

1. **`$row` closure projection is not portable (screen changed).** The brief's `ForEach($store.rows) { $row in ... $row.text ... }` form compiles on macOS but is rejected on Windows with `cannot use property wrapper projection parameter`. The shared screen uses `{ row in ... row.text ... row.id }` instead. The import block and all other declarations are unchanged; both platforms compile the identical file. The SR0-S/SR1 team should decide whether `$`-projected closure parameters are supported in shared screens. Root cause is not identified.
2. **Screen depends on a SwiftUI export.** `rows.move(fromOffsets:toOffset:)` is a SwiftUICore symbol (see SDK line 17814), not Foundation. Under the contract ("do not depend on SwiftUI transitive exports"), the screen should not use it. Windows compiles only because the stub declares it (`extension MutableCollection`). Recommended fix in the screen: replace with Foundation-only reordering (remove and insert), then drop the stub shim. Not changed in this probe because the brief fixed the screen's content (`.onMove` shape) and asked only for stub-level fixes.
3. **Stubs are shape-only, not behavior.** `Text` takes `String`, whereas SwiftUI's `Text` takes `LocalizedStringKey`. `FocusState.init()` is constrained to `ExpressibleByNilLiteral`; the exact SDK overload set was not enumerated. `Layout` omits the `Animatable` refinement (the screen does not use it), and `makeCache` uses the `Cache == Void` default.
4. **Same-name ambiguity: none observed.** On macOS, `SwiftRightUI` declares only `sdkVersion` (no `View`, `State`, `Binding`, `Environment`, `FocusState`, `Layout`), so no SwiftUI name is shadowed or ambiguous. The Windows stub declares every name only under `#if os(Windows)`. Because `SwiftRightUI` on macOS declares no SwiftUI-named type, the screen cannot be ambiguous there.
5. **Result-builder `if` shape.** The Windows `ViewBuilder` provides `buildIf` and `buildEither` (both mirror SDK names; the macOS SDK has `buildIf` at `SwiftUICore...interface:5609`). The screen uses `if` with and without `else`, which compiled on both.

## Out of scope / not touched

- Only `probes/sr0-c/same-source/` was written.
- `probes/sr0-d/ime-text-node/` appeared as untracked during this work; it is not from this probe and was not modified.
- No commit, branch, push, or Rust build.

## Primary correction (2026-10-09)

Contract finding 1 was a stub defect, not a portability limit. SwiftUI's `Binding` declares `public init(projectedValue: Binding<Value>)` (SwiftUICore interface line 14388), which is what permits `{ $row in }` closure parameters under SE-0293. Adding that initializer to the Windows stub restored the original `ForEach($editable.rows) { $row in TextField("Row", text: $row.text) … }` line. Both `swift build` runs pass with the screen unchanged: macOS 1.8 s, Windows x64 17.8 s.

Contract finding 2 is not a transitive-export violation: the shared file imports SwiftUI explicitly on macOS. `MutableCollection.move(fromOffsets:toOffset:)` joins the Windows inventory, provided by `SwiftRightUI`.
