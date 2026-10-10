# SwiftUICore header-derived SourceKit index v1

Fresh raw index of immutable `SwiftUICore` interface source from compiler-cursor link `836`, using production `arm64-apple-macosx27.0` & pinned SDK.

`header-flags.json` is shlex-derived from both `swift-module-flags` rows. Target, target-variant, & target-arch-variant are removed with values recorded. Frontend-only `-enable-objc-interop` & `-formal-cxx-interoperability-mode=off` are retained through `-Xfrontend`; `-module-abi-name SwiftUI`, `-public-module-name SwiftUI`, `-module-name SwiftUICore`, language, library, feature, package, & version flags remain pinned.

`sourcekit-index-core-header.stdout` is successful full response: 8,506 declaration records, 7,515 effective-public fields, 8,709 public attribute fields, 8,506 unique physical position/name/kind/USR pairs. Nominal USRs: 650 `SwiftUI` ABI prefix, 0 `SwiftUICore`; variable USRs: 1,679 `SwiftUI` ABI prefix, 0 `SwiftUICore`.

`attempts/` preserves initial exit-1 request/response preimages & unknown-argument diagnostic. Capture records no eligibility or namespace conclusion.

`run-receipt.json` pins runner cwd/argv/exit/output hashes, Swift compiler/sourcekit-lsp/sourcekitd binaries, & `tool-versions.json` (sourcekit-lsp reports no `--version`; pinned binary/Xcode toolchain identity remains recorded).
