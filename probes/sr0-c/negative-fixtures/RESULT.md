# SR0-C negative fixtures: `.onReceive`, `ObservableObject`/`@StateObject`, `Timer.publish`

Contract: `conformance/sr0-slice/CONTRACT.md` §2 (negative fixtures must fail Windows compilation with a diagnostic).
Slice under test: `probes/sr0-s/fresh-runtime` (module `SwiftRightRuntime`), read-only. Each fixture is one SwiftPM library target depending on that slice. `PositiveControl` uses only slice APIs (`View`, `Text`, `VStack`) and must compile on both OSes. It shows the failures are API-specific.

Commands:
- Mac: `probes/sr0-c/negative-fixtures/run-fixtures.sh <dir>` (per-target `swift build --target`, ANSI stripped).
- Windows: synced to `D:\Claude\sr0c-neg\probes\sr0-c\negative-fixtures` and `D:\Claude\sr0c-neg\probes\sr0-s\fresh-runtime`, then `swift build --target <T>` with the PATH from `examples/BridgeSmoke/scripts/build-smoke.ps1`. Logs in `D:\Claude\sr0c-neg\logs\`.

| Fixture | Mac: expected-fail | Mac: first diagnostic | Windows: expected-fail | Windows: first diagnostic |
|---|---|---|---|---|
| PositiveControl | no (compiles, as expected) | none | no (compiles, as expected) | none |
| NegOnReceive | **yes** | `Sources/NegOnReceive/OnReceive.swift:9:22: error: value of type 'Text' has no member 'onReceive'` | **yes** | `OnReceive.swift:9:22: error: value of type 'Text' has no member 'onReceive'` |
| NegObservableObject | **yes** | `Sources/NegObservableObject/ObservableObject.swift:5:27: error: cannot find type 'ObservableObject' in scope` | **yes** | `ObservableObject.swift:5:27: error: cannot find type 'ObservableObject' in scope` |
| NegTimerPublish | **no** (compiles, exit 0) | none | **yes** | `TimerPublish.swift:7:23: error: type 'Timer' has no member 'publish'` |

Windows paths are prefixed `D:\Claude\sr0c-neg\probes\sr0-c\negative-fixtures\Sources\<Target>\`. Mac paths are prefixed `probes/sr0-c/negative-fixtures/`.

## Findings

- `NegTimerPublish` does not fail on macOS. Apple's Foundation (macOS 27 SDK) exposes `Timer.publish` without `import Combine`, so the Mac build compiles it. The Windows failure is the evidence the contract requires. The Mac oracle cannot prove this negative, so it needs a Windows-only check.
- `NegObservableObject` also reports `unknown attribute 'Published'` and `'StateObject'` on Mac, and the first diagnostic is the `ObservableObject` one. Those attributes were not separately evidenced as a first line.
- The `.onReceive` fixture passes a placeholder `Int` argument, so the only failing name is `onReceive`.
- `docs/sr0-freeze-slice-contract-v1.md` (lines 33 and 100) still list these three as PENDING. Not edited here, because it is outside the allowed edit paths. Windows evidence now exists for all three.
