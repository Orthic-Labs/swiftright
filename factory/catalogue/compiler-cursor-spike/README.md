# SourceKit compiler-cursor spike

This spike tests whether pinned SourceKit index and cursor requests can produce compiler USRs for unresolved SDK interface declarations. SourceKit emits declaration records for exact `.swiftinterface` locations; strict linking needs one raw record matching source line, declaration name, kind, enclosing context, effective access, live interface hash, and parsed request identity. Duplicate raw records remain held even when their USRs are identical.

## Pinned inputs

- Xcode 27.0 (27A266a), Apple Swift 6.4.0.34.1; SDK `MacOSX27.0.sdk`; target `arm64-apple-macosx27.0`.
- SwiftUI interface SHA-256: `155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38`.
- SwiftUICore interface SHA-256: `4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13`.
- Input audit: `factory/catalogue/evidence/interface-audit-v6.json`; raw symbol graphs: `factory/out/catalogue/raw`, target `arm64-apple-macosx27.0`. `link-evidence.json` records each live input hash and validates it before joining.

## Reproduction

Run from repository root on pinned Xcode installation:

```sh
xcrun sourcekit-lsp debug run-sourcekitd-request --request-file factory/catalogue/compiler-cursor-spike/request-index-interface.yaml > /tmp/sourcekit-index-interface.txt
xcrun sourcekit-lsp debug run-sourcekitd-request --request-file factory/catalogue/compiler-cursor-spike/request-index-core.yaml > /tmp/sourcekit-index-core.txt
xcrun sourcekit-lsp debug run-sourcekitd-request --request-file factory/catalogue/compiler-cursor-spike/request-interface-module-name.yaml > /tmp/sourcekit-cursor.txt
xcrun swiftc -typecheck -sdk /Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -target arm64-apple-macosx27.0 factory/catalogue/compiler-cursor-spike/probe.swift
python3 factory/catalogue/compiler-cursor-spike/test_strict_match.py -v
python3 factory/catalogue/compiler-cursor-spike/analyze_index.py
```

Request files preserve exact SourceKit request bytes; raw index responses are retained uncompressed as `index-interface-output.txt` and `index-core-output.txt`. Analyzer output is `link-evidence.json`; it includes input, request, response, toolchain, cursor-control, and raw-symbol-graph hashes. `run-receipt.json` includes reproducible command, compiler identity, and validation receipts.

## Observed result

Of 2,549 v6 residual rows, 2,285 have exactly one eligible raw SourceKit declaration entity. Of those, 135 USRs are also in the pinned symbol graphs and 2,150 are absent there. Five same-USR duplicate raw records remain held. Other 259 held rows fail exact matching gates: 206 enclosing-context mismatches, 51 declarations with no parseable expected access level, one declaration-kind mismatch, and one line with no same-name entity.

Six call-site cursor probes resolve to matching exact interface-row USRs: `accessibilityLabel(content:)`, `sensoryFeedback(trigger:_:)`, both `dropDestination` overloads, and both `onDrop` overloads. Interface cursor info resolves `SwiftUI.View.accessibilityLabel(content:)` only when `-module-name SwiftUI` is supplied; omitting module name returns `P4mainE` USR, so that fault control is rejected. Conditional controls confirm `MenuButton` resolves in active `$TildeSendable` branch and not inactive `#else`; `buildLimitedAvailability` row 28491 is in inactive `#else` because compiler selected `$InlineAlways`.

These results establish compiler-produced index-link evidence for guarded rows. They do not establish independent public-inventory closure; held rows remain residual until separately resolved.
