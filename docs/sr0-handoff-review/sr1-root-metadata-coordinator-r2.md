# SR1 root-metadata coordinator review r2

Read-only review of prospective Count1 r2 source, SHA256 `f00ce48b5219a70c8214792a1aeecefcab26d2c201620a178c32b01ce857e2d0`.

## BLOCKED_PENDING_PATH_LAYOUT_AND_DELL_RUN

- Source admission passed locally with `python3 .../test-resume-source-admission.py`: status `passed-source-only`, issued metadata `26ab10c102f2536110c373271cb377d8acda1a6983cb1f8e00238ff4e49d74d2`, guard `79845ab43e27467e727e475da1734097f4977963f2be0b65a397c938629743e5`, schema receipt `5b0ca56887147453a26c658fbff086ad07f7cdfaec010c8f7d2f426dc9dfe48a`, native/lock actions `0`.
- Archived actual fixture joins pass: 12 candidate-context Mac refs are unique & match local path, SHA-256, & byte count; tuple ref is `40b1a3cb...` / 11041; schema is `d319f074...` / 3784; verifier is `4ab3aedc...` / 2678; source archive is `21fe0b64...` / 1641; schema `rootNonce` equals issued `runID`; issued `sourceHash` equals archived Witness source; source/archive refs share hash & bytes. Current fixture source archive path exists.
- Archived `execute-controls-r2` exited 0 with `ROOT_TRANSPORT_PARSE_PASS count=76` & `ROOT_HEADLESS_CONTROLS_RETURNED`; this is transport/source parsing only, not Count1 coordinator execution, lock acquisition, or native launch.
- **Executable blocker:** `root-metadata-controls-r2/resume-issued-coordinator-r2.ps1:17` sets `$here` to `Join-Path $PSScriptRoot '..'`. From archived nested location this resolves `...\root-metadata-controls-v1`, while line 18 requires capture root `...\padding-capture-lease-capture-v3`. Same wrong root affects support helpers, integration bindings, control root, schema path, & receipt paths. Producer must relocate wrapper or compute two parents, then refresh source hash & manifest before any Dell run.
- **Join hardening required:** line 58 validates `sourceArchiveRef.path` only as nonempty, hash as regex, & bytes positive. It does not bind path to an existing file or recompute hash/bytes. Current fixture has matching source/archive values, but source code must enforce actual receipt bytes before coordinator PASS.

Preserve executed r1 & r2 transport receipts. Next root actions: repair prospective path layout, add sourceArchiveRef file/hash/bytes check, rerun source admission, then run Count1 in fresh namespace with no native claim until terminal receipt proves it.
