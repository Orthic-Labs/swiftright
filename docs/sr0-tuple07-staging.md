# SR0 tuple 07: Dell staging record (10 October 2026)

Staged at `D:\Claude\sr0-r07` on the Dell from HEAD `02b3cc0` (pushed). Build and copy only: no GUI, no scheduled task, no desktop run, no commit. Supersedes nothing yet: the final tuple (`docs/sr0-snapshot.md` section 2c, `qualification/tuple-final.json`) is unchanged until the lead edits the pins listed in section 5.

Two changes against the final tuple: the renderer modal fix (`02b3cc0`, `render/swiftright-render`, no ABI change) and the FreshOnBridge release gate (`c0fc401`, `SelfTest.swift`: `releaseSignalPresent()`, env `SR0O_RELEASE_FLAG`; unset = release immediately).

## 1. Pins (sha256)

| Member | Path (Dell) | Bytes | sha256 | Status vs final tuple |
|---|---|---:|---|---|
| Renderer DLL (07) | `D:\Claude\sr0-r07\renderer\swiftright_render.dll` | 11,882,496 | `97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B` | NEW (was `7533963D…`) |
| FreshOnBridge.exe | `D:\Claude\sr0-r07\src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` | 4,087,296 | `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960` | NEW (was `AA4353CE…`, 4,087,808 bytes) |
| BridgeSmoke.exe | `D:\Claude\sr0-r07\smoke\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe` | 1,004,544 | `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5` | UNCHANGED (copied from `D:\Claude\sr0b-abi06c`) |
| WorkloadWin.exe | `D:\Claude\sr0-r07\workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe` | 4,669,440 | `0815DF499371CEDE032758B00A6B254726DD524B9A0930C2D96B57089A74070F` | UNCHANGED (copied from `D:\Claude\sr0b-workload`; full hash now recorded here, it was prefix-only in `docs/sr0-snapshot.md`) |

The renderer DLL sits beside each exe and under each tree's `payload\bin\` (same bytes, all hash-checked 97CA28E8). FreshOnBridge `scratch\out\...` and `payload\bin` are untracked build output in a clone whose tracked files equal `02b3cc0` (`git status`: only `payload/`, `scratch/`).

Swift runtime DLLs: none are copied beside the exes (same as the final trees). The drive scripts put `C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin` on PATH. Toolchain: Swift 6.4 (swift-6.4-RELEASE), x86_64-unknown-windows-msvc, +assertions (`Toolchains\6.4.0+Asserts`). Imported runtime DLLs (BridgeSmoke imports all but `swiftObservation.dll`; FreshOnBridge and WorkloadWin import all of them), hashes read from that directory:

| DLL | Bytes | sha256 |
|---|---:|---|
| swiftCore.dll | 6,064,128 | `3C881EFBCDDBCA632D2DCE2F4D59F6B3D53D7A02782CA1BA7A3CB5D9C698F0FA` |
| swift_Concurrency.dll | 522,752 | `B85A4F0817981A4455D5324DBD626A40206328F6066767B5483C46FD5C852EC6` |
| swiftCRT.dll | 38,912 | `1739C6E1370812BBB78B6CB6F5A8943E23E3A23B804123141039FB7D636C94C9` |
| swiftDispatch.dll | 145,408 | `E49FB75A23452E321F90FD7518E0787874E78029365F30EC18531C44CAB7A4DA` |
| swiftObservation.dll | 120,320 | `1A6616A1ACB1EA1DF44EA590D7944936996894DE7ED481414CB37D0EB1A52166` |
| Foundation.dll | 4,680,192 | `1641656145C1CC386FFD75DBC2627A95E2EC28A492B1B565B9F02AA3DB14DAD0` |
| FoundationEssentials.dll | 5,712,896 | `C622B8AA08C4B0F2FAC7BF0B6D60642C3FBB8EC1DB91B3E8231CA39B012AB932` |
| dispatch.dll | 236,032 | `3B2BF951E308B135C7467477722B3AE694A518D25E5B48C93A9A78B3A7043057` |
| BlocksRuntime.dll | 11,776 | `A7B0433EF9C1315388D5CD526F6A1E77506FA9570A9DC3FA9C1818ADD5F4E22A` |
| VCRUNTIME140.dll | 120,432 | `DA72E6677BD1BCD01C453C1998AAA19AEAF6659F4774CF6848409DA8232A95B2` |

## 2. Layout under `D:\Claude\sr0-r07`

```
renderer\swiftright_render.dll                 97CA28E8 (copied out of sr0-modalfix\bin first, hash re-verified; sr0-modalfix\payload\bin held the same bytes)
src\                                           git clone of bogusyogi/swiftright, detached at 02b3cc0 = the FreshOnBridge tree (Base)
  probes\sr0-s\fresh-on-bridge\scripts\        verify-artifacts.ps1, schedule-fixture.ps1, drive-fixture.ps1 ... (committed 02b3cc0 versions)
  probes\sr0-b\native-interaction\scripts\     present from the clone; run-native.sh also stages its own copy at run time
  scratch\out\Products\Release-windows-x86_64\ FreshOnBridge.exe, swiftright_render.dll
  payload\bin\swiftright_render.dll
smoke\                                         BridgeSmoke tree (Base)
  examples\BridgeSmoke\{scripts,Sources,Package.swift}   from the clone (result-*.txt history excluded)
  scratch\out\Products\Release-windows-x86_64\ BridgeSmoke.exe (unchanged), swiftright_render.dll (07)
  payload\bin\swiftright_render.dll
workload\                                      WorkloadWin tree (Base)
  probes\sr0-b\workload\{scripts,analysis,Sources,Package.swift}, probes\sr0-s\fresh-runtime, packages\SwiftRightBridge, render\swiftright-abi\include   from the clone
  scratch\out\Products\Release-windows-x86_64\ WorkloadWin.exe (unchanged), swiftright_render.dll (07)
  payload\bin\swiftright_render.dll
  build.json                                   exe path and hashes for the new tree (written by staging; build_seconds/source_head/swift/built_utc carried over from the old build.json, plus staged_from, staged_utc)
  SOURCE-HEAD.txt                              copied from sr0b-workload (the exe's own source note: edb1784 + uncommitted R10 changes)
  runs\                                        empty
stage-tools\build-fresh-lowprio.ps1            launcher used for the FreshOnBridge build (BelowNormal priority)
```

Scripts in `smoke\` and `workload\` are copies of the `02b3cc0` committed versions. If their defaults are edited in the repo (section 5), either pass the parameters explicitly or re-copy; do not `git pull` in `src` (it would move the tree off the commit the exe was built from).

## 3. Build and staging commands

FreshOnBridge (`src` clone, build exactly as the 06f tree: `build-fresh.ps1`, release, ComCtl v6 `/MANIFEST:EMBED` dependency, scratch `src\scratch`, renderer DLL beside the exe and under `payload\bin`):

```
git clone https://github.com/bogusyogi/swiftright D:\Claude\sr0-r07\src
git -C D:\Claude\sr0-r07\src checkout --detach 02b3cc0
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r07\stage-tools\build-fresh-lowprio.ps1"
```

where the launcher sets `BelowNormal` priority (another agent had a desktop proof running) and calls:

```
D:\Claude\sr0-r07\src\probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1 -Base D:\Claude\sr0-r07\src -Dll D:\Claude\sr0-r07\renderer\swiftright_render.dll -ExpectDllSha256 97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B
```

Inside it: `swift build -c release --scratch-path D:\Claude\sr0-r07\src\scratch -Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"` from `src\probes\sr0-s\fresh-on-bridge`. Build complete in 27.7 s; build-fresh.ps1 printed `dll_bin_sha256` and `dll_payload_sha256` = 97CA28E8 and `exe_sha256` = 7673A2D5.

Pitfall: run the build as a `-File` (as above). Under `-EncodedCommand` the swift compiler's stderr warnings become terminating errors (`$ErrorActionPreference = 'Stop'` in build-fresh.ps1), and the build stops at "NativeCommandError" with no binary copied (two attempts failed this way, no output was produced).

BridgeSmoke and WorkloadWin: no build. Staging copied the existing exes (source hashes checked before the copy, `21992F16` and `0815DF49`, and re-checked after), the 07 DLL next to each, the scripts from the clone, and wrote `workload\build.json`.

## 4. Verification (offline, no window opened)

| Check | Result |
|---|---|
| `src\...\fresh-on-bridge\scripts\verify-artifacts.ps1 -Base D:\Claude\sr0-r07\src -ExpectExe 7673A2D5… -ExpectDll 97CA28E8…` | `ARTIFACT_OK` |
| `...\verify-manifest.ps1 -Base D:\Claude\sr0-r07\src` (mt.exe) | `manifest=OK comctl32-v6` |
| `workload\...\verify-artifacts.ps1 -Base D:\Claude\sr0-r07\workload -ExpectExe 0815DF49… -ExpectDll 97CA28E8…` | `ARTIFACT_OK` (its `-ExpectDll` default is still `7533963D…`, so it must be passed) |
| `workload\...\verify-manifest.ps1 -Base D:\Claude\sr0-r07\workload` | `manifest=OK comctl32-v6` |
| BridgeSmoke (no verify script exists): exe 21992F16 unchanged, DLL in bin and payload = 97CA28E8, mt.exe manifest | OK, `comctl32-v6` present |
| FreshOnBridge `--self-test` | NOT RUN: it opens a window (renderer window plus driven input), skipped by instruction |
| Headless runs of the other exes | not run |

## 5. Renderer provenance (RightKit build `rr-1791600938761-0a7e48770d4544ce`)

Read from the persisted request record `D:\.rightkit-managed\state\remote-requests\rr-1791600938761-0a7e48770d4544ce.json` on the Dell (`rightkit status <id>` answers "job not found" on both Mac and Dell, so the record file was read instead; no new build started):

- state `TERMINAL`, broker `SUCCEEDED`, exit 0; `cargo build --release --target x86_64-pc-windows-msvc`; repository key `swiftright-render-815231d1`; remote workspace `D:\.rightkit-managed\remote-workspaces\swiftright-render-815231d1\slot1`; input snapshot 399,360 bytes, digest `8e307c249d9f171ccf549802627e30419c8c64f1acaa5c9af0b4e706c8414ff7`; submitted 2026-10-10T02:55:39Z (08:25:39 IST), terminal 02:56:35Z, run 54.2 s, receipt id `90bfcd0c-d34e-46dc-88ad-1c175cf7a87d`.
- Artifact: `D:\.rightkit-managed\rightkit-build-control\ws\864173e69427\g\001\target\x86_64-pc-windows-msvc\release\swiftright_render.dll`, 11,882,496 bytes, written 08:26:34 IST, sha256 `97CA28E8…CA26B` (matches the staged DLL).
- Caveats: the receipt's `inputClosure` is `inputs-mutated` (`Cargo.lock` changed during the build); the receipt records no git commit, so that the snapshot equals `02b3cc0` is UNVERIFIED (the commit message of `02b3cc0` says "Built DLL 97ca28e8"). Authenticode digest not computed. The managed target path may be recycled by RightKit GC; the copy in `renderer\` is the staged one.

## 6. Parameters and defaults to change to point at `sr0-r07` (not edited)

Needed (Mac-side defaults that run the lanes):

- `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh:22` `BASE_DIR` -> `D:\\Claude\\sr0-r07\\src`; `:23` `EXPECT_EXE_SHA256` -> `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960`; `:24` `EXPECT_DLL_SHA256` -> `97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B`. The header comment lines 6-12 and 19 still describe the 0.6b defaults (stale already). `qualification/run.py:57,751` runs this script with only `OUT_DIR` and `RUNS` in the environment, so these three defaults decide the win-replay stage.
- `qualification/run.py:80` `SMOKE_BASE` -> `D:\\Claude\\sr0-r07\\smoke` (comment names 21992F16 + 7533963D; renderer now 97CA28E8). Used at `:683`, `:687` (`schedule-smoke.ps1 -Base`).
- `qualification/run.py:87` `F1_TREE` -> `D:\\Claude\\sr0-r07\\src`; `:88` `F1_BIN` follows from it; `:770` runs `verify-artifacts.ps1` there, `:773` passes `-Bin {F1_BIN}`. `:86` `F1_BASE` (`D:\Claude\sr0o-f1`, UIARecorder tree) stays. The F1 trace now needs no `build-fob.ps1` patched exe (`probes/sr0-o/f1-cross/scripts/build-fob.ps1:3` throws, obsolete).
- `qualification/tuple-final.json:9` (`windows_renderer`) -> `97ca28e84a58f0d3b44b5a6eaa8d7c912e673a07774123296c958e0d7ecca26b`; `:18` (`windows_fixture_exe`) -> `7673a2d5139172d890d3882d332c3c72321f2372d343319a1065cfeedfdb960` (lowercase). `:27` (`windows_smoke_exe`) unchanged. The `source` citations at `:11-13` and `:20-22` (`docs/sr0-snapshot.md:64`/`:65`, `run-matrix.sh:24`/`:23`, result files `:103`) are re-read by `test_run.py` `TupleFileTests`, so they must be re-pointed to a new snapshot section and to result files that carry the new hashes (the existing `result-smoke-rev06final.txt:103` and `matrix-final/F1-none-r1.txt:110` hold the old renderer/exe). Header `:3-5` (`name`, `note`) names the final tuple and HEAD 4496474.
- `qualification/test_run.py:995-996` assert hash prefixes `7533963d` and `aa4353ce`; `:997` (`21992f16`) stays.
- `docs/sr0-snapshot.md:64-65` (and `:66` smoke row text naming the renderer) are the cited rows; add a section 2d rather than editing 2c.

Lane defaults that still point at older trees (callers pass explicit `-Base` and hashes, so no change is required, but they are stale):

- `probes/sr0-b/native-interaction/scripts/run-native.sh:12` `BASE_DIR` (`sr0s-bridge06b`), `:13` `EXPECT_EXE_SHA256` (`3593209A…`), `:14` `EXPECT_DLL_SHA256` (`C80B9517…`), comment `:7`; `drive-ime.ps1:12`, `:15`; `drive-narrator.ps1:15`, `:16`; `schedule-native.ps1:8`. Run with `BASE_DIR=D:\\Claude\\sr0-r07\\src EXPECT_EXE_SHA256=7673A2D5… EXPECT_DLL_SHA256=97CA28E8… DESKTOP_LANE_FREE=1`. `run-native.sh` stages its scripts to `<BASE_DIR>\probes\sr0-b\native-interaction\scripts` itself.
- `examples/BridgeSmoke/scripts/schedule-smoke.ps1:3` `-Base` default (`sr0b-abi0`; comment `:7`), `drive-smoke.ps1:13` `-Bin`, `:14` `-Out`, `build-smoke.ps1:5`. `run.py` passes `-Base` and the schedule script passes `-Bin`/`-Out`. No hash default exists in the smoke scripts (the result line `drive-smoke.ps1:219` records the hashes).
- `probes/sr0-b/workload/scripts/run-workload.ps1:12` `-Base` default `D:\Claude\sr0b-workload` and `:23` `-ExpectDll` default `7533963D…`; `verify-artifacts.ps1:4` and `:6` (same two); `verify-manifest.ps1:2`; `headless-check.ps1:4`; `run-stress.ps1:15` (`-ExpectDll` default is empty at `:22`, forwarded when set); `task-workload.ps1:32-34` (`-Base`, `-RunRoot`, `-ResultFile`; run-workload passes them); `build-incremental.ps1:8`; `build-workload.ps1:9-11` (`-Base`, `-Dll` from `sr0s-bridge06b`, `-ExpectDllSha256`). Elevated run: `run-workload.ps1 -Base D:\Claude\sr0-r07\workload -ExpectDll 97CA28E8…` (the exe hash comes from `build.json`).
- `probes/sr0-s/fresh-on-bridge/scripts/build-fresh.ps1:6,8`, `verify-manifest.ps1:5`, `drive-fixture.ps1:8,11`, `drive-fresh.ps1:8-9`, `schedule-fixture.ps1:7`, `schedule-fresh.ps1:3` default to `D:\Claude\sr0s-bridge` and `sr0b-abi0`; `run-matrix.sh` passes `-Base` and both hashes to `schedule-fixture.ps1`.

Outside the Dell tuple dirs, for the lead's decision:

- `examples/SliceApp/Windows/renderer-pin.json:5` (`sha256` `7533963D…`) and `:9` (`defaultSource` `D:\Claude\sr0b-abi06f\bin\swiftright_render.dll`): the SliceApp MSIX renderer pin. Moving it to 97CA28E8 means rebuilding the R5 MSIX pair; not part of this staging.
- `examples/BridgeGeoModal/scripts/build.ps1:8` (`$RendererSrc` default `sr0b-abi06f\bin`), `:9` (`$RendererSha` default `7533963d…`): already modified in the working tree by another change (git status at session start); its header says the modal-fix build takes `-RendererSha` and a new DLL path (`D:\Claude\sr0-r07\renderer\swiftright_render.dll`, `97ca28e8…`).

## 7. Run commands once the lead edits the pins

```
# win-replay matrix (interactive desktop; do not start while another desktop proof runs)
BASE_DIR='D:\\Claude\\sr0-r07\\src' EXPECT_EXE_SHA256=7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960 \
  EXPECT_DLL_SHA256=97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B sh probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh
# smoke
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r07\smoke\examples\BridgeSmoke\scripts\schedule-smoke.ps1 -Base D:\Claude\sr0-r07\smoke -Tag <tag>"        # add -SkipShutdown for timeout mode
# workload (elevated)
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r07\workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Base D:\Claude\sr0-r07\workload -ExpectDll 97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B"
```
