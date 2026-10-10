# SR0 tuple 11: Dell staging record (11 October 2026)

## SUPERSEDING NOTE (current staging)

Tuple 11 = tuple 10 plus only the FreshOnBridge host fix. `D:\Claude\sr0-r11\src` is now on clone-local branch `tuple11-local`:
base `0a745ab` (`0a745abca1391d266331940b70fe6a305f1a7039`), `git cherry-pick -x 2cfb36ef` applied cleanly (exit 0), clone-local commit `a75df9f5ac20b8cb1eb9cf97b8b6f168512464f6` (not pushed). `git diff 0a745ab --stat`: 2 files (`BridgeBackend.swift`, `SelfTest.swift` under `probes/sr0-s/fresh-on-bridge/Sources/FreshOnBridge`), 31 insertions, 7 deletions. `git diff 0a745ab` patch sha256 `C1CC24AB7046E6C8C5F4F4A3609DE1AD08C6014B789BFE4DE83DCC2CA80315C7` (file `D:\Claude\sr0-r11\tuple11-vs-0a745ab.patch`, same hash).

**FreshOnBridge.exe (current): `073513142F25C454B58DD05E545875E90B157539C72977E855AD68785293D55E`** (built by `build-fresh.ps1`, 41.9 s; `verify-artifacts` and `verify-manifest` re-run with this hash, see the verify11b log). The runtime is the 8e47b89/0a745ab runtime, so WorkloadWin `5270D3E5…` (built at 8e47b89, runtime unchanged through 0a745ab) is consistent and the WARNING below no longer applies. The `C8F0674D…` build and everything below describing a `2cfb36ef` checkout is SUPERSEDED. Scripts: `pick11.ps1`, log `pick11.log`, in `D:\Claude\sr0-r10\stage-tools\`.

Staged at `D:\Claude\sr0-r11` from commit `2cfb36ef` (`2cfb36ef5808c2ba0fface1b52f31c3ecc6b2e14`). New root; `sr0-r10` and `sr0-r09` untouched. Build and copy only; no GUI, no scheduled task, nothing deleted on the Dell. Only FreshOnBridge was rebuilt; everything else was copied from `D:\Claude\sr0-r10` (robocopy, no purge) and hash-checked.

## WARNING: WorkloadWin is NOT built from this commit

The brief assumed only the FreshOnBridge host changed. `git diff 8e47b89 2cfb36ef -- probes/sr0-s/fresh-runtime` is NOT empty: 14 runtime source files changed (about 27 commits, `feat(runtime): add ...` APIs, layout engine, Graph.swift). `probes/sr0-b/workload/Package.swift:30` depends on `../../sr0-s/fresh-runtime`, so the WorkloadWin exe copied here (built from 8e47b89) does not contain these runtime changes. It does not link FreshOnBridge host sources (`Package.swift` has no `fresh-on-bridge` path), but it does link the runtime. If the workload lane must run the 2cfb36ef runtime, rebuild WorkloadWin from `D:\Claude\sr0-r11\src` (same scripts as `docs/sr0-tuple10-staging.md` section 3). `packages/`, `render/`, BridgeSmoke and BridgeGeoModal sources are unchanged, so those copies are consistent.

## Pins (sha256)

| Member | Path (Dell) | sha256 | Status |
|---|---|---|---|
| Renderer DLL | `D:\Claude\sr0-r11\renderer\swiftright_render.dll` | `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` | unchanged, all copies verified |
| FreshOnBridge.exe | `D:\Claude\sr0-r11\src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` | `C8F0674D97D339D1A546277D9177C24394028D851B5F440E9E07F81DE9B6E805` | NEW (tuple 10: `F136046B…`), built from 2cfb36ef in 60.6 s |
| WorkloadWin.exe | `D:\Claude\sr0-r11\workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe` | `5270D3E54C1BD8FB625A2BE20EDFE12C31DD92686426457FDBED8FBA705124E7` | copied from r10 (built from 8e47b89; see warning); `build.json` exe path rewritten to r11, `staged_from` added; `incremental.json` copied (r10 record: 0 Rust invocations) |
| BridgeSmoke.exe | `D:\Claude\sr0-r11\smoke\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe` | `85D5F8BA798EF17367844F28D75F3E53A37323F13A8409397C7C3FD1AD563EEA` | unchanged |
| BridgePixels.exe | `D:\Claude\sr0-r11\smoke\bin\BridgePixels.exe` | `452110B5508533751F2E70C69D1008F484BD5C833C3F743850B7ACE50DABD0F7` | unchanged |
| TextGeom06 / Modal06 / ColdOpen06 | `D:\Claude\sr0-r11\geomodal\bin\` | `CDEA68FD…9607` / `E7CC6615…8FB9` / `F7742CA8…9157` (full values in `docs/sr0-tuple10-staging.md`) | unchanged |

Layout as `docs/sr0-tuple10-staging.md` section 2 (no `slicecheck\` in r11). Scripts: `stage11.ps1`, `verify11.ps1` and logs in `D:\Claude\sr0-r10\stage-tools\`.

## Verification (offline)

- FreshOnBridge `verify-artifacts.ps1 -ExpectExe C8F0674D… -ExpectDll E280F4A9…`: `ARTIFACT_OK`; `verify-manifest.ps1`: `manifest=OK comctl32-v6`.
- WorkloadWin `verify-artifacts.ps1 -ExpectExe 5270D3E5… -ExpectDll E280F4A9…`: `ARTIFACT_OK`; `verify-manifest.ps1`: `manifest=OK comctl32-v6`; `build.json` exe hash equals the file.
- BridgeSmoke, BridgePixels (both copies), TextGeom06, Modal06, ColdOpen06: `UNCHANGED`. Renderer: `E280F4A9 OK` at every copy.
- NOT RUN: any window or self-test run; SliceApp compile check (not requested).

## Script defaults to change (from sr0-r10 values)

`sr0-r10` becomes `sr0-r11`; FreshOnBridge `F136046BEFE7EE9900D3466F03D540430E8D84477B8A9089E87497CACEE99F19` becomes `C8F0674D97D339D1A546277D9177C24394028D851B5F440E9E07F81DE9B6E805`; WorkloadWin `5270D3E5…` stays only if the copy is accepted.

Locations: `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh:22` (BASE_DIR), `:23` (EXPECT_EXE_SHA256); `probes/sr0-b/native-interaction/scripts/run-native.sh:12`, `:13`; `probes/sr0-b/workload/scripts/run-workload.ps1:12` (-Base); `probes/sr0-o/f1-cross/scripts/schedule-cross.ps1:5`, `run-cross.ps1:10`, `win-cross.sh:9` (Bin); `qualification/run.py:95` (SMOKE_BASE), `:102` (F1_TREE, comment "tuple 10"). `qualification/test_run.py:1748` names `F136046B` in a docstring only. Not changed since tuple 10: `qualification/tuple-final.json:19,28` and `test_run.py:1024-1025` (still tuple 08 values), and the leftovers listed in `docs/sr0-tuple10-staging.md` section 5.
