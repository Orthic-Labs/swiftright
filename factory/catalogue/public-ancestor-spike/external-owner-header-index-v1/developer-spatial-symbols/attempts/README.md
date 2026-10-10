Attempt ledger:

- Initial capture invocation produced DeveloperToolsSupport & Spatial raw outputs, then helper parser rejected imported-C Spatial `Size3D` while preserving exit-0 raw bytes. Those outputs were superseded by corrected parser invocation & are not accepted evidence; no separate pre-parser copies remain.
- Corrected invocation produced final DeveloperToolsSupport, Spatial, & Symbols outputs; CoreFoundation then exited 1 because `-enable-experimental-concurrency` was not forwarded. That exact failed request/output is preserved under `attempts/failed/`.
- Final CoreFoundation invocation forwarded `-enable-experimental-concurrency` through `-Xfrontend` & exited 0. No test runner or eligibility tool was used.
