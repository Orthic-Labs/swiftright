# Projected variable cursor capture

`capture_projected_variables.py` ran six exact `source.request.cursorinfo` requests against Xcode 27A266 SwiftUI interface bytes. Requests use UTF-8 byte offsets for source lines 4080, 5533, 9717, 23750, 31446, & 32822. Each request stores request bytes, compiler arguments, sourcekit-lsp/xcrun hashes, exit status, stdout, & stderr. `swift-demangle --expand` stores raw USR input/tree output.

`verify_projected_variables.py` binds frozen link evidence SHA `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`, SwiftUI source SHA `155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38`, & frozen duplicate archive SHA `5287ecdbd267d2d30196855233ee285914b7e6bb4c24e25dafa911386bb1c89f`. Tests include accepted baseline plus wrong USR, offset, context, third duplicate, exit, & source-pin faults.

Cursorinfo at projected-property offsets returns backing-property identity: `isOn`, `isExpanded`, `document`, & `selection` USRs on preceding source lines. Frozen index output retains projected `$isOn`, `$isExpanded`, `$document`, & `$selection` USRs with exact duplicate raw records. `switch` row 31446 resolves directly to unique static var identity.
