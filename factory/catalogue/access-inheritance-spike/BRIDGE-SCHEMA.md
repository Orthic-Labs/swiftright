# Exact enum-case access bridge

`derived-access-bridge.json` records compiler-backed access for 51 enum cases held by the immutable source link evidence. `exact_access_bridge.py` rebuilds it only after checking request identity, pinned compiler/SourceKit tool bytes, SDK settings, live SwiftUI & SwiftUICore interface bytes, raw index responses, and seed evidence hashes.

Each accepted row binds `auditRowKey`, module, interface hash, line, name, full context, one non-implicit raw `source.lang.swift.decl.enumelement` record, compiler USR, effective access, and every lexical enclosing type with exact source range and resolved access. Promotion requires exact module/name/line/context agreement, one raw entity, nearest owner kind `enum`, and explicit `public` or `open` access on every enclosing type. Extensions resolve only to a unique declaration with exact module-relative qualified owner; basename matches cannot transfer access from another type. For extensions of nested types, `resolvedOwnerChain` preserves every original nominal ancestor and its declaration range/access; ancestors are checked even though extension body appears outside their lexical braces. Private, internal, package, fileprivate, less-than-fileprivate, unknown, absent, duplicate, mismatched, or unresolved records fail closed.

The explicit enclosing-type check is deliberately conservative. Swift's language reference says enum cases inherit the access level of their enum; the bridge additionally requires all outer type contexts to be public/open and checks compiler-reported effective access. This excludes cases nested under a less-visible scope. See [Swift Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/).

Run from repository root:

```sh
python3 factory/catalogue/access-inheritance-spike/exact_access_bridge.py
python3 -m unittest factory/catalogue/access-inheritance-spike/test_exact_access_bridge.py
```

`derived-access-bridge.json` is a derived receipt; original `access-evidence.json`, its `sha256-manifest.txt`, compiler cursor evidence, and source outputs are not rewritten. `bridge-manifest.txt` hashes only bridge-specific files.
