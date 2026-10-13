# External owner capture v2

This version records bounded raw evidence for 24 non-Swift-stdlib owners used by SwiftUI extension rows. It joins exact pinned SDK interface or Clang header declarations, SwiftUI external-extension source lines, SourceKit reference USRs, request/output bytes, tool hashes, typecheck argv, exits, & source hashes.

Owners include Foundation, Observation, DeveloperToolsSupport, AppKit, Combine, CoreFoundation, Spatial, & Symbols. `Spatial.Size3D` has exact compiler USR but no declaration in its public swiftinterface; it remains explicitly held. Clang imported owners retain header evidence & imported USRs.

No public-ancestor, access, eligibility, or graph-absence conclusion is made. Unknown/missing source joins remain held.

Run `python3 capture_external_modules.py` to regenerate `external-owner-evidence-v2.json`; run `python3 test_external_modules.py` to replay immutable bindings.
