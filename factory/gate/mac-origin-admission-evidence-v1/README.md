# Mac origin admission v1

`factory.gate.mac_origin_admission.mac_origin_admission_issues(capture, reader)` is an origin-only F10 callback. `reader(ref)` receives exact `{path, sha256, bytes?}` refs & returns raw bytes. Capture must bind `macOrigin.version=1` with `summary`, `case`, `source`, `binary`, & `compilerReceipt` refs. Optional `auxiliaryAX` binds `receipt`, `source`, & `binary` refs.

Verifier checks candidate policy, canonical case identity, main summary/receipt/source/binary joins, resolver/compiler argv, cwd, tool pre/post hashes, owned PID/PGID, UTC timing, natural exit, cleanup, raw stream hashes, source drift, & optional AX joins. Missing origin fails closed. Result remains `candidateOnly=true`, `parityGranted=false`, & `promotionEligible=false`.

Focused tests cover positive admission plus missing/copy/wrong-case/source/tool/PID/AX/drift/stream faults. `test-receipt.json` records one bounded Python test invocation; no compiler or native capture ran.
