# SR0 tuple 10: Dell staging record (10 October 2026)

Staged at `D:\Claude\sr0-r10` (a NEW root; `D:\Claude\sr0-r09` is untouched) from commit `8e47b89` (`8e47b89b3e9ae488e77ea8b5a2e4663053601c0d`; runtime change: launch initial focus selects all). Build and copy only: no GUI, no scheduled task, no desktop run, nothing deleted on the Dell. Renderer unchanged (`E280F4A9`). `git diff be9a922 8e47b89` over `packages/`, `render/`, `examples/BridgeSmoke/{Sources,Package.swift}` and `examples/BridgeGeoModal/{Sources,Package.swift}` is empty, so those members are copied from sr0-r09 (robocopy, no purge) and their hashes re-verified; only FreshOnBridge and WorkloadWin (which link `fresh-runtime`) were rebuilt.

## 1. Pins (sha256)

| Member | Path (Dell) | Bytes | sha256 | Status vs tuple 09 |
|---|---|---:|---|---|
| Renderer DLL | `D:\Claude\sr0-r10\renderer\swiftright_render.dll` | 11,885,056 | `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` | unchanged (all copies verified) |
| FreshOnBridge.exe | `D:\Claude\sr0-r10\src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` | 4,204,032 | `F136046BEFE7EE9900D3466F03D540430E8D84477B8A9089E87497CACEE99F19` | NEW (was `8650BBFC…`) |
| WorkloadWin.exe | `D:\Claude\sr0-r10\workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe` | 4,714,496 | `5270D3E54C1BD8FB625A2BE20EDFE12C31DD92686426457FDBED8FBA705124E7` | NEW (was `27E781B8…`) |
| BridgeSmoke.exe | `D:\Claude\sr0-r10\smoke\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe` | 1,017,344 | `85D5F8BA798EF17367844F28D75F3E53A37323F13A8409397C7C3FD1AD563EEA` | unchanged (copied) |
| BridgePixels.exe | `D:\Claude\sr0-r10\smoke\bin\BridgePixels.exe` (and `smoke\scratch\...`) | 660,992 | `452110B5508533751F2E70C69D1008F484BD5C833C3F743850B7ACE50DABD0F7` | unchanged (copied) |
| TextGeom06.exe | `D:\Claude\sr0-r10\geomodal\bin\TextGeom06.exe` | 1,053,696 | `CDEA68FDEC10D83405BCE5E7C622402C2935AFA1886A8C20C6CB039C2AD99607` | unchanged (copied) |
| Modal06.exe | `D:\Claude\sr0-r10\geomodal\bin\Modal06.exe` | 965,120 | `E7CC66159027654EBAD963835E9593292F3A834DC116634848D8C312B5E08FB9` | unchanged (copied) |
| ColdOpen06.exe | `D:\Claude\sr0-r10\geomodal\bin\ColdOpen06.exe` | 776,704 | `F7742CA8EFB07DA73EE0512ADB7FF08114E513CCE4549F860AE177343F939157` | unchanged (copied) |
| SliceApp.exe (compile check only) | `D:\Claude\sr0-r10\slicecheck\examples\SliceApp\.build\payload\SliceApp.exe` | 3,380,224 | `E074B5223E6437896D50ADB8157866DEA7AFF5E42C06F98ACCB51B389C5F014B` | not a tuple member |

Toolchain unchanged (Swift 6.4, `docs/sr0-tuple07-staging.md` section 1 runtime DLL table).

## 2. Layout under `D:\Claude\sr0-r10`

Same as `docs/sr0-tuple09-staging.md` section 2: `renderer\`, `src\` (fresh clone, detached at 8e47b89, FreshOnBridge built in `src\scratch\out\Products\Release-windows-x86_64`, `src\payload\bin`), `smoke\` and `geomodal\` (copies of the sr0-r09 trees, still holding the `bece2a8` copies of their scripts), `workload\` (sources from the clone, `build.json` for the new exe, `incremental.json`, `SOURCE-HEAD.txt` = 8e47b89..., empty `runs\`), `slicecheck\` (local clone at 8e47b89), `stage-tools\` (empty; the scripts `stage10.ps1`, `slice10.ps1`, `verify10.ps1` and their logs `stage10.log`, `slice10.log`, `verify10.log` are in `D:\Claude\sr0-r09\stage-tools\`).

## 3. Build commands

`stage10.ps1` (a `-File`, BelowNormal): copy renderer from sr0-r09 and hash-check; `git clone https://github.com/bogusyogi/swiftright src` + `checkout --detach 8e47b89`; robocopy `smoke\`, `geomodal\`; `build-fresh.ps1 -Base D:\Claude\sr0-r10\src -Dll ...\renderer\swiftright_render.dll -ExpectDllSha256 E280F4A9...` (48.3 s); robocopy workload sources; `build-workload.ps1 -Base D:\Claude\sr0-r10\workload -Dll ...\workload\payload\bin\swiftright_render.dll -ExpectDllSha256 E280F4A9...` (105.6 s, writes `build.json`; `staged_from`/`staged_utc` added); `build-incremental.ps1 -Base D:\Claude\sr0-r10\workload`. `slice10.ps1`: clone `src` to `slicecheck`, fetch GitHub master, checkout 8e47b89, `examples\SliceApp\scripts\build-windows.ps1`.

W7 record `workload\incremental.json`: 3 edits (13.1, 12.3, 8.0 s, all exit 0), `rust_invocations_total=0`, `hashes_identical=True`, `builds_ok=True`; the exe hash is unchanged after the builds. The analyzer finds it from `workload\runs\<tag>` via `..\..\incremental.json`.

## 4. Verification (offline; `verify10.ps1`, log `verify10.log`)

| Check | Result |
|---|---|
| FreshOnBridge `verify-artifacts.ps1 -Base D:\Claude\sr0-r10\src -ExpectExe F136046B… -ExpectDll E280F4A9…` | `ARTIFACT_OK` |
| FreshOnBridge `verify-manifest.ps1` | `manifest=OK comctl32-v6` |
| WorkloadWin `verify-artifacts.ps1 -Base D:\Claude\sr0-r10\workload -ExpectExe 5270D3E5… -ExpectDll E280F4A9…` | `ARTIFACT_OK` |
| WorkloadWin `verify-manifest.ps1` | `manifest=OK comctl32-v6` |
| `workload\build.json` | `exe_sha256` = file hash = `5270D3E5…`, `source_head` 8e47b89... |
| BridgeSmoke, BridgePixels (both copies), TextGeom06, Modal06, ColdOpen06 | all `UNCHANGED` against sr0-r09 |
| Renderer DLL, every copy under sr0-r10 | `E280F4A9 OK`, no mismatch |
| SliceApp compile check at 8e47b89 (build only) | `swift build exit=0`, no `warning:` line, ComCtl v6 + PerMonitorV2 manifest ok |
| FreshOnBridge `--self-test`, any run of any exe, geomodal dry run | NOT RUN (the dry run was not repeated: its binaries are byte-identical to sr0-r09, where it passed) |

## 5. Script defaults to change (read from the repo at 8e47b89)

`sr0-r09` becomes `sr0-r10`; FreshOnBridge `8650BBFC4118F0793D71F84A51077D23D076E7DD1AA144C2AE7B60BAC27161C8` becomes `F136046BEFE7EE9900D3466F03D540430E8D84477B8A9089E87497CACEE99F19`; WorkloadWin `27E781B8…` becomes `5270D3E54C1BD8FB625A2BE20EDFE12C31DD92686426457FDBED8FBA705124E7`. BridgeSmoke `85D5F8BA…` stays.

- `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh:22` `BASE_DIR`; `:23` `EXPECT_EXE_SHA256`.
- `probes/sr0-b/native-interaction/scripts/run-native.sh:12` `BASE_DIR`; `:13` `EXPECT_EXE_SHA256`.
- `probes/sr0-b/workload/scripts/run-workload.ps1:12` `-Base` (no exe-hash default; pass `-ExpectExe 5270D3E5…` to `verify-artifacts.ps1`).
- `probes/sr0-o/f1-cross/scripts/schedule-cross.ps1:5`, `run-cross.ps1:10` `-Bin`, `win-cross.sh:9` `BIN`.
- `qualification/run.py:95` `SMOKE_BASE` (comment: tuple 09), `:102` `F1_TREE` (comment: tuple 09). `qualification/test_run.py:1743` mentions `8650BBFC` in a docstring only.
- Still on tuple 08 values: `qualification/tuple-final.json:19` (`7673a2d5…`) and `:28` (`21992f16…`) and their `source` citations; `qualification/test_run.py:1024-1025` prefixes `7673a2d5`, `21992f16`. Targets: FreshOnBridge `f136046befe7ee9900d3466f03d540430e8d84477b8a9089e87497cacee99f19` (prefix `f136046`), BridgeSmoke `85d5f8ba798ef17367844f28d75f3e53a37323f13a8409397c7c3fd1ad563eea` (prefix `85d5f8b`).
- `factory/native/windows/` hard-codes `D:\Claude\sr0-r09` (`adapter.py:9`, `inventory.ps1:3`, `compile-probe.ps1:14`, `capture-native.ps1:12,25,83`, `typecheck-probes.ps1:7`, and the `stage-inventory*.json` files); those bind sr0-r09 and are left for the factory owner to decide.
- Unedited r08 leftovers (see `docs/sr0-tuple09-staging.md` section 6): `build-pixels.ps1:6`, `drive-pixels.ps1:16`, `drive-coldopen.ps1:15`, `recycle-stage.ps1:5`, `gpu-routing.ps1:2`, `w5-ab.ps1:3`, `dll-strings.ps1:2`, `examples/SliceApp/Windows/renderer-pin.json:9`.

## 6. Run commands

```
BASE_DIR='D:\\Claude\\sr0-r10\\src' EXPECT_EXE_SHA256=F136046BEFE7EE9900D3466F03D540430E8D84477B8A9089E87497CACEE99F19 \
  EXPECT_DLL_SHA256=E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93 sh probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r10\workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Base D:\Claude\sr0-r10\workload"
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r10\smoke\examples\BridgeSmoke\scripts\schedule-smoke.ps1 -Base D:\Claude\sr0-r10\smoke -Tag <tag>"
```
