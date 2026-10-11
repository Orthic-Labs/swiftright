# Strict bounded Clang owner guard

`ExactClangOwners` reconstructs 12 requested external owners & NSControl support from genuine `clang-external-process-v3` full AST streams, exact physical SDK headers, direct module umbrella/export edges, ordinary import C USRs & `clang-nominal-import-v2` inferred variable trees. No producer eligibility flags or filtered AST rows participate.

`validate()` returns 12 rows. `supportRows` contains NSControl. Each row preserves physical module/header provenance separately from actual compiled namespace/path/kind & exact `nominalTree`. NSControl.ControlSize resolves individually to captured `__C.NSControlSize` Structure; Spatial.Size3D resolves individually to captured `__C.SPSize3D` TypeAlias.

Constructor accepts `inputs=completeByteMap` or `read_bytes=resolver.read_bytes, force_archive=True`. Original recorded paths stay semantic bindings for requests, compiler argv & source positions. Captured header aliases are exact per-file byte identities established before archive hydration. `validate_overrides(actualByteOverrides)` mirrors only descriptors for identical original files, then runs complete production validation.

`capture-inputs.json` pins all source, request, process, stdout/stderr, module/export, tool & nominal-tree bytes. `build_inputs.py` archives existing capture descriptors; it never executes tools. `ast_reader.py` parses full translation units incrementally, rejects malformed/duplicate JSON structure, restores physical location printer state & preserves declaration ancestry. Every definition joins a complete source declaration; enum/struct/union typedefs join actual type IDs/redeclaration chains. Compiler input & tool archive ownership belongs to shared archive resolver.

`test_exact_clang.py` runs changed-byte faults after accepted full baselines, requiring specific semantic rejections. Raw AST controls preserve entire genuine streams; they never replace them with producer summaries. `versioned-snapshots/` & `producer-preimage-v2/` retain earlier rejected or historical bytes. V2 AST receipts lacking explicit target & nominal-v1 demangler tool mismatch are historical.

Public source/header/import correspondences are bounded certificates for these exact identities. Full catalogue denominator & effective public ancestor proof is built by separate production guard.
