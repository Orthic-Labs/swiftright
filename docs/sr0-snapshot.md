# SR0 qualification snapshot: tuple on bridge ABI 0.6

Written 9 October 2026 against repository HEAD `6263841`; section 5 updated 10 October 2026 to HEAD `d4d2ca4` (current state; sections 1-4 keep their 9 October text unless marked) (lane R0 of `docs/sr0-close-plan.md` v2). Mac-side text work plus read-only inspection (`win` for hashes and file listings, no GUI, nothing built or run). Every row cites a path, commit, or a command run for this document; anything not checked is marked UNVERIFIED.

**Status (updated 10 October 2026, HEAD `d4d2ca4`): the FINAL tuple is tuple 08 (section 2d; section 2c, tuple 06, is superseded and kept as history).** Tuple 08 pins renderer `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93`, FreshOnBridge `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960`, MSIX 0.1.0.0 `c80c6947…` / 0.1.1.0 `0ff65165…`, `@rightkit/release` 0.2.146; the text below that names `7533963D`, `AA4353CE` or `4496474` describes tuple 06 and is superseded. Renderer DLL `7533963D124C066159322EDF540BD45637CC294173FD9DB2AF95D4D4A3F149FC` (ABI 0.6, source commits through `65cd886`), runtime `b8702bb`, fixture host FreshOnBridge `AA4353CE5EC2DEA7B3C00C68CC4E160789CCDD3B14DCA41494B8509B34BE1D7E` (matrix-final 320/320, `5a67f23`), BridgeSmoke `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5` (40/40 and 41/41, `541129c`), SliceApp MSIX 0.1.0.0 / 0.1.1.0 from `0751951` (`examples/SliceApp/RESULT-R5.md`), SliceApp DMG 0.1.0 `b976ac70…` from `4496474` (R3 final), `@rightkit/release` 0.2.144. Everything named in sections 1 and 2 as a renderer `777F14C4` / `4FB068F0` or fixture `3593209A` / `30FBE599` / `AFE131A1` row is history; where a row below still carries its 9 October text it is marked SUPERSEDED. The tuple is complete except for the items marked PENDING in section 5 (R6, R10 W5 overlay-off run, Narrator speech, R8 full runner run, the repo record of the R3 final DMG); R5 W08 is a recorded FAIL routed to RightKit.

Rule (close plan, Decisions): all SR0 receipts bind to one tuple: runtime commit, bridge/header commit, renderer DLL sha256, app/fixture binary sha256. Existing 0.5 evidence stays as history.

## 1. Source pins

| Component | Path | Pin | State |
|---|---|---|---|
| Repository base | `/Volumes/D/claude/swiftright` | `6263841` (branch master, tree clean at start of this lane) | candidate base; final pin = commit that records the 0.6 builds |
| ABI header (ABI 0.6) | `render/swiftright-abi/include/swiftright.h`, `SWR_ABI_MAJOR 0`, `SWR_ABI_MINOR 6` (lines 126-127) | last changed `4df7e67` (SR1: bridge ABI rev 0.6, "built, smoke pending desktop") | pinned |
| Renderer sources | `render/swiftright-render/` (gpui =0.2.2, accesskit =0.25.1, accesskit_windows =0.35.1; `Cargo.lock`) | last changed `65cd886` (R10: paint pacing off by default, AX publication every 100 ms, allocations -78%); earlier since the 0.6 header: `862997c`, `15855e1`, `a9db7dc`, `5e36535` (IME), `02d8335` (R10); `173ac08` is README notes only. No header or ABI change after `862997c` | pinned (section 2c) |
| SwiftRightBridge | `packages/SwiftRightBridge/` | last changed `33987c2` (`Bridge.events` created lazily; R10 leak fix), after `fd2e0ad` and `4df7e67` | pinned (section 2c) |
| Fresh runtime | `probes/sr0-s/fresh-runtime/` | last changed `b8702bb` (final tuple; diagnostic counters, committed because they were in the working tree when fixture `AA4353CE` was built); R10 performance work `03050c3`, `02d8335`, `33987c2`; earlier `14106d6` (SR1 inventory controls, 62/62 headless on macOS and Windows; 46/46 at `000679e`) | pinned. matrix-20b ran an older runtime: the Windows staging copy was written 11:16 (`D:\Claude\sr0s-bridge`), `14106d6` is dated 11:45, so the 0.5 matrix did not run `14106d6`. Exact runtime commit of matrix-20b UNVERIFIED (not recorded in `out/matrix-20b`) |
| Windows fresh-on-bridge host | `probes/sr0-s/fresh-on-bridge/` | last matrix driver edits in `076a56f` (matrix driver hardening) | pinned |
| BridgeSmoke | `examples/BridgeSmoke/` | last changed `4df7e67` | pinned |
| SliceApp | `examples/SliceApp/` (right-release config, `package.json` pins `@rightkit/release` 0.2.144, `f4c313f` (0.2.142 at `ea879dc`, 0.2.143 at `b5473b9`)) | `2051a6a` adopted bridge AX fixes; `076a56f` packaging prep; `b476c85` R2 MSIX; `1aee425`/`ea879dc` R3 DMG; `b5473b9`/`f4c313f` 0.2.143/0.2.144; `0751951` GUI-subsystem exe | MSIX 0.1.0.0/0.1.1.0 built on the final renderer pin `7533963D` from `0751951` (R5 final2, `4496474`, section 2c); the R2 pair on `777F14C4` is history; final DMG on 0.2.144 PENDING (r3-final) |
| Mac fixtures / comparator / recorder | `probes/sr0-o/{fixtures,comparator,f1-cross,uia-recorder}` | fixtures last changed `858faa7` (SR1 G2/G6; SR0 F-configs unchanged since `4ff202f` sweep per `docs/qualification.md`); signed `F1MacRecord.app` built in `7a91608` | pinned; the Accessibility grant for the signed recorder was reported done by the lead on 10 Oct (no committed record); the R6 oracle run is PENDING |
| Accepted Mac baselines | `conformance/accepted/` (16 configs) | `799047d`, approver note in `docs/qualification.md` | pinned; canonical digests to be recomputed after the F4 per-node-order fix (plan F4) |
| Contract | `conformance/sr0-slice/CONTRACT.md` | DRAFT v0.1 (freeze proposal `docs/sr0-freeze-slice-contract-v1.md`) | not frozen |

## 2. Binary pins

| Artifact | Path | sha256 | Built from | State |
|---|---|---|---|---|
| Renderer DLL, ABI 0.6 (rev06c) | `D:\Claude\sr0b-abi06c\bin\swiftright_render.dll` (11,779,072 bytes, written 2026-10-09 14:42:21; same bytes in `sr0b-abi06c\scratch\release`) | `777F14C4FF11822BF6E2174E127B3A4A325D83A6B322FA599C7FC4408B335441` | commit `862997c` (images counted in `live_nodes` until freed; header change is comments only). Hash computed with `win Get-FileHash`. That the file equals a rebuild of `862997c` is UNVERIFIED (file predates the commit at 15:02; no RightKit receipt id recorded) | SUPERSEDED by `4FB068F0…` for the final tuple; history for BridgeSmoke rev06c, matrix-abi06c and the R2 MSIX |
| Renderer DLL, ABI 0.6 (first build) | `D:\Claude\sr1-abi06\payload\bin\swiftright_render.dll` (11,777,536 bytes, 2026-10-09 12:06:15) | `C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30` | `4df7e67`; also kept as `swiftright_render.dll.c80b9517` in `sr0s-bridge06b` | SUPERSEDED by 777F14C4… (history only) |
| BridgeSmoke.exe (0.6, rev06c) | `D:\Claude\sr0b-abi06c\scratch\release\BridgeSmoke.exe` (999,424 bytes, 2026-10-09 14:56:17) | `517600DC635D38A4581FE34347C13A4D57557C5080246D77A73BEA28DFD25B12` | bridge package at `862997c` with renderer `777F14C4…` | RUN: smoke 40/40 (`examples/BridgeSmoke/result-smoke-rev06c.txt`), timeout mode 41/41 (`result-smoke-timeout06c.txt`), Dell desktop |
| BridgeSmoke.exe (0.6 first build, superseded) | `D:\Claude\sr1-abi06\scratch\release\BridgeSmoke.exe` (955,904 bytes, 12:20:12) | `1B031BD8B8ABA9DF897B41D53AEEE05FFB14AEB575641CB93D974A1067E48E83` | bridge as of `4df7e67`, before `fd2e0ad` | SUPERSEDED, never run |
| SR1Gallery.exe (0.6 build) | `D:\Claude\sr1-gallery06\scratch\release\SR1Gallery.exe` (3,423,744 bytes, 12:29:05) | `F30D86BFD11A07310778E849AAC923A4587AB1ACAF35926DFD09943982976B18` | same pre-`fd2e0ad` bridge | build only, self-test never executed (`probes/sr1-win-backend/RESULT.md`); SR1 lane, outside SR0 tuple; TO-BUILD if reused |
| FreshOnBridge.exe on 0.6b (fixture host) | `D:\Claude\sr0s-bridge06b\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` (3,829,760 bytes, 2026-10-09 14:40:39 +05:30), built from the working tree (uncommitted at build time) with renderer `C80B9517…` at build time, replaced on 2026-10-09 by `777F14C4…` (old DLL kept as `swiftright_render.dll.c80b9517`; exe not rebuilt: no bridge package change since the build); manifest verified with mt.exe (comctl32 v6); adds Tab / Shift-Tab focus traversal, IME automation hooks (caret-bounds EVT, `--release-event` / `--release-file` / `--f7-live`) and per-line stdout flush | `3593209A49BC540FD0FAB2EC7AD14390A60C9E30042D8B7E23852D48000D68BA` | built; supersedes the `58CAA002…` 0.6 build for the 0.6 matrix |
| Windows fixture/oracle drivers on 0.6 | `probes/sr0-s/fresh-on-bridge/scripts/*.ps1`, F1 recorder `probes/sr0-o/f1-cross/uia-recorder` | TO-BUILD | | TO-BUILD |
| SliceApp.exe (Windows) | `examples/SliceApp/scripts/build-windows.ps1` | TO-BUILD. Existing `D:\Claude\sliceapp-sr0p\…\SliceApp.exe` (2,240,000 bytes, 11:41) and `D:\Claude\sliceapp-sr1-check\…\SliceApp.exe` (2,992,128 bytes, 12:34) are not hashed here and not tuple members | | TO-BUILD |
| SliceApp MSIX (old + new), signed | R2 (RightKit) | TO-BUILD | | TO-BUILD |
| SliceApp .app + DMG (old + new), signed, notarized, stapled | R3 | TO-BUILD | | TO-BUILD |
| Mac FixtureApp | `probes/sr0-o/fixtures` (SwiftPM) | `6C972B766718ED0FA2D2E84D047C7F17600321DB2231DED0A4ADA2825C2D83A4` from `docs/qualification.md` (committed tree `bb4258a2549f`, 2026-10-09 06:05 run). Rebuild required after the F4 canonical-form change | | hash recorded only for history; TO-BUILD on the tuple |
| Mac recorder `F1MacRecord.app` | `probes/sr0-o/f1-cross` | not hashed (UNVERIFIED location of the signed build) | `7a91608` | needs Adrian's AX grant (R6) |

## 2b. Tuple of 9 October 2026 evening (SUPERSEDED by section 2c; history)

| Artifact | Path | sha256 | Built from | State |
|---|---|---|---|---|
| **Renderer DLL, ABI 0.6 (final)** | `D:\Claude\sr0s-bridge06f\payload\bin\swiftright_render.dll` (11,789,312 bytes, 2026-10-09 18:06:19; identical copies in `scratch\out\Products\Release-windows-x86_64` and `scratch\renderer-src`) | `4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F` | `5e36535` (18:07:31: IME composition/candidate window re-placement on layout move, on top of `15855e1` IME fixes and `a9db7dc` candidate geometry logging). That the file equals a clean rebuild of `5e36535` is UNVERIFIED (file written one minute before the commit; no RightKit receipt id) | SUPERSEDED by `7533963D…` (section 2c); history for matrix-abi06f/g, BridgeSmoke rev06f, R9 final06f; Authenticode digest of the unsigned DLL `B77F7A5EDBE5AF03A375A59561796E9A12CA76078DB6D660CE4C47DCF2B75F49` (`examples/SliceApp/Windows/renderer-pin.json`; import closure unchanged, `imm32.dll` already declared) |
| FreshOnBridge fixture host, matrix-abi06f / R9 final | `D:\Claude\sr0s-bridge06f\...` | `30FBE599B697F731CFB652586B81B7B9561BDA969990D82DCD0681532630D239` | working tree at the time (`preflight-final06f.txt` ARTIFACT_OK with the final DLL) | RUN: R9 final (`050d28e`, `277b92d`); matrix-abi06f (`c31f1b5`): F8 0/20 fixture defect, other configs 20/20. SUPERSEDED, history |
| FreshOnBridge fixture host (SUPERSEDED by `AA4353CE…`) | rebuilt after `c31f1b5` (ax-button-focus logging) | `AFE131A1B75C70B0939CD2077C5A5E3E4788FA198E8739FC80EC48F0E8617B0F` | working tree | RUN: matrix-abi06g 318/320 first time (2 infrastructure), reruns 6/6 (`a6fdcad`, `matrix-abi06g/RESULT.md`); history |
| Intermediate fixtures | | `3593209A…` (abi06c matrix, R9 first pass), `083752D2…` (Narrator pass after `0993eb2`) | | history |
| BridgeSmoke.exe | still rev06c `517600DC…` (row above) | `517600DC635D38A4581FE34347C13A4D57557C5080246D77A73BEA28DFD25B12` | bridge `862997c` with renderer `777F14C4…` | smoke 40/40 and timeout 41/41 bind to the old renderer `777F14C4…`; rerun on `4FB068F0…` 40/40 and 41/41 (`45f707d`, `result-smoke-rev06f.txt`); final: section 2c |
| SliceApp MSIX 0.1.0.0 / 0.1.1.0 (R2) | `/Volumes/D/sr0-artifacts/win/r2-msix/` | `A2D6BC08A9AA573F46D79240AACF99C7D04DF9131A2B4D4A9AE77ECF5A63119E` / `BB2031CAC1A53B555CD344B1F69E1DAC2D7693E9B286D1DC0627175DED86FD23` | SliceApp `d70d36b`, renderer `777F14C4…`, `@rightkit/release` 0.2.139, signed (CN=Damned Ventures LLC, thumb `70C72673…`) | built and signed on the old renderer; history; replaced by the R5 final2 pair in section 2c |
| SliceApp DMG 0.1.0 / 0.1.1 (R3) | `/Volumes/D/sr0-artifacts/mac/` (`0.1.0`, `0.1.1`, `0.1.0-rk0140`, `0.1.0-rk0142`) | 0.2.139 DMGs `81742a7c…64b661` / `c75155b4…071a8a` (`RESULT-R7.md`); 0.2.142 0.1.0 DMG `363c8768…0d5ea` | SliceApp clones, Developer ID signed, notarized, `.app` stapled before DMG since 0.2.140 | built; Mac packages carry no Windows renderer, no tuple change |
| Windows Sandbox harness (R5) | `qualification/clean-machine/windows/`, `examples/SliceApp/R5-RUNBOOK.md` | n/a | run (final2 round, `4496474`): 14/15, W08 FAIL | section 2c |

## 2c. Tuple 06 final (10 October 2026; supersedes 2b; SUPERSEDED by section 2d, tuple 08; history, rows below unedited)

All rows verified against the committed files named; hashes are copied from them. HEAD at writing: `4496474`.

| Artifact | Path / pin | sha256 | Built from | State |
|---|---|---|---|---|
| Runtime | `probes/sr0-s/fresh-runtime/` | n/a | commit `b8702bb` (last change: diagnostic counters `Graph.counts`; its message says they were in the working tree when fixture `AA4353CE` was built and were committed so the tuple corresponds to a commit) | pinned |
| Bridge ABI header and package | `render/swiftright-abi/include/swiftright.h` (`SWR_ABI_MAJOR 0`, `SWR_ABI_MINOR 6`), `packages/SwiftRightBridge/` | n/a | header last changed `862997c` (unchanged since); bridge package last changed `33987c2` | pinned |
| Renderer sources | `render/swiftright-render/` | n/a | commits through `65cd886` (R10: paint pacing off by default, AccessKit publication throttled to 100 ms, renderer allocations -78%); `173ac08` adds README notes (`render/README-abi-v0.md`, "Performance and diagnostics knobs") only. The renderer changed after the 0.6 header (IME `15855e1`, `a9db7dc`, `5e36535`; R10 `02d8335`, `65cd886`) with no header or ABI change: the final smoke prints `startup validation [abi 0.6 fn_count=16 stats_size=200]` | pinned |
| **Renderer DLL (final)** | `D:\Claude\sr0s-bridge06f` (`matrix-final/RESULT.md`); SliceApp pin `examples/SliceApp/Windows/renderer-pin.json` (`b5473b9`) | `7533963D124C066159322EDF540BD45637CC294173FD9DB2AF95D4D4A3F149FC` (11,877,888 bytes; Authenticode digest `D8FB3B3BF57409FE5013B45F073801EEA455822AF8F9E8FCAF4F1A50D39F7EB1`) | source at `65cd886`. `ITERATION.md`: final source = `709E05CB` plus comment/doc edits only; the rebuild is not bit-identical. That the file equals a clean rebuild of `65cd886` is UNVERIFIED (no RightKit receipt id recorded) | pinned |
| **FreshOnBridge fixture host (final)** | `D:\Claude\sr0s-bridge06f` | `AA4353CE5EC2DEA7B3C00C68CC4E160789CCDD3B14DCA41494B8509B34BE1D7E` | runtime `b8702bb` | RUN: matrix-final **320/320 PASS first time**, 16 configs x 20, every run ARTIFACT_OK, no reruns (`probes/sr0-s/fresh-on-bridge/out/matrix-final/RESULT.md`, `5a67f23`); native interaction final (`probes/sr0-b/native-interaction/out/*-tuplefinal.txt`, `541129c`) |
| **BridgeSmoke.exe (final)** | `examples/BridgeSmoke/` | `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5` | bridge package, renderer `7533963D` | RUN: smoke 40/40 (`result-smoke-rev06final.txt`), timeout mode 41/41 (`result-smoke-timeout06final.txt`), `541129c`; both print the ARTIFACTS line with these hashes |
| WorkloadWin.exe | `D:\Claude\sr0b-workload` | `0815DF49…` (prefix only in `probes/sr0-b/workload/results/ITERATION.md` it8; full hash not recorded in a committed file: UNVERIFIED). Earlier exe `8E0264F0ABD7A3D78D0E0DE40D293D924FE53A186B78AC5967A449B5736BE020` with renderer `7533963D` in `r10-20261010-renderer7533-windows.txt` | `33987c2` (leak fix) | measured, W5 fails (see `docs/sr0-status.md`, R10) |
| SliceApp MSIX 0.1.0.0 | `/Volumes/D/sr0-artifacts/win/r5-final2/inputs/` | `4cc9a7f0a05c05561432ddf536179ae18b6e2aeabbc0f6c245397de38edf2f4a` (29,048,635 B) | SliceApp `0751951` (GUI-subsystem exe), renderer pin `7533963D` | built, signed (`signtool verify /pa` OK, Damned Ventures LLC, thumbprint `121FD7B5…`, expires 2026-10-12 05:16:54 Dell local), Sandbox 14/15 (`examples/SliceApp/RESULT-R5.md`, `4496474`) |
| SliceApp MSIX 0.1.1.0 | same | `c2897a68d1a4555da92155f4192dc53c77a5803e5932a821ab3fed465de2f432` (29,048,705 B) | clone-local `b545c34f` on `0751951` (version bump plus one diagnostic string) | built, signed; `swift-only-proof.mjs` `ok: true` (changed payload = manifest and `sliceapp.exe`) |
| SliceApp DMG 0.1.0 (R3 final) | `/Volumes/D/sr0-artifacts/mac/r3-final/SliceApp_0.1.0_arm64.dmg` | `b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4` | commit `4496474`, `@rightkit/release` 0.2.144 | PASS (coordinator report, receipts read and hash recomputed 10 Oct): QA source receipt passed, `codesign`, `spctl` (Notarized Developer ID), `stapler`, `syspolicy_check` pass for DMG and inner `.app`; evidence outside the repository (`r3-final-verify.txt`); repo record PENDING. Mac packages carry no Windows renderer |
| `@rightkit/release` | `examples/SliceApp/package.json` | catalog `a7121f96` (`f4c313f`) | published 0.2.144 | pinned |
| Mac FixtureApp, recorder `F1MacRecord.app`, accepted baselines | `probes/sr0-o/*`, `conformance/accepted/` | unchanged from section 2 | | R6 PENDING |

History in 2b and section 2: renderers `777F14C4…` and `4FB068F0…`, fixtures `3593209A…`, `30FBE599…`, `AFE131A1…`, the R2 MSIX pair (renderer `777F14C4`) and the R5 harness rounds before final2 (5/15, then 13/15 in `75050e2`) are superseded and are not tuple members.

### Superseded 0.5 binaries (history only, not tuple members)

| Artifact | Path | sha256 |
|---|---|---|
| Renderer DLL, ABI 0.5, built from `d45c98c` | `D:\Claude\sr0s-bridge\scratch\release\swiftright_render.dll` (11,742,208 bytes, 09:45:50) | `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1` (also in `docs/sr0-freeze-*.md` and `matrix-rev4/RESULT.md`) |
| FreshOnBridge.exe used by matrix-20b | `D:\Claude\sr0s-bridge\scratch\release\FreshOnBridge.exe` (2,987,520 bytes, 11:18:16) | `DD6C9CE69F06D9C28EF300E7FEA5B499AEA0F7AF9AF364C3F2B4C4D67BED8CC6` (matches the "binary DD6C9CE6…" in commit `65e0f29`) |

## 2d. Tuple 08 (10 October 2026; supersedes 2c; the final tuple)

Hashes copied from the committed files named. HEAD at writing: `d4d2ca4`. Tuple 07 (renderer `97CA28E8`, modal lost-wake fix `02b3cc0`) was an intermediate: its receipts are history (`docs/sr0-retry-ledger.md`). Section 2c rows for the renderer, FreshOnBridge and the MSIX pair are superseded; BridgeSmoke is unchanged, the DMG rows of 2c remain current (the Mac does not use the renderer).

| Artifact | Path / pin | sha256 | Built from | State |
|---|---|---|---|---|
| Renderer DLL ABI 0.6 (tuple 08) | `examples/SliceApp/Windows/renderer-pin.json`; Dell `D:\Claude\sr0-r08\renderer\swiftright_render.dll` | `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` (11,885,056 bytes; Authenticode digest `E713BF405FEF43835576ACAC418C99E6D95BA5112E6FB628481B8B641D4F9B0E`) | `9c261d4` (AX trailing publish re-arm) on top of `02b3cc0` (modal lost-wake fix); no ABI change; committed-tree rebuild was a no-op and hashes equal (provenance in the pin file) | pinned; unsigned |
| FreshOnBridge fixture host (tuple 08) | Dell `D:\Claude\sr0-r08\src`; defaults in `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh` | `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960` | `c0fc401` (F1 cross-compare release gate in source, `SR0O_RELEASE_FLAG`) | RUN: matrix-08 319/320, the failure is external typed input, rerun 3/3 (`probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md`) |
| BridgeSmoke.exe (unchanged) | `examples/BridgeSmoke/` | `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5` | bridge package, renderer `E280F4A9` | RUN: smoke 40/40 (`examples/BridgeSmoke/result-smoke-rev08.txt`), timeout 41/41 (`examples/BridgeSmoke/result-smoke-timeout08.txt`) |
| WorkloadWin.exe | Dell `D:\Claude\sr0-r08\workload` | `0815DF499371CEDE032758B00A6B254726DD524B9A0930C2D96B57089A74070F` | `33987c2`, unchanged exe | measured: W5 FAIL, leak PASS (`probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt`) |
| SliceApp MSIX 0.1.0.0 | `examples/SliceApp/RESULT-R5-08.md` | `c80c694735754f7bff892a74e2335c2d8cd7a87e8555f2e5233bd47392a7a0c4` | SliceApp `a6d657b`, renderer pin `E280F4A9`, `@rightkit/release` 0.2.146 | built, signed; Sandbox offline 13/14 (W08 FAIL), network W00/W01/W12 PASS |
| SliceApp MSIX 0.1.1.0 | same | `0ff6516543d2c2dec49dd41a65ae3ef0a7eb9c7d34f9c05321534f731b6bc8e8` | clone-local `5e6338b6` on `a6d657b` | built, signed; swift-only proof `ok: true` |
| SliceApp DMG 0.1.0 / 0.1.1 | section 2c rows and `tuple-final.json` | `b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4` / `75f3cd75cbd5e0f2eb1f561ae4d273f2522dedc19c75713b138a919678dd4b3b` | unchanged | PASS; no Windows renderer inside |
| `@rightkit/release` | `examples/SliceApp/package.json` | n/a | 0.2.146 | used for tuple 08 MSIX |

## 3. Toolchains and hosts

| Item | Value | Source |
|---|---|---|
| Mac host | Mac mini, macOS 27.0.1 (26A434), arm64 | `sw_vers`, `uname -m` run for this document; CONTRACT §1 |
| Xcode | 27.0, build 27A266a | `xcodebuild -version` run for this document (the 27.0 RC note in `docs/qualification.md` is older) |
| Swift (Mac) | Apple Swift 6.4 (swiftlang-6.4.0.34.1), target arm64-apple-macosx27.0.0, swift-driver 1.168.6 | `swift --version` run for this document |
| Windows host | Dell XPS 15 9530 (host name BOGUS-DELL in driver logs), Windows NT 10.0.26300.0, x64 | `win` query for this document; `matrix-20b/F1-none-r1.txt` |
| Swift (Windows) | Swift 6.4 (swift-6.4-RELEASE), target x86_64-unknown-windows-msvc, assertions on | `win "swift --version"` run for this document |
| Rust | 1.98.0 via RightKit (`rightkit cargo`) per CONTRACT §1. Not re-queried: the workspace hook denies a direct `rustc` call | UNVERIFIED for today |
| Windows build tools | MSVC / `mt.exe` / `dumpbin` via `scripts/build-windows.ps1`; versions not recorded in the repository | UNVERIFIED |
| GPU / driver, fonts, locale, DPI, refresh | recorded per run in fixture metadata, not at tuple level | UNVERIFIED for 0.6 runs (none exist) |
| Architectures in scope | Windows x64 and macOS arm64 only | `docs/architecture.md` §9 scope revision 1 |
| Packaging pin | `@rightkit/release` 0.2.144 (published; R4 done) | `examples/SliceApp/package.json` (`f4c313f`), `PACKAGING.md` |

## 4. What must be rerun on this tuple

Source of the list: which receipts were produced on ABI 0.5 (or earlier-ABI probe) binaries, per `docs/sr0-status.md` evidence and commit history. "0.5" = DLL `2DC4B6F7…` unless noted.

| # | Receipt (path, commit) | Built on | Rerun needed | Plan lane |
|---|---|---|---|---|
| 1 | BridgeSmoke 26/26 and timeout mode 27/27 (`examples/BridgeSmoke/result-smoke-rev05c.txt`, `result-smoke-timeout05c.txt`, `ee5a4db`) | ABI 0.5 | Yes: 0.6 smoke plus timeout mode on a BridgeSmoke built after `fd2e0ad`. The 0.6 additions (roles 8-14, toggled, selected/selectable, disabled routing, image register/release, menu and dialog modal kinds, `\n` measure) have never run on a desktop | R1(a) |
| 2 | Windows matrix 15 configs x 20 (`probes/sr0-s/fresh-on-bridge/out/matrix-20b`, `65e0f29`, 300/300) | ABI 0.5, FreshOnBridge `DD6C9CE6…` | Yes: 20 runs per config on the 0.6 tuple, plus the F3 3 s variants (`list-3s`, `vstack-3s`, `lazy-3s`) that the 0.5 matrix lacks | R1(b) |
| 3 | Matrices rev4/rev4b 15 x 3 (`out/matrix-rev4`, `matrix-rev4b`, `cc4c93a`, `ee5a4db`) | ABI 0.5 | Superseded by item 2, history only | |
| 4 | F1 cross-platform compare, Windows w6 vs Mac m1..m5, 0 diffs (`probes/sr0-o/f1-cross`, `eaf40dc`) | Windows trace on the 0.5 stack (UNVERIFIED exact binary) | Yes: Windows F1 re-record on 0.6 and compare against the Mac baselines recorded by the signed recorder | R6 |
| 5 | Mac oracle 17 configs x 20 (`probes/sr0-o/fixtures/REPEAT20.md`, `4ff202f`) and accepted baselines (`799047d`) | Mac only (ABI independent) | Yes, for a different reason: recompute canonical digests with the per-node-order form (plan F4) and rerun with the signed recorder (F1-F9 re-record) | R8, R6 |
| 6 | Text geometry run 4, 35/35 including degenerate caret rect (`probes/sr0-b/text-geometry`, `fcc999d`) | probe-tree bridge, pre-0.6 | Yes if the 0.6 text path changed: `text.rs` changed in `4df7e67` (multi-paragraph, line-break cells); rerun against the 0.6 DLL. Which ABI the run-4 probe used: UNVERIFIED | R1(a) or R9 |
| 7 | Modal loop probe within budget, late-dispatch 3/3 (`probes/sr0-b/modal-loop`, `probes/sr0-b/gpui-drain`, `0d3f1a9`) | standalone probe hosts (gpui-drain ABI 0.2), not the bridge | The 0.6 bridge's real modal paths (`SWR_MODAL_MENU`, `SWR_MODAL_DIALOG`) have no desktop receipt; late-dispatch on the bridge path is covered only by the smoke "late async result after close" lines (0.5). Rerun on 0.6 | R1(a), R9 |
| 8 | Frame budget 30/30 (`probes/sr0-b/frame-clock`, `011c83e`) | standalone SwiftHost probe | Full §11 workload on the selected runtime and bridge replaces it (plan F7) | R10 |
| 9 | Headless runtime tests 46/46 (`000679e`), 62/62 (`14106d6`) | n/a (no renderer) | Rerun `swift test` for the pinned runtime commit on both OSes and record the output with the tuple | R1 / R8 |
| 10 | Mac-Windows compare F2-F9 | none exists | New (only F1 was ever compared cross-platform) | R6 |
| 11 | Real Japanese IME, Narrator/NVDA | none | New on the 0.6 tuple | R9 |
| 12 | Packaging (P), clean-machine checks, automation (A) | none | New on final binaries | R2, R3, R5, R7, R8 |

Not part of the SR0 tuple: SR1 gallery (`probes/sr1-win-backend`, build only), SR1 Mac fixtures G1-G8 (`c9347a0`), SR3 engine client (`e0034fc`, `b56704e`).

## 5. Rerun status after the 10 October lanes

State of the section 4 list against commits through `4496474`; PENDING means no committed result.

| # (section 4) | State |
|---|---|
| 1 BridgeSmoke + timeout mode | DONE on the final tuple 08: smoke 40/40 (`examples/BridgeSmoke/result-smoke-rev08.txt`, line 83) and timeout 41/41 (`result-smoke-timeout08.txt`, line 84), both printing the tuple 08 renderer and exe hashes. Tuple 06 runs (`541129c`) are history |
| 2 Windows matrix 20 runs incl. F3 3 s | DONE on tuple 08 with one external-input failure: 319/320 on fixture `7673A2D5`, renderer `E280F4A9` (`probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md`, `820eb26`); the failing run (F3 list-0s r16) passed on a 3/3 rerun. Tuple 06 `320/320` (`5a67f23`) and the earlier 0.6 matrices are history |
| 4, 10 Mac-Windows compare F1-F9 | PARTIAL: F1 only, 0 diffs on tuple 08 (`qualification/out/r8-tuple08/compare-F1.json`), against the 0.5-era Mac baseline. F2-F9 PENDING (R6: signed recorder on the Mac, about 10 min, Adrian) |
| 5 Mac oracle digests, F4 per-node order | Canonical v2 and offline recompute of 15 of 16 configs committed (`1b7cdc1`); F6 has 2 canonical results; re-record with the signed recorder and the 100-run F6 sample PENDING (R6) |
| 6 Text geometry on 0.6 | DONE on tuple 08: TextGeom06 20/20 (`examples/BridgeGeoModal/result-textgeom08.txt`, line 93); AX trailing-publish fix `9c261d4` proven at `result-textgeom-axfix.txt:132` (60/60) |
| 7 Real modal paths on 0.6 | DONE on tuple 08: Modal06 20/20 on the first attempt, 0 stalls in 120 modals (`examples/BridgeGeoModal/result-modal08.txt`, lines 257 and 268); `modal_open_one_off` max 39.59 ms against the 50 ms bound (line 262) |
| 8 §11 workload | RUN on Windows on tuple 08 (`probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt`): NOT MET. W5 missed vblanks 5, 1 and 1 per 60 s run (lines 40, 79, 118; `OVERALL: FAIL` line 285); leak PASS. Overlay-off run PENDING (Adrian); Mac windowed run not committed |
| 9 Headless runtime tests on the pinned commit | DONE: fresh-runtime 84/84 and SwiftRightBridge 8/8 on runtime `b8702bb`, macOS 27 arm64 and Windows 11 x64 (`c370228`, `docs/sr0-status.md` row SR0-S) |
| 11 Real IME, Narrator | DONE on tuple 08 (`840f9ec`): IME F7 20/20, F7live 20/21, F8 18/19 (the failing check in both is `candidate-window-follows-layout-move`, known limitation, SR1 TSF), Narrator 8/8 automatable; Narrator speech (audio) PENDING Adrian, about 2 min |
| 12 Packaging and clean machines | R5 Windows Sandbox on the tuple 08 MSIX pair: offline 13/14, W08 FAIL (RightKit recovery documented, probe `80a9b45`; decision PENDING). R3 final DMGs PASS, repo record committed (`34e818a`, `0be0ea3`). R7 PASS including the quarantined launch of the stapled `.app` (10/10, `2403117`). R8 runner run on tuple 08 (win-replay, compare, smoke, package); mac-oracle stage PENDING with R6 |
