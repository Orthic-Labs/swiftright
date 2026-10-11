# SR1 v3 source handoff review

Review is read-only against stable source bundle `factory/native/windows/padding-capture-lease-capture-v3`.

## Pinned inputs

- source map: `source-bundle-map.json`, SHA-256 `66eebcc496af0793714383941820cef037a6469d94a157a19f8daf8249d9526d`
- root manifest: `root-stage-manifest.json`, SHA-256 `51cc818f25949031b5551cf2824ebb966665874ef5d037514e821465f01f3135`
- root gate: `root-entry-gate.json`, SHA-256 `4fd938219c378a96768eb35e7ea22f2fa8d2383fb5c0fe06fdb64b74da6b76ea`
- candidate context: `candidate-context.json`, SHA-256 `705377b54e341e7cfc06eea4394bd7c5b9d92885e56165c0ee928a0e433c8de2`

`verify-source.py` passed 25 offline source checks with zero native/compiler/GUI/remote actions. `test-candidate-fault-controls.py` passed six mutation controls with zero actions. Producer fault controls are present in `test-producer-fault-controls.ps1` but require Windows PowerShell execution.

## Join review

`root-entry.ps1` checks map/manifest membership, exact bytes & hashes, allowlisted paths, fresh output, then runs source-string, producer-fault, & headless controls. It emits `passed-source-gates-consumer-held`; it does not qualify capture output.

`support/integration.ps1` provides exact joins for issued metadata, compile receipt, executable/renderer, source binding, candidate tuple/binding, canonical inputs, Mac context source refs, runtime modules, capture IDs, process handles, raw streams, worker ordering, & release certificates. `Assert-LeaseIssuedMetadata` is called before launch in `capture-repeat.ps1`; it checks `IssuedMetadataHash` against bytes, exact producer paths/hashes, candidate context, Mac20 envelope (`13bfe5b8…` host hash, `c12eaec…` acceptance hash), & source refs.

Candidate acceptance is source-bound observation only: `frozenTupleBound=false`; Mac20 host/context is joined by binary hash, source refs, acceptance config, compiler receipt, & origin archive. No SR1 tuple is frozen.

## Concrete hold

Existing positive/fault controls exercise `Assert-CandidateMetadataAdmission` and Python adapter validation. They do not execute `Assert-LeaseIssuedMetadata` with a complete Windows issued-metadata fixture; Windows PowerShell controls remain required before any native capture. Root should run baseline plus mutations for issued metadata hash, producer path/hash, Mac source ref, candidate tuple ref, capture count/IDs, & runtime module bytes, verifying zero launch actions on each rejection.

No producer source was changed. SR1 remains prospective until root completes Windows controls, actual capture receipts, & downstream review.
