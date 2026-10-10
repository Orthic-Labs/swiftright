# SR0-S final runtime: headless `swift test` on macOS arm64 and Windows x64

Result: **all applicable tests pass on both OSes, first run, 0 failures, 0 skipped.**

| Package | macOS 27.0.1 arm64 | Windows 11 x64 |
|---|---|---|
| `probes/sr0-s/fresh-runtime` (SwiftRightRuntimeTests, incl. PerformanceTests) | **84 / 84 pass** (exit 0) | **84 / 84 pass** (exit 0) |
| `packages/SwiftRightBridge` (SwiftRightBridgeTests, AXTextRunTests; the "8/8") | **8 / 8 pass** (exit 0) | **8 / 8 pass** (exit 0) |
| `probes/sr0-s/fresh-on-bridge` (FreshOnBridge) | no test target: builds, `swift test` exits 1 `error: no tests found` | same: builds, exit 1 `error: no tests found` |

Failing tests: none. Skipped tests: none (the only "skipped" text in the logs is the test name
`FocusTraversalTests.testDisabledStopsAreSkipped`, which passed). No test needed a rerun.

## What `swift test` covers

- **fresh-runtime**: module `SwiftRightRuntime`, 84 XCTest cases in 15 suites (below). Pure Swift, no renderer, no DLL.
- **FreshOnBridge has no `Tests/` and no `.testTarget`** (see its `Package.swift`: one `executableTarget`). `swift test` there only
  builds the package (runtime + bridge + executable) and then reports "no tests found"; that exit 1 is the absence of a test
  target, not a failure. Its own verification is the scripted `--self-test` run against the renderer DLL
  (`probes/sr0-s/fresh-on-bridge/RESULT.md`, `out/matrix-final/`), which is a Windows-only runtime run and is not part of
  `swift test`. No renderer DLL was used or needed here.
- **The Bridge tests ("8/8") live in `packages/SwiftRightBridge/Tests/SwiftRightBridgeTests/AXTextRunTests.swift`**, not in
  fresh-on-bridge. They exercise the platform-neutral AX text-run marshalling (no `LoadLibrary`, no DLL), so they apply on
  macOS too, where `Bridge.load` itself would throw `.unsupportedPlatform` and is not called. Ran on both OSes: 8/8.

## Commit tested

`252a598c0e40a137a40d0f95f3551cf4c5bf8758` (master HEAD at test time, tree clean). Final runtime commit
`b8702bbc48e416947c30a69d186190779897ffcb` is an ancestor. Runtime sources are unchanged since `b8702bb`:
`git diff --stat b8702bb HEAD -- probes/sr0-s/fresh-runtime/{Package.swift,Sources,Tests} probes/sr0-s/fresh-on-bridge/{Package.swift,Sources} packages render`
is empty. (`git log b8702bb..HEAD -- probes/sr0-s/fresh-runtime probes/sr0-s/fresh-on-bridge` lists only `5a67f23`, which added
`fresh-on-bridge/out/matrix-final/` result files.)

## Host facts

| | macOS | Windows |
|---|---|---|
| Machine | Adrian's Mac | `Bogus-Dell` |
| OS | macOS 27.0.1 (build 26A434), Darwin 27.0.0 | Windows 11 Pro 10.0.26300 |
| Arch | `uname -m` = arm64 | `PROCESSOR_ARCHITECTURE` = AMD64 |
| `swift --version` | swift-driver 1.168.6, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1), Target arm64-apple-macosx27.0.0 (Xcode-27-RC toolchain) | Swift version 6.4 (swift-6.4-RELEASE), Target x86_64-unknown-windows-msvc, Build config +assertions (`...\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe`) |
| Env | none special | `SDKROOT=C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\SDKs\Windows.sdk\`; `PATH` prefixed with `C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin` (the same setup as `examples/SliceApp/scripts/build-windows.ps1` and `probes/sr0-s/fresh-on-bridge/scripts/build-fresh.ps1`) |
| Source location | `/Volumes/D/claude/swiftright` (sources only; all build products and test binaries on the internal disk) | `D:\Claude\sr0-swifttest\repo`, a `git clone` of a `git bundle` of master (bundle sha256 `8817D638D5E8B7A4AA743795C940D2815FF9FB0087209054B2F19FAA72710C1A`), `HEAD` verified = `252a598c...` before testing |
| Build config | debug (default `swift test`), fresh scratch dir per package | debug (default `swift test`), fresh scratch dir per package |
| Windows UI | no window opened | no GUI launched, interactive desktop and Windows Sandbox untouched; headless over SSH |

## Commands

macOS (scratch on the internal disk, never on `/Volumes/D`):

```
S=/private/tmp/claude-501/-Volumes-D-claude-swiftright/608d5b75-d927-4ac2-a450-cee48f9d74ed/scratchpad/swifttest-mac
cd /Volumes/D/claude/swiftright/probes/sr0-s/fresh-runtime && swift test --scratch-path $S/fresh-runtime
cd /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge && swift test --scratch-path $S/fresh-on-bridge
cd /Volumes/D/claude/swiftright/packages/SwiftRightBridge && swift test --scratch-path $S/SwiftRightBridge
```

Windows (`win "powershell -NoProfile -EncodedCommand <UTF-16LE base64 of the script>"`; script body):

```
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$stage = 'D:\Claude\sr0-swifttest'; $repo = "$stage\repo"
# for each of: probes\sr0-s\fresh-runtime, probes\sr0-s\fresh-on-bridge, packages\SwiftRightBridge
Set-Location "$repo\$pkg"; cmd /c "swift test --scratch-path $stage\scratch\<leaf> 2>&1"
```

Staging: `git bundle create` on the Mac, `scp` to the Dell, `git -c core.autocrlf=false -c core.symlinks=false clone -b master`
into `D:\Claude\sr0-swifttest\repo`. When done the whole stage dir (clone, scratch, bundle) was cleared of read-only attributes
(`attrib -r /s /d`) and moved to the Recycle Bin with `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(..., 'SendToRecycleBin')`;
`Test-Path D:\Claude\sr0-swifttest` is `False` afterwards. Mac scratch stays under the session scratchpad (internal disk).

## Wall time (each includes a clean debug build of that package plus its dependencies)

| Package | macOS | Windows |
|---|---|---|
| fresh-runtime | 17 s (XCTest run 6.0 s) | 64 s (XCTest run 7.3 s) |
| fresh-on-bridge | 13 s (build 9.6 s, then "no tests found") | 36 s (build 33.3 s, then "no tests found") |
| SwiftRightBridge | 15 s (XCTest run 0.08 s) | 22 s (XCTest run 0.26 s) |
| Total | about 45 s | about 2 min (07:07:13 to 07:09:17 +05:30) |

## fresh-runtime per-suite counts (identical on both OSes)

AnimationTests 5, BindingCollectionTests 3, FocusContainerTests 4, FocusTraversalTests 8, LayoutTests 7, LazyContainerTests 1,
PerformanceTests 7, RowRefreshTests 7, RuntimeTests 11, SR1ControlTests 8, SR1SelectionMenuTests 8, ScrollViewTests 1,
TaskIDTests 3, TeardownTests 4, TextInputTests 7. Sum 84. PerformanceTests are work-counter and linearity regression tests
and all 7 passed on both OSes; the one timing line they print (debug build, `optimized=false`, 200-row commit medians):

- macOS: typing 9.4 ms, scroll-only 14.8 ms, row edit 14.0 ms
- Windows: typing 16.3 ms, scroll-only 23.8 ms, row edit 19.5 ms

Summary lines in the logs:

```
macOS    Test Suite 'SwiftRightRuntimeTests.xctest' passed ... Executed 84 tests, with 0 failures (0 unexpected) in 6.000 (6.012) seconds
macOS    Test Suite 'SwiftRightBridgeTests.xctest'  passed ... Executed 8 tests, with 0 failures (0 unexpected) in 0.075 (0.083) seconds
Windows  Test Suite 'Debug-windows-x86_64.xctest'   passed ... Executed 84 tests, with 0 failures (0 unexpected) in 7.319 (7.319) seconds
Windows  Test Suite 'Debug-windows-x86_64.xctest'   passed ... Executed 8 tests, with 0 failures (0 unexpected) in 0.26 (0.26) seconds
```

Both OSes also print `Test run with 0 tests in 0 suites passed` from the Swift Testing runner (no `@Test` cases exist; the suites are XCTest).

## Compiler diagnostics (not test failures)

- macOS: none.
- Windows: 47 distinct warnings (94 log lines containing `warning:`, each diagnostic printed twice). 45 are the toolchain/SDK
  `WinSDK` module note "reference to type 'wchar_t' broken by a context change" (SDK module built with Swift 5.10, invoked
  under 6.4; repeated per compile step). The other 2 are source warnings in `fresh-on-bridge` (built by its `swift test`):
  unused result of `FileManager.createFile` at `Sources/FreshOnBridge/SelfTest.swift:426`, and "reference to captured var
  'self' in concurrently-executing code" at `Sources/FreshOnBridge/Hooks.swift:52` (Swift 5 language mode). No errors.

## Logs

- `probes/sr0-s/fresh-runtime/out/swift-test-final-mac.txt` (28 KB, complete)
- `probes/sr0-s/fresh-runtime/out/swift-test-final-windows.txt` (86 KB, complete; ANSI colour codes, CR characters and the
  PowerShell CLIXML progress envelope that `-EncodedCommand` appends were stripped, nothing else edited)

Each log opens with host facts and the commit, then per package: the exact command, swift output, and `exit=<code> wall_seconds=<n>`.
