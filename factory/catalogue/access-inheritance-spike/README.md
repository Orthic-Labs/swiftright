# Enum-case effective-access spike

This spike resolves access-level gaps for 51 held enum-case rows from immutable `factory/catalogue/compiler-cursor-spike/link-evidence.json` (SHA-256 `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`). It adds no changes to that evidence or catalogue adapter.

SourceKit `source.request.indexsource` output contains exactly one declaration record for each exact residual source line, name, kind, and enclosing context. Every record has a unique compiler USR and `key.effective_access: source.decl.effective_access.public`; each lexical owning enum declaration is explicitly `public`. Live SwiftUI and SwiftUICore interface hashes are checked against original link evidence before rows are matched. Full exact row-to-USR records are in `access-evidence.json`.

Swift language documentation states enum cases automatically receive same access level as their enum. This is confirmed with pinned Swift 6.4 compiler controls: SourceKit reports `public`, `internal`, `fileprivate`, and `less_than_fileprivate` for fixture cases; separate client modules can import public cases, while internal/private/fileprivate cases are rejected. A real `import SwiftUI` client typechecks 11 case expressions across all 11 enum owners represented by held rows, including nested enums. See [Swift Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/).

## Proposed exact mapping rule

For enum-case candidate, keep all compiler-cursor spike identity, line/name/kind/context, live interface hash, and exact SourceKit request checks. Use compiler entity's exact `effective_access` field as access evidence; allow public-inventory mapping only for `public` or `open`, with one raw entity occurrence and one compiler USR. Require lexical owning enum line to resolve in same pinned interface, then confirm its explicit `public`/`open` modifier when present. Keep missing/unknown access, duplicates, internal/package/private, and context mismatches held. This rule uses compiler-reported effective access; language's enum-case inheritance rule provides independent semantic basis. Do not infer public access from spelling or graph absence.

## Reproduction

From repository root, run:

```sh
python3 factory/catalogue/access-inheritance-spike/run_controls.py
```

This uses pinned Xcode 27.0, SDK 27.0, target `arm64-apple-macosx27.0`, rebuilds compiler fixture module, runs public and negative client typechecks, runs SourceKit fixture indexing, rebuilds exact per-row evidence, then runs four evidence tests. `run-receipt.json` records commands, statuses, output hashes, pinned source link-evidence hash, and input hashes. Raw SDK SourceKit outputs remain intact in compiler-cursor-spike; fixture SourceKit output is retained here.
