# SR0 tuple 09: Dell staging record (10 October 2026)

Staged at `D:\Claude\sr0-r09` on the Dell. CURRENT staging: commit `be9a922` (`be9a922028079fb8a51c6bb47299dfb6e9965d06`; runtime-only change over `bece2a8`: a motion's start time is set by the first display tick, `probes/sr0-s/fresh-runtime` `Animation.swift`, `Graph.swift`). FIRST staging (superseded): commit `bece2a8` (`bece2a82f24416d8d7d909c94afc1be0c7730209`); its FreshOnBridge and WorkloadWin values are kept below as "first staging, superseded". Build and copy only: no GUI, no scheduled task, no desktop run, no commit, nothing deleted on the Dell. The renderer is UNCHANGED from tuple 08 (E280F4A9). In the first staging every executable was rebuilt from `bece2a8`, because the bridge package and runtime had changed since the tuple 08 exes (`829f70c` parity fixes: `ButtonFocusGate`, initial focus, reduce motion; `bece2a8` SliceApp host). The restage rebuilt ONLY the two binaries that link the runtime (FreshOnBridge, WorkloadWin); BridgeSmoke, BridgePixels and the three BridgeGeoModal hosts keep their first-staging bytes (section 3). The final tuple (`docs/sr0-snapshot.md` section 2d, `qualification/tuple-final.json`) is unchanged until the lead edits the pins in section 6.

## 1. Pins (sha256)

| Member | Path (Dell) | Bytes | sha256 | Status vs tuple 08 |
|---|---|---:|---|---|
| Renderer DLL | `D:\Claude\sr0-r09\renderer\swiftright_render.dll` | 11,885,056 | `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` | UNCHANGED (copied from `D:\Claude\sr0-r08\renderer`, hash checked before and after) |
| FreshOnBridge.exe (be9a922) | `D:\Claude\sr0-r09\src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` | 4,195,840 | `8650BBFC4118F0793D71F84A51077D23D076E7DD1AA144C2AE7B60BAC27161C8` | NEW (tuple 08: `7673A2D5…`, 4,087,296) |
| BridgeSmoke.exe | `D:\Claude\sr0-r09\smoke\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe` | 1,017,344 | `85D5F8BA798EF17367844F28D75F3E53A37323F13A8409397C7C3FD1AD563EEA` | NEW (was `21992F16…`, 1,004,544) |
| BridgePixels.exe | `D:\Claude\sr0-r09\smoke\bin\BridgePixels.exe` (same bytes in `smoke\scratch\out\Products\Release-windows-x86_64\`) | 660,992 | `452110B5508533751F2E70C69D1008F484BD5C833C3F743850B7ACE50DABD0F7` | NEW (sources committed in `3587dcc`; the T4 build lived in `D:\Claude\sr0-t4`) |
| WorkloadWin.exe (be9a922) | `D:\Claude\sr0-r09\workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe` | 4,711,936 | `27E781B85E54F1213CE46C170C31EB9E351BDB00A97B37FE453D084A745C079C` | NEW (tuple 08: `0815DF49…`, 4,669,440) |
| TextGeom06.exe | `D:\Claude\sr0-r09\geomodal\bin\TextGeom06.exe` | 1,053,696 | `CDEA68FDEC10D83405BCE5E7C622402C2935AFA1886A8C20C6CB039C2AD99607` | NEW |
| Modal06.exe | `D:\Claude\sr0-r09\geomodal\bin\Modal06.exe` | 965,120 | `E7CC66159027654EBAD963835E9593292F3A834DC116634848D8C312B5E08FB9` | NEW |
| ColdOpen06.exe | `D:\Claude\sr0-r09\geomodal\bin\ColdOpen06.exe` | 776,704 | `F7742CA8EFB07DA73EE0512ADB7FF08114E513CCE4549F860AE177343F939157` | NEW (sources committed in `3587dcc`) |
| SliceApp.exe (compile check only, not a tuple member; be9a922) | `D:\Claude\sr0-r09\slicecheck\examples\SliceApp\.build\payload\SliceApp.exe` | 3,377,152 | `19D34C53087090B9A54F7FC54F495A4A58F4540B3628E8311423491BBB659DCC` | not staged for runs |
| FreshOnBridge.exe, first staging (bece2a8), SUPERSEDED | same path, replaced by the restage | 4,193,792 | `941C314492C1E0E17294A1CF61CE72BB5CF928305DB8E52E3111CB228DBA5C6F` | superseded; this hash is what `run-matrix.sh:23` and `run-native.sh:13` hold after `a10b667` |
| WorkloadWin.exe, first staging (bece2a8), SUPERSEDED | same path, replaced by the restage | 4,708,864 | `F8807AFCAB10A657AB7ACF357AA19CD8B5D53F49DABC4321DF4CCD9FA966C8B7` | superseded; `workload\build.json.first-staging-bece2a8` holds its record |
| SliceApp.exe, first staging (bece2a8), SUPERSEDED | same path, replaced | 3,374,592 | `453022D117F651D4FB3164E23D6AF491823F4A2DA76D9DF3FBC459BA430654CF` | superseded |

The renderer DLL hash was checked at all 10 copies under `D:\Claude\sr0-r09` (not counting `slicecheck`, which has none): `renderer\`, `src\payload\bin`, `src\scratch\...\Release-windows-x86_64`, `smoke\payload\bin`, `smoke\bin`, `smoke\scratch\...`, `workload\payload\bin`, `workload\scratch\...`, `geomodal\payload\bin`, `geomodal\bin`. All `E280F4A9`.

Exe hashes are build outputs (the linker stamps a PE timestamp), so a rebuild from the same commit gives different hashes; these hashes bind THIS build. The WorkloadWin hash was the same before and after the three incremental builds (section 3), in both stagings. The BridgeSmoke, BridgePixels, TextGeom06, Modal06 and ColdOpen06 rows are the first-staging builds and are still current (restage, section 3).

Toolchain: Swift 6.4 (swift-6.4-RELEASE), x86_64-unknown-windows-msvc, +assertions, unchanged from `docs/sr0-tuple07-staging.md` section 1. The ten Swift/CRT runtime DLLs in `C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin` were re-hashed and match that table exactly (no runtime DLL is copied beside any exe; the drive scripts put the directory on PATH).

## 2. Layout under `D:\Claude\sr0-r09`

```
renderer\swiftright_render.dll                 E280F4A9
src\                                           git clone of bogusyogi/swiftright, detached at be9a922 (first staging: bece2a8) = the FreshOnBridge tree
  scratch\out\Products\Release-windows-x86_64\ FreshOnBridge.exe, swiftright_render.dll
  payload\bin\swiftright_render.dll
smoke\                                         BridgeSmoke + BridgePixels tree
  examples\BridgeSmoke\{scripts,Sources,Package.swift}   from the clone (result-*.txt and evidence\ excluded)
  packages\SwiftRightBridge                    from the clone
  scratch\out\Products\Release-windows-x86_64\ BridgeSmoke.exe, BridgePixels.exe, swiftright_render.dll
  bin\BridgePixels.exe, swiftright_render.dll  (build-pixels.ps1 layout)
  payload\bin\swiftright_render.dll
workload\                                      WorkloadWin tree
  probes\sr0-b\workload\{scripts,analysis,Sources,Package.swift}   (results\ and out-mac\ excluded)
  probes\sr0-s\fresh-runtime, packages\SwiftRightBridge, render\swiftright-abi\include   from the clone
  scratch\out\Products\Release-windows-x86_64\ WorkloadWin.exe, swiftright_render.dll
  payload\bin\swiftright_render.dll
  build.json                                   exe path and hashes of THIS build (written by build-workload.ps1); source_head = be9a922...; staged_from, staged_utc added
  build.json.first-staging-bece2a8             the first staging's record (copy kept)
  incremental.json                             W7 record for this tuple (section 3), from the be9a922 build
  incremental.json.first-staging-bece2a8       the first staging's W7 record (copy kept)
  SOURCE-HEAD.txt                              be9a922... (clean checkout of the named commit)
  runs\                                        empty
  shim\, incremental-build-{1,2,3}.txt, WorkloadScreen.swift.orig, WorkloadWin.exe.pinned    build-incremental.ps1 side files
geomodal\                                      TextGeom06, Modal06, ColdOpen06 tree
  examples\BridgeGeoModal, packages\SwiftRightBridge   from the clone (result-*.txt and evidence\ excluded)
  scratch\out\Products\Release-windows-x86_64\ the three exes
  bin\{TextGeom06,Modal06,ColdOpen06}.exe, swiftright_render.dll
  payload\bin\swiftright_render.dll
slicecheck\                                    local clone, detached at be9a922 (SliceApp compile check; has .build\ output; not a tuple member)
stage-tools\                                   the staging and verification .ps1 files and their logs
```

`src` was not `git pull`ed and must not be (it would move off the commit the exe was built from). The scripts in `smoke\`, `workload\` and `geomodal\` are copies of the `bece2a8` committed versions; if their defaults are edited in the repo (section 6), pass the parameters explicitly or re-copy.

## 3. Build and staging commands

All run as `-File` scripts through `win`, never inline or `-EncodedCommand`: the ComCtl v6 `/MANIFESTDEPENDENCY` quoting breaks inline, and under `-EncodedCommand` swift's stderr warnings become terminating errors. Each stage script sets `BelowNormal` priority first (another agent held the desktop). Scripts are in `D:\Claude\sr0-r09\stage-tools\`, logs beside them.

```
git clone https://github.com/bogusyogi/swiftright D:\Claude\sr0-r09\src
git -C D:\Claude\sr0-r09\src checkout --detach bece2a8      # first staging; the restage moved it to be9a922 (below)

# FreshOnBridge: build-fresh-lowprio.ps1 calls
src\probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1 -Base D:\Claude\sr0-r09\src -Dll D:\Claude\sr0-r09\renderer\swiftright_render.dll -ExpectDllSha256 E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93

# BridgeSmoke + BridgePixels: stage-smoke.ps1 = robocopy examples\BridgeSmoke and packages\SwiftRightBridge from src, DLL into payload\bin, then
smoke\examples\BridgeSmoke\scripts\build-smoke.ps1 -Base D:\Claude\sr0-r09\smoke
smoke\examples\BridgeSmoke\scripts\build-pixels.ps1 -Base D:\Claude\sr0-r09\smoke -RendererSrc D:\Claude\sr0-r09\smoke\payload\bin\swiftright_render.dll -RendererSha e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93

# WorkloadWin + W7: stage-workload.ps1 = robocopy the four source dirs, SOURCE-HEAD.txt, then
workload\probes\sr0-b\workload\scripts\build-workload.ps1 -Base D:\Claude\sr0-r09\workload -Dll D:\Claude\sr0-r09\workload\payload\bin\swiftright_render.dll -ExpectDllSha256 E280F4A9...
workload\probes\sr0-b\workload\scripts\build-incremental.ps1 -Base D:\Claude\sr0-r09\workload

# BridgeGeoModal hosts: stage-geomodal.ps1 = robocopy examples\BridgeGeoModal and packages\SwiftRightBridge, then
geomodal\examples\BridgeGeoModal\scripts\build.ps1 -Base D:\Claude\sr0-r09\geomodal -RendererSrc D:\Claude\sr0-r09\renderer\swiftright_render.dll -RendererSha e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93

# SliceApp compile check: slice-check.ps1 = git clone src -> slicecheck (bece2a8), then
slicecheck\examples\SliceApp\scripts\build-windows.ps1
```

Restage to `be9a922` (stage-tools scripts, same build scripts as above, new log names `*-be9a922.log`):

```
restage-src-be9a922.ps1:        git -C src fetch origin; git -C src checkout --detach be9a922; HEAD checked = be9a922028079fb8a51c6bb47299dfb6e9965d06;
                                0 tracked changes; then build-fresh-lowprio.ps1 (the unchanged FreshOnBridge build above)
restage-workload-be9a922.ps1:   keeps build.json and incremental.json as *.first-staging-bece2a8 (copies); robocopy (no purge) probes\sr0-b\workload,
                                fresh-runtime, SwiftRightBridge, swiftright-abi\include from src into workload\; SOURCE-HEAD.txt = be9a922...;
                                build-workload.ps1 (as above, writes build.json), staged_from/staged_utc added; build-incremental.ps1 (writes incremental.json)
slice-check-be9a922.ps1:        git -C slicecheck fetch https://github.com/bogusyogi/swiftright master; checkout --detach be9a922; build-windows.ps1
verify09b.ps1:                  section 4
```

Why only FreshOnBridge and WorkloadWin were rebuilt: `probes/sr0-s/fresh-on-bridge/Package.swift:13` (`../fresh-runtime`) and `probes/sr0-b/workload/Package.swift:30` (`../../sr0-s/fresh-runtime`) depend on the runtime package; `examples/BridgeSmoke/Package.swift:17` and `examples/BridgeGeoModal/Package.swift:15` depend only on `../../packages/SwiftRightBridge`, which declares no package dependency. `git diff bece2a8 be9a922` over `packages/`, `render/`, `examples/BridgeSmoke/{Sources,Package.swift}` and `examples/BridgeGeoModal/{Sources,Package.swift}` is empty, so the BridgeSmoke, BridgePixels, TextGeom06, Modal06 and ColdOpen06 inputs are byte-identical between the two commits. Their hashes were re-read after the restage and are unchanged (section 4). The `smoke\` and `geomodal\` trees still hold the `bece2a8` copies of their scripts.

Every build is `swift build -c release --scratch-path <tree>\scratch` with `-Xlinker /MANIFEST:EMBED` and the ComCtl v6 `/MANIFESTDEPENDENCY` (SliceApp: the manifest file, `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup`). Build times, first staging: FreshOnBridge 45.8 s, BridgeSmoke (all products) 18.6 s plus BridgePixels 0.9 s, WorkloadWin 52.4 s, BridgeGeoModal 21.8 s, SliceApp 30.5 s. Restage (be9a922): FreshOnBridge 30.6 s, WorkloadWin 39.7 s, SliceApp 23.6 s.

W7 record (current, from the be9a922 restage): `build-incremental.ps1` ran 3 edits (9.0, 7.9, 8.3 s, all `exit=0`) with the same shims: `rust_invocations_total=0`, `hashes_identical=True`, `builds_ok=True`, `pinned_exe_sha256=27E781B8…`; `WorkloadScreen.swift` restored (`7C9CF0D1…` before and after, equal to the clone's copy) and the exe hash `27E781B8…` is the same after the builds. It replaced `workload\incremental.json`; the first staging's record is `incremental.json.first-staging-bece2a8` (also 3 edits, 0 Rust invocations).

W7 record (first staging, bece2a8): `build-incremental.ps1` ran 3 edits against `WorkloadCore\WorkloadScreen.swift` (7.6 to 8.8 s each, all `exit=0`) with cargo/rustc/rustup/rightkit shims first on PATH: `rust_invocations_total=0`, `hashes_identical=True`, `builds_ok=True`, written to `D:\Claude\sr0-r09\workload\incremental.json`. The edited source was restored byte for byte (sha256 `7C9CF0D1…` before and after, equal to the clone's copy) and the WorkloadWin exe hash is `F8807AFC…` after the builds. The analyzer finds this file on its own: it looks at `<run root>\incremental.json` then `<run root>\..\..\incremental.json`, and a run root of `workload\runs\<tag>` resolves to it (tuple 08 failed W7 only because that record did not exist in its tree).

Staging notes: `git clone` and similar native commands in a script with `$ErrorActionPreference = 'Stop'` stop at the first stderr line (the first `slice-check.ps1` run died there after the clone had completed; the script was fixed to `Continue` around git and re-run on the existing clone, same HEAD). A 3-byte `stage-tools\t.txt` is the `scp` test file and was left in place (no deletions). In the restage, `git -C slicecheck fetch origin` did not bring `be9a922` (the `src` clone's `master` branch is still at the clone-time commit and its detached HEAD is not a fetched ref), so `slice-check-be9a922.ps1` fetches from GitHub (`master`). `D:\Claude\sr0-r09b` is another agent's probe tree and was not touched.

## 4. Verification (offline, no window opened)

### Restage, be9a922 (current)

Run by `stage-tools\verify09b.ps1`, log `stage-tools\verify09b.log`.

| Check | Result |
|---|---|
| `verify-artifacts.ps1 -Base D:\Claude\sr0-r09\src -ExpectExe 8650BBFC… -ExpectDll E280F4A9…` | `ARTIFACT_OK` |
| `verify-manifest.ps1 -Base D:\Claude\sr0-r09\src` (mt.exe) | `manifest=OK comctl32-v6` |
| `workload\...\verify-artifacts.ps1 -Base D:\Claude\sr0-r09\workload -ExpectExe 27E781B8… -ExpectDll E280F4A9…` | `ARTIFACT_OK` |
| `workload\...\verify-manifest.ps1 -Base D:\Claude\sr0-r09\workload` | `manifest=OK comctl32-v6` |
| `workload\build.json` | `exe_sha256` = `27E781B8…` = the file's hash, `dll_sha256` = `E280F4A9…`, `source_head` = `be9a922…` |
| BridgeSmoke.exe, BridgePixels.exe (both copies), TextGeom06.exe, Modal06.exe, ColdOpen06.exe | all `UNCHANGED` against section 1 |
| Renderer DLL at all 10 copies | `E280F4A9 OK` |
| SliceApp, `slicecheck` at be9a922, `build-windows.ps1` (build only) | `swift build exit=0`, no `warning:` line, `manifest ok: ComCtl v6 + PerMonitorV2 embedded`, nothing unresolved in the import closure, exe 3,377,152 bytes, sha256 `19D34C53…` |
| W7 `incremental.json` | 3 edits, 0 Rust invocations, hashes identical, builds ok |
| FreshOnBridge `--self-test`, any run of any exe | NOT RUN (window or desktop use, skipped by instruction) |

### First staging, bece2a8 (superseded rows are marked)

Run by `stage-tools\verify09.ps1`, log `stage-tools\verify09.log`. The FreshOnBridge, WorkloadWin and SliceApp rows below are SUPERSEDED by the restage above; the manifest rows for the unchanged binaries, the geomodal dry run and the ColdOpen06 dry run still describe current binaries.

| Check | Result |
|---|---|
| `src\...\fresh-on-bridge\scripts\verify-artifacts.ps1 -Base D:\Claude\sr0-r09\src -ExpectExe 941C3144… -ExpectDll E280F4A9…` | `ARTIFACT_OK` (superseded) |
| `...\verify-manifest.ps1 -Base D:\Claude\sr0-r09\src` (mt.exe) | `manifest=OK comctl32-v6` (superseded exe) |
| `workload\...\verify-artifacts.ps1 -Base D:\Claude\sr0-r09\workload -ExpectExe F8807AFC… -ExpectDll E280F4A9…` | `ARTIFACT_OK` (superseded) |
| `workload\...\verify-manifest.ps1 -Base D:\Claude\sr0-r09\workload` | `manifest=OK comctl32-v6` (also run inside `build-workload.ps1`) |
| mt.exe manifest of BridgeSmoke.exe, BridgePixels.exe, TextGeom06.exe, Modal06.exe, ColdOpen06.exe | `comctl32-v6=True` for all five (`build.ps1` also printed it for the three hosts) |
| Renderer DLL at all 10 copies | `E280F4A9 OK` |
| `geomodal\examples\BridgeGeoModal\scripts\dryrun.ps1 -Base D:\Claude\sr0-r09\geomodal -RendererSha e280f4a9…` | `dryrun PASS`, exit 0: renderer identity, 10 script parses, both driver `-DryRun` self-tests, `TextGeom06.exe` and `Modal06.exe` with `SWR_GM_DRYRUN=1` (logic PASS; renderer loaded and validated, abi 0.6 fn_count=16 stats_size=200, no window), 18 foreground-classification cases, fg.log round trip, AX tally parser, 10 ms foreground watch, no leftover `SR0GM-*` task |
| `ColdOpen06.exe` with `SWR_CO_DRYRUN=1` (not covered by `dryrun.ps1`) | exit 0: `DRYRUN logic PASS`, `DRYRUN renderer loaded and validated: abi 0.6 (no window opened)` |
| SliceApp Windows sources, `slicecheck\examples\SliceApp\scripts\build-windows.ps1` (build only; no sign, pack or launch) | `swift build exit=0`, no warning from `BridgeBackend.swift`, `manifest ok: ComCtl v6 + PerMonitorV2 embedded`, import closure resolved with nothing unresolved, exe 3,374,592 bytes (superseded) |
| BridgeSmoke (no verify script exists) | exe/DLL hashes as section 1, manifest as above |
| FreshOnBridge `--self-test`, headless runs of any exe, smoke, pixels, cold-open or workload runs | NOT RUN (windows or desktop use, skipped by instruction) |

Not proven by this staging: the behavior of the `829f70c`/`bece2a8`/`be9a922` changes on Windows (initial focus, `ax-focus-coalesced`, tick-on-demand in SliceApp). The owed Dell runs are listed in `probes/sr0-s/fresh-on-bridge/RESULT.md`, "Owed on the Dell".

## 5. Renderer provenance

Unchanged: tuple 08 renderer `E280F4A9…` (ABI 0.6, built from `9c261d4` on `02b3cc0`). `D:\Claude\sr0-r09\renderer\swiftright_render.dll` was copied from `D:\Claude\sr0-r08\renderer\swiftright_render.dll`; both hash `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` and 11,885,056 bytes. No RightKit build was started.

## 6. Script defaults to change

State read from the repo at `be9a922` after the restage. Already edited by the lead (`a10b667`, `be9a922`): the `r08` -> `r09` base paths and the first-staging FreshOnBridge hash in `run-matrix.sh:22-23`, `run-native.sh:12-13`, `run-workload.ps1:12`, `run-cross.ps1:10`, `schedule-cross.ps1:5`, `qualification/run.py:88,95` (comments now say `85D5F8BA`, tuple 09). STILL OPEN because of the restage: the FreshOnBridge default hash in `run-matrix.sh:23` and `run-native.sh:13` is the superseded `941C3144…` and must become `8650BBFC4118F0793D71F84A51077D23D076E7DD1AA144C2AE7B60BAC27161C8`. Not yet edited: everything else below that still shows `r08`, `7673A2D5` or `21992F16` (`tuple-final.json`, `test_run.py`, the five `sr0-r08` defaults in the BridgeSmoke, BridgeGeoModal, workload scripts and `renderer-pin.json`, and the docs).

Needed to point the lanes at tuple 09 (`r08` becomes `r09`; old exe hashes become the current section 1 hashes; the DLL hash `E280F4A9…` stays everywhere):

FreshOnBridge `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960` (first staging `941C3144…`) becomes `8650BBFC4118F0793D71F84A51077D23D076E7DD1AA144C2AE7B60BAC27161C8`:

- `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh:22` `BASE_DIR` `D:\\Claude\\sr0-r08\\src` -> `D:\\Claude\\sr0-r09\\src`; `:23` `EXPECT_EXE_SHA256` -> `8650BBFC…`. (`:24` DLL unchanged; header comments `:7`, `:19` still describe 0.6b, stale already.)
- `probes/sr0-b/native-interaction/scripts/run-native.sh:12` `BASE_DIR` -> `D:\\Claude\\sr0-r09\\src`; `:13` `EXPECT_EXE_SHA256` -> `8650BBFC…`. (Its other scripts still default to `sr0s-bridge06b`; the caller passes `BASE_DIR`.)
- `qualification/run.py:95` `F1_TREE` -> `D:\\Claude\\sr0-r09\\src` (the comment says "tuple 08"); `:96` `F1_BIN` follows.
- `probes/sr0-o/f1-cross/scripts/schedule-cross.ps1:5` and `run-cross.ps1:10` `-Bin` default `D:\Claude\sr0-r08\src\scratch\out\Products\Release-windows-x86_64` -> `sr0-r09`.
- `qualification/tuple-final.json:19` `windows_fixture_exe` sha256 -> `8650bbfc4118f0793d71f84a51077d23d076e7dd1aa144c2ae7b60bac27161c8`, and its `what` text (it names `c0fc401`/`b8702bb`) and `source` citations (`:20-24`: `docs/sr0-snapshot.md:90`, `run-matrix.sh:23`, `matrix-08/F1-none-r1.txt:111`).
- `qualification/test_run.py:1024` prefix `7673a2d5` -> `8650bbf`. `TupleFileTests` re-reads every `source` citation, so each cited file must carry the new hash on the cited line.
- Docs that quote `7673A2D5` as a pin: `docs/sr0-snapshot.md:5,90,141`, `docs/sr0-status.md:9,15,17,20`, `docs/sr0-findings.md:11,375`, `docs/sr0-freeze-bridge-interface.md:5`, `docs/sr0-freeze-slice-contract-v1.md:7,28,30,133`. Add a section 2e to `docs/sr0-snapshot.md` rather than editing 2d in place.

BridgeSmoke `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5` becomes `85D5F8BA798EF17367844F28D75F3E53A37323F13A8409397C7C3FD1AD563EEA`:

- `qualification/run.py:88` `SMOKE_BASE` `D:\\Claude\\sr0-r08\\smoke` -> `D:\\Claude\\sr0-r09\\smoke` (comment names `21992F16`); used by `schedule-smoke.ps1 -Base`.
- `qualification/tuple-final.json:28` `windows_smoke_exe` sha256 -> `85d5f8ba798ef17367844f28d75f3e53a37323f13a8409397c7c3fd1ad563eea`, `what` ("unchanged") and `source` citations (`:29-33`: `docs/sr0-snapshot.md:91`, `result-smoke-rev08.txt:104`, `result-smoke-timeout08.txt:105`).
- `qualification/test_run.py:1025` prefix `21992f16` -> `85d5f8b`.
- `examples/BridgeSmoke/scripts/drive-pixels.ps1:16` `-Bin` default `D:\Claude\sr0-r08\smoke\scratch\out\Products\Release-windows-x86_64` -> `sr0-r09`; `build-pixels.ps1:6` `-RendererSrc` default `D:\Claude\sr0-r08\smoke\payload\bin\swiftright_render.dll` -> `sr0-r09` (`:5` `-Base` default `D:\Claude\sr0-t4` is the old T4 tree; the exe now lives in `smoke\bin` and `smoke\scratch\...`).
- Docs quoting `21992F16`: `docs/sr0-snapshot.md:5,66,91`, `docs/sr0-status.md:9,16`, `docs/sr0-findings.md:11`, `docs/sr0-freeze-bridge-interface.md:5,99,129`, `docs/sr0-freeze-slice-contract-v1.md:7,29,133`.

WorkloadWin `0815DF499371CEDE032758B00A6B254726DD524B9A0930C2D96B57089A74070F` (first staging `F8807AFC…`) becomes `27E781B85E54F1213CE46C170C31EB9E351BDB00A97B37FE453D084A745C079C`:

- No script default holds the exe hash: `build.json` (written for the new paths) does. Pass `-ExpectExe 27E781B8…` to `verify-artifacts.ps1`.
- `probes/sr0-b/workload/scripts/run-workload.ps1:12` `-Base` default `D:\Claude\sr0-r08\workload` -> `D:\Claude\sr0-r09\workload` (`:23` `-ExpectDll` already `E280F4A9`); `gpu-routing.ps1:2` `-Out` default `D:\Claude\sr0-r08\workload\runs\w5\routing` and `w5-ab.ps1:3` `-Base` -> `sr0-r09`; `dll-strings.ps1:2` `-Dll` default `D:\Claude\sr0-r08\renderer\...` -> `D:\Claude\sr0-r09\renderer\...`.
- Docs quoting `0815DF49`: `docs/sr0-snapshot.md:67,92`, `docs/sr0-status.md:9,21,27`, `docs/sr0-findings.md:11,136`, `docs/sr0-freeze-bridge-interface.md:5`, `docs/sr0-freeze-slice-contract-v1.md:7,32`.

BridgeGeoModal hosts (no hash pin in the repo scripts; the dry run takes `-RendererSha`):

- `examples/BridgeGeoModal/scripts/drive-coldopen.ps1:15` `-Base` default `D:\Claude\sr0-r08\geomodal` -> `D:\Claude\sr0-r09\geomodal`; `recycle-stage.ps1:5` allow-list names `D:\Claude\sr0-r08\geomodal` and would refuse the r09 tree until edited.
- Stale but explicit-parameter defaults (callers pass `-Base`): `dryrun.ps1:12`, `schedule.ps1:6`, `drive-modal.ps1:24`, `drive-textgeom.ps1:7`, `probe-menu-uia.ps1:3`, `build.ps1:7-9` (still `sr0-geomodal`, `sr0b-abi06f\bin`, `7533963d…`), `common.ps1:7` `PinnedRendererSha` `7533963d…` (the dry run passes `-RendererSha`), `schedule-coldopen.ps1:3` (`sr0-t10`).

Other:

- `examples/SliceApp/Windows/renderer-pin.json:5` sha256 is already `E280F4A9…`; `:9` `defaultSource` `D:\\Claude\\sr0-r08\\renderer\\swiftright_render.dll` may move to `sr0-r09\renderer` (same bytes; the r08 copy still exists).
- Still-stale defaults that callers override: `examples/BridgeSmoke/scripts/schedule-smoke.ps1:3`, `build-smoke.ps1:5`, `drive-smoke.ps1:13-14` (`sr0b-abi0`); the other `probes/sr0-b/workload/scripts` (`sr0b-workload`: `headless-check.ps1:4`, `build-workload.ps1:9-10`, `verify-artifacts.ps1:4`, `verify-manifest.ps1:2`, `task-workload.ps1:32-34`, `run-stress.ps1:15`, `build-incremental.ps1:8`); the other `probes/sr0-s/fresh-on-bridge/scripts` (`sr0s-bridge`/`sr0b-abi0`: `build-fresh.ps1:7-8`, `verify-manifest.ps1:4`, `drive-fixture.ps1:8,11`, `drive-fresh.ps1:8-9`, `schedule-fixture.ps1:7`, `schedule-fresh.ps1:3`).

## 7. Run commands once the lead edits the pins

```
# win-replay matrix (interactive desktop; do not start while another desktop proof runs)
BASE_DIR='D:\\Claude\\sr0-r09\\src' EXPECT_EXE_SHA256=8650BBFC4118F0793D71F84A51077D23D076E7DD1AA144C2AE7B60BAC27161C8 \
  EXPECT_DLL_SHA256=E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93 sh probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh
# smoke
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r09\smoke\examples\BridgeSmoke\scripts\schedule-smoke.ps1 -Base D:\Claude\sr0-r09\smoke -Tag <tag>"        # add -SkipShutdown for timeout mode
# workload (elevated)
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r09\workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Base D:\Claude\sr0-r09\workload"
# geomodal / cold open: pass -Base D:\Claude\sr0-r09\geomodal (and -Bin D:\Claude\sr0-r09\geomodal\bin where a script takes one)
```
