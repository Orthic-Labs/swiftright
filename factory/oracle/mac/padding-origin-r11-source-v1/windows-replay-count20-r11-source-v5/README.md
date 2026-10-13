# Fresh Count20 r11 integration validator source-v5

v5 replaces only candidate-specific `Assert-CandidateMetadataAdmission` & `Assert-LeaseIssuedMetadata`. Frozen Count1 donor validation delegates to captured frozen functions; common UIA, ordering, raw closure, terminal release, and ownership helpers remain byte-identical. Count20 validation requires metadata v2, fresh `.r11.h<12hex>` case, prefixed tuple IDs, full Mac host hash, fresh case/manifest/tuple/equivalence refs, actual donor compiler receipt closure, 20 prefixed capture IDs, and fresh runtime/renderer joins.

Stage `integration-fresh-r11-v2.ps1` beside v4 overlay under producer-root layout where `..\\..\\support\\integration.ps1` resolves frozen support. Pass its measured hash as `IntegrationGuardHash`; keep v4 coordinator/dispatch/capture bytes unchanged. V5 validator accepts historical donor plan/receipt only as compiled closure and requires fresh case/manifest/equivalence refs separately.

Use `source-map-v5.json` for exact custom-validator & v4 overlay/helper hashes. No compiler, GUI, native, lock, remote, or Git effects occur in source validation.
