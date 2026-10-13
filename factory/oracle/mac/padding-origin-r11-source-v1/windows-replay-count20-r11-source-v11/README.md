# Fresh r11 Count20 adapter packet

This packet binds fresh case/tuple/source/host identity to Count20 adapter-v6 successor stages. Existing r7 output remains historical; no output is relabeled. Windows archive is intentionally pending.

Use `fresh-count20-adapter-plan-v1.json` as admission input. After root transfers exact Windows archive, require 20 unique `capture/<32 hex>` & `image/<32 hex>` IDs, measured host/clock identity, raw stream seals, all 13 proof roles, runtime tree/modules, compiler/source/exe/renderer joins, & coordinator release proof. `adapter-v7-source/produce-input-map-v7.py --allow-pending` may prepare source map only; strict v7 producer/normalizer, proof-r2, trusted reader & paired comparator require every measured Windows ref. v7 accepts explicit metadata/native roots & optional issued-metadata path, while retaining frozen v6 transforms.

Mac pair inputs are exact archived r11 records under `observed-mac20-r1`; current comparator remains blocked until Windows20 joins. Keep source/case/tuple/host fields exact & keep parity/golden qualification held.

`first-proof-fresh-r11-v11.ps1` is immutable successor for Count1 first-proof calls. It requires explicit `-AdmissionRoot`, validates that root, & passes it to issued-metadata admission; it does not derive archive root from `$PSScriptRoot`.

Root must pass archive/repository root containing measured Count1 `macContext_capture_index`, `macContext_verification`, & `macContext_compiler` files. Each path, byte count & SHA256 remains metadata-bound; missing or relocated rows reject before native action.

`resume-issued-coordinator-fresh-r11-v11.ps1` is Count20 coordinator successor. It requires `-AdmissionRoot`, pins new first-proof source hash, binds fresh r11 source hash, & passes explicit schema dependency path before first-proof dot-source. It retains v10 release, lock, UIA, stream & native guards.

Coordinator overlay stages frozen v10 interactive, dispatch, capture sources by exact hashes from `source-map-v11.json`; those files remain immutable dependencies. Adapter v7 sources are independently hash-pinned in same map.

Run `test-first-proof-admission-v11.ps1 -ConfigPath <actual-config>` headlessly on Windows. Config must provide exact issued metadata, receipts, guards, producer root, & four admission roots. Control expects correct root accepted; wrong, missing & stale roots rejected before lock/native action.
