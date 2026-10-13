# Clang external-owner process v2

Bounded evidence captures exact public nominal identities for 12 requested external owners, plus `AppKit.NSControl` as `NSControl.ControlSize` outer-owner support. Pinned SDK is Xcode-27-RC, target `arm64-apple-macosx27.0`.

`run_capture.py` executes seven real `xcrun` subprocesses: Swift typecheck, SourceKit request, AppKit/Foundation/CoreFoundation/CoreGraphics/Spatial Clang AST dumps. Each receipt records argv, cwd, UTC start/end, return code, tool identity hash, bound source/request hashes, stdout/stderr paths, hashes, sizes, & decompressed AST stdout hashes. AST streams are gzip-compressed raw bytes; filtered records retain exact owner kind/source identity.

`build_evidence.py` reconstructs module-map exports, SourceKit USR/kind/line, SDK header line/hash/text, AST owner cardinality/kind, process outputs, input bindings, & raw output hashes. `test_process.py` first proves baseline acceptance, then rejects wrong source, USR, kind, return code, module export, & extra target mutations through production validator.

CoreFoundation geometry provenance binds CGPoint/CGSize/CGRect to actual `CoreFoundation.framework/Versions/A/Headers/CFCGTypes.h` definitions, correcting historical CGGeometry.h-only evidence. Historical v1 bytes remain untouched.

Latest evidence: `raw/clang-external-process-v2.json` SHA-256 `83266f81963496054326b1e63bd69e0b76eeb8849812f01b8d2244e29acece93`.
