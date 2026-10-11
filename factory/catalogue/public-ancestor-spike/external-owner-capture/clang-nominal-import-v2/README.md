# Inferred nominal import supplement v2

This supplement captures 13 ordinary inferred `let` metatype bindings: 12 requested external owners plus `AppKit.NSControl` outer-owner support. Probe declarations contain no `Any.Type` annotations.

`run_capture.py` executes four actual processes: Swift typecheck, Swift AST dump, SourceKit index request, and `swift-demangle --expand` over raw SourceKit variable USRs. Swift processes carry explicit `-sdk` and `-target arm64-apple-macosx27.0`. Receipts preserve argv, cwd, timestamps, tool hashes, source/request/stdin bindings, complete stdout/stderr, and return codes.

Evidence binds each SourceKit variable declaration to same-line nominal CUSR, compiler inferred interface type, physical probe token, and full demangle tree. Demangle output records imported `__C` nominal roots exactly; no namespace alias is inferred. `test_nominal.py` rejects wrong source, variable USR, nominal USR, compiler type, demangle tree, process target, and frozen-v3 pin mutations.

Frozen v3 links are content-addressed: evidence `60de7e63881e6585fd8285c752ba0ae780e486461a8e64174fc6d721059c14b3`, process receipt `17e1b678d581ec0b5b6b8d38ceafd174760b85b4b84a7be6922b776aa8cdcc63`, stage manifest `3091ffe6a63c754be0bec457a302b81bf142e1e5c8ce28c4bb5662d616fe245e`.

Latest supplement evidence SHA: `37592ad663649512de3968b11d54203fa83fef816e8b1c4ba32ef7a20d32b6ca`.

Stage manifest records 19 local files, 9 frozen-v3 refs, 21 external semantic dependencies, and 4 repository archive refs.
