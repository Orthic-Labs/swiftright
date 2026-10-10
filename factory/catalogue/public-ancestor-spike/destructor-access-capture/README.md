# Destructor access cursor capture

`capture_destructors.py` selects exactly 42 frozen reconstruction rows with reason `destructor source access semantics require explicit eligibility definition`, then runs one exact `source.request.cursorinfo` request per SwiftUI/SwiftUICore `deinit` source offset. Requests, sourcekit-lsp/xcrun hashes, argv, exit status, stdout, stderr, source bytes, branch conditions, scope lines, raw member kind, USR, owner type metadata, & demangle tree are archived.

`verify_destructors.py` binds frozen link SHA `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`, reconstruction SHA `58cfe1155ea19358637ca43c9ab90dfc183e78ea07f48248111ca22f72a9e65d`, SwiftUI source SHA `155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38`, & SwiftUICore source SHA `4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13`. Tests include accepted baseline plus wrong USR/kind/offset/access inference/exit/source pin faults.

All 42 cursor responses report `source.lang.swift.decl.function.destructor`, exact `deinit` line/name/module, & concrete destructor USR. None emits `key.effective_access`, `key.accessibility`, or `key.access`; verifier records accessibility as `unknown` & rejects inferred values. No eligibility or public/internal conclusion is made.
