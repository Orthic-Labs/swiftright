# SR0-D probe: SwiftPM consumer of a prebuilt C ABI DLL on Windows x64

**Overall: PASS** for steps 1-5, with the limitations listed at the end. The downstream app resolves, links and loads a prebuilt MSVC-built DLL through a `systemLibrary` target and module map. No Rust/Cargo was used, and no `unsafeFlags` appears in any package.

Host: Windows x64, Swift 6.4.0 (`x86_64-unknown-windows-msvc`), Visual Studio 2026 Community (MSVC cl/lld-link).
Work dir: `D:\Claude\sr0d-swiftpm\`. Payload: `D:\Claude\sr0d-swiftpm\payload\{include,lib,bin}` (outside both packages).
Sources synced from `probes/sr0-d/swiftpm-consumer/` with `scripts/sync-to-win.sh`.

## Step 1: sentinel payload (MSVC) - PASS

Source: `payload-src/sentinel.c`, `payload-src/sentinel.h` (`__declspec(dllexport)` via `SWR_SENTINEL_BUILD`, `dllimport` for consumers).
`swr_bootstrap_query` returns 0 and fills fields only when `caller_size >= sizeof(swr_bootstrap_info)` (36 bytes), else returns -1 and writes nothing.

Build command (inside a VS dev shell):
```
cl /nologo /LD /W4 /WX /I "D:\Claude\sr0d-swiftpm\payload\include" "D:\Claude\sr0d-swiftpm\payload-src\sentinel.c" /Fe:"...\payload\bin\swiftright_sentinel.dll" /Fo:"...\payload\obj\" /link /IMPLIB:"...\payload\lib\swiftright_sentinel.lib"
```
Verbatim (trimmed):
```
   Creating library D:\Claude\sr0d-swiftpm\payload\lib\swiftright_sentinel.lib and object D:\Claude\sr0d-swiftpm\payload\lib\swiftright_sentinel.exp
exit=0
          1    0 00001000 swr_bootstrap_query
          2    1 000010F0 swr_sentinel_add
```
First attempt failed on `/WX` with C4996 for `strncpy`; replaced with a bounded copy loop, then rebuilt clean.

## Step 2: SDK wrapper package - PASS

`probes/sr0-d/swiftpm-consumer/SwiftRightSentinelSDK/`
- `Package.swift`: `.systemLibrary(name: "CSwiftRightSentinel", path: "Sources/CSwiftRightSentinel")` plus Swift target `SwiftRightSentinel`, product `SwiftRightSentinel`. No linker or unsafe settings.
- `Sources/CSwiftRightSentinel/module.modulemap`: `module CSwiftRightSentinel [system] { header "shim.h"  link "swiftright_sentinel"  export * }`
- `Sources/CSwiftRightSentinel/shim.h`: `#include <sentinel.h>` (resolved from the consumer's `-Xcc -I`, not from the package).
- `Sources/SwiftRightSentinel/SwiftRightSentinel.swift`: `public func sentinelAdd(_:_:)`, and `public func checkABI() -> Result<SentinelABIReport, SentinelError>`, which calls `swr_bootstrap_query` with size 36 and with size 8, and reports both plus whether the too-small call left `struct_size` untouched (sentinel value 0xFFFFFFFF).

## Step 3: consumer app - PASS

`probes/sr0-d/swiftpm-consumer/ConsumerApp/`: `.package(path: "../SwiftRightSentinelSDK")`, executable prints `sentinelAdd(2,3)` and the `checkABI` results.

## Step 4: build, stage, run, fail-closed - PASS

Exact working build command (fresh scratch path, run from `ConsumerApp`, inside a VS dev shell and the Swift runtime PATH fix):
```
swift build -c release --scratch-path D:\Claude\sr0d-swiftpm\scratch-final -Xcc -ID:\Claude\sr0d-swiftpm\payload\include -Xlinker -LD:\Claude\sr0d-swiftpm\payload\lib
```
Note: the spec's `-Xcc -I <path>` with a space does not parse (`error: 2 unexpected arguments`). The joined form `-I<path>` and `-L<path>` is required.

Verbatim build tail: `Build complete! (5.10 secs)`, build exit 0.

Stage DLL beside exe (`...\scratch-final\out\Products\Release-windows-x86_64\`), then run:
```
sentinelAdd(2, 3) = 5
expectedSize = 36
fullSize -> success(SwiftRightSentinel.SentinelBootstrap(structSize: 36, abiMajor: 0, abiMinor: 1, pointerWidth: 64, arch: "x86_64", fnTableSize: 16))
tooSmallCallerSize = 8 -> failure(SwiftRightSentinel.SentinelError.queryRejected(code: -1, callerSize: 8))
tooSmallUntouchedStructSize = Optional(4294967295)
exit=0
```

Fail-closed: removed `swiftright_sentinel.dll` from beside the exe; `payload\bin` is not on PATH (checked: `False`); no copy of the DLL is on PATH.
```
exit=-1073740612 (0xC00004BC)
stdout bytes=0 stderr bytes=0
```
Observations:
- The process fails at load, before `main` runs, so there is no stdout and no stderr. It does not run with a stale or substitute DLL.
- The code is `0xC00004BC`, not the usual loader code `STATUS_DLL_NOT_FOUND` (0xC0000135). certutil decodes 0xC00004BC as "untrusted mount point", which does not fit a missing DLL. Its meaning here is unexplained. Control run: exe copied alone into an empty directory (runtime on PATH, sentinel absent) gives the same 0xC00004BC, so it is the load failure for this build, not a sentinel-specific code.
- Restoring the DLL restores exit 0 and the full output above, so the failure is caused by the missing DLL.

## Step 5: checks - PASS

- `grep -r unsafeFlags` over `SwiftRightSentinelSDK/` and `ConsumerApp/` (Mac): no matches. Same search on Windows copies (excluding build dirs): no matches.
- No cargo/rustc invoked in this probe; all build steps were SwiftPM (`swift build`) and MSVC (`cl`, `dumpbin`).
- No commit, push or branch. Files written only under `probes/sr0-d/swiftpm-consumer/`. The repo's other untracked probes (`sr0-c`, `ime-text-node`) predate this work.

## Limitations and findings

1. **Search paths are on the command line.** Both `-Xcc -I<payload>\include` and `-Xlinker -L<payload>\lib` are required. Checked with fresh scratch paths:
   - No flags: `'sentinel.h' file not found`.
   - Only `-Xlinker -L`: same `'sentinel.h' file not found`.
   - Only `-Xcc -I`: `lld-link: could not open 'swiftright_sentinel.lib'`.
   So the consumer needs a thin invocation with both flags. This is acceptable as a "thin consumer build invocation" only if the consumer's build script owns them; the package manifest itself stays free of paths. Any no-command-line alternative (for example env vars such as `CPATH`/`LIB`) was not tested.
   Note: an earlier "Build complete" with only `-Xlinker -L` was a cache hit from the first build. The fresh-scratch test is the one to trust.
2. **Payload `module.modulemap` is redundant.** `payload\include` contains the `module.modulemap` specified in step 1. The build did not report a duplicate `CSwiftRightSentinel` module, because the SDK's `-fmodule-map-file` is what gets used. A consumer that adds `payload\include` to the search path still resolves the SDK's module map. Not separately tested with that file removed.
3. **Fail-closed code is non-standard**, as described above. Exit is nonzero, there is no output, and no stale DLL is used. The exact code should be explained before a release gate relies on it.
4. **`payload\obj`, `.exp` and `.lib` leftovers** are in the payload dir. This is expected for an MSVC import library build.

## Primary verification (2026-10-09)

Rerun from fresh directories with the Swift 6.4 runtime bin first on PATH:
- Exe + staged `swiftright_sentinel.dll`: `sentinelAdd(2, 3) = 5`, full-size bootstrap succeeds, 8-byte caller rejected with struct untouched, exit 0.
- Exe alone: exit 0xC00004BC with no output, also with the runtime PATH corrected, so the code is the loader's missing-dependency failure on this Windows build, not the BlocksRuntime shadowing issue.

Consequence for SR0-B: a missing renderer DLL kills the process before any Swift code runs. §6 requires deterministic startup diagnostics, so the bootstrap must load the renderer explicitly (LoadLibrary/delay-load) and report a typed error instead of relying on import-table loading.
