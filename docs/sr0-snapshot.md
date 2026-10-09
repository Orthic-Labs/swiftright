# SR0 qualification snapshot: tuple on bridge ABI 0.6

Written 9 October 2026 against repository HEAD `6263841` (lane R0 of `docs/sr0-close-plan.md` v2). Mac-side text work plus read-only inspection (`win` for hashes and file listings, no GUI, nothing built or run). Every row cites a path, commit, or a command run for this document; anything not checked is marked UNVERIFIED.

**Status: the tuple is NOT yet complete.** Source commits and the renderer DLL are pinned. The Swift host binaries on ABI 0.6 (FreshOnBridge, fixture drivers, SliceApp, a post-`fd2e0ad` BridgeSmoke) are TO-BUILD, so no end-to-end receipt can yet bind to this tuple. The final pin is the commit that lands those builds; until then the tuple names a candidate base (`6263841`).

Rule (close plan, Decisions): all SR0 receipts bind to one tuple: runtime commit, bridge/header commit, renderer DLL sha256, app/fixture binary sha256. Existing 0.5 evidence stays as history.

## 1. Source pins

| Component | Path | Pin | State |
|---|---|---|---|
| Repository base | `/Volumes/D/claude/swiftright` | `6263841` (branch master, tree clean at start of this lane) | candidate base; final pin = commit that records the 0.6 builds |
| ABI header (ABI 0.6) | `render/swiftright-abi/include/swiftright.h`, `SWR_ABI_MAJOR 0`, `SWR_ABI_MINOR 6` (lines 126-127) | last changed `4df7e67` (SR1: bridge ABI rev 0.6, "built, smoke pending desktop") | pinned |
| Renderer sources | `render/swiftright-render/` (gpui =0.2.2, accesskit =0.25.1, accesskit_windows =0.35.1; `Cargo.lock`) | last changed `4df7e67` (`git log -- render/swiftright-render`); previous: `d45c98c` (0.5 post-close pump) | pinned |
| SwiftRightBridge | `packages/SwiftRightBridge/` | last changed `fd2e0ad` (collision-free AX run ids, runs for empty editable nodes), after `4df7e67` | pinned, but see the stale-binary note in section 3 |
| Fresh runtime | `probes/sr0-s/fresh-runtime/` | last changed `14106d6` (SR1 inventory controls, 62/62 headless on macOS and Windows; earlier 46/46 at `000679e`) | pinned. matrix-20b ran an older runtime: the Windows staging copy was written 11:16 (`D:\Claude\sr0s-bridge`), `14106d6` is dated 11:45, so the 0.5 matrix did not run `14106d6`. Exact runtime commit of matrix-20b UNVERIFIED (not recorded in `out/matrix-20b`) |
| Windows fresh-on-bridge host | `probes/sr0-s/fresh-on-bridge/` | last matrix driver edits in `076a56f` (matrix driver hardening) | pinned |
| BridgeSmoke | `examples/BridgeSmoke/` | last changed `4df7e67` | pinned |
| SliceApp | `examples/SliceApp/` (right-release config, `package.json` pins `@rightkit/release` 0.2.138) | `2051a6a` adopted bridge AX fixes; `076a56f` packaging prep | pinned; not packaged |
| Mac fixtures / comparator / recorder | `probes/sr0-o/{fixtures,comparator,f1-cross,uia-recorder}` | fixtures last changed `858faa7` (SR1 G2/G6; SR0 F-configs unchanged since `4ff202f` sweep per `docs/qualification.md`); signed `F1MacRecord.app` built in `7a91608` | pinned; recorder has no AX grant yet (R6) |
| Accepted Mac baselines | `conformance/accepted/` (16 configs) | `799047d`, approver note in `docs/qualification.md` | pinned; canonical digests to be recomputed after the F4 per-node-order fix (plan F4) |
| Contract | `conformance/sr0-slice/CONTRACT.md` | DRAFT v0.1 (freeze proposal `docs/sr0-freeze-slice-contract-v1.md`) | not frozen |

## 2. Binary pins

| Artifact | Path | sha256 | Built from | State |
|---|---|---|---|---|
| **Renderer DLL, ABI 0.6** | `D:\Claude\sr1-abi06\payload\bin\swiftright_render.dll` (11,777,536 bytes, written 2026-10-09 12:06:15) | `C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30` | `4df7e67` per its commit message and `probes/sr1-win-backend/RESULT.md` ("renderer DLL sha256 C80B9517…"). Hash computed for this document with `win "Get-FileHash …"`. Identical bytes (same length and timestamp) sit in `sr1-abi06\scratch\release` and `sr1-gallery06\scratch\release`. That the file equals a rebuild of `4df7e67` is UNVERIFIED (the file predates the commit by 15 minutes; render sources are unchanged since the commit per git log; no RightKit receipt id was recorded in the repository) | pinned |
| BridgeSmoke.exe (0.6 build) | `D:\Claude\sr1-abi06\scratch\release\BridgeSmoke.exe` (955,904 bytes, 12:20:12) | `1B031BD8B8ABA9DF897B41D53AEEE05FFB14AEB575641CB93D974A1067E48E83` | bridge package as of `4df7e67`, before `fd2e0ad` (12:33) | STALE: never run (no 0.6 smoke result file in `examples/BridgeSmoke/`); TO-BUILD on the final bridge commit |
| SR1Gallery.exe (0.6 build) | `D:\Claude\sr1-gallery06\scratch\release\SR1Gallery.exe` (3,423,744 bytes, 12:29:05) | `F30D86BFD11A07310778E849AAC923A4587AB1ACAF35926DFD09943982976B18` | same pre-`fd2e0ad` bridge | build only, self-test never executed (`probes/sr1-win-backend/RESULT.md`); SR1 lane, outside SR0 tuple; TO-BUILD if reused |
| FreshOnBridge.exe on 0.6b (fixture host) | `D:\Claude\sr0s-bridge06b\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe` (3,829,760 bytes, 2026-10-09 14:40:39 +05:30), built from the working tree (uncommitted at build time) with the renderer `C80B9517…` copied hash-checked; manifest verified with mt.exe (comctl32 v6); adds Tab / Shift-Tab focus traversal, IME automation hooks (caret-bounds EVT, `--release-event` / `--release-file` / `--f7-live`) and per-line stdout flush | `3593209A49BC540FD0FAB2EC7AD14390A60C9E30042D8B7E23852D48000D68BA` | built; supersedes the `58CAA002…` 0.6 build for the 0.6 matrix |
| Windows fixture/oracle drivers on 0.6 | `probes/sr0-s/fresh-on-bridge/scripts/*.ps1`, F1 recorder `probes/sr0-o/f1-cross/uia-recorder` | TO-BUILD | | TO-BUILD |
| SliceApp.exe (Windows) | `examples/SliceApp/scripts/build-windows.ps1` | TO-BUILD. Existing `D:\Claude\sliceapp-sr0p\…\SliceApp.exe` (2,240,000 bytes, 11:41) and `D:\Claude\sliceapp-sr1-check\…\SliceApp.exe` (2,992,128 bytes, 12:34) are not hashed here and not tuple members | | TO-BUILD |
| SliceApp MSIX (old + new), signed | R2 (RightKit) | TO-BUILD | | TO-BUILD |
| SliceApp .app + DMG (old + new), signed, notarized, stapled | R3 | TO-BUILD | | TO-BUILD |
| Mac FixtureApp | `probes/sr0-o/fixtures` (SwiftPM) | `6C972B766718ED0FA2D2E84D047C7F17600321DB2231DED0A4ADA2825C2D83A4` from `docs/qualification.md` (committed tree `bb4258a2549f`, 2026-10-09 06:05 run). Rebuild required after the F4 canonical-form change | | hash recorded only for history; TO-BUILD on the tuple |
| Mac recorder `F1MacRecord.app` | `probes/sr0-o/f1-cross` | not hashed (UNVERIFIED location of the signed build) | `7a91608` | needs Adrian's AX grant (R6) |

### Superseded 0.5 binaries (history only, not tuple members)

| Artifact | Path | sha256 |
|---|---|---|
| Renderer DLL, ABI 0.5, built from `d45c98c` | `D:\Claude\sr0s-bridge\scratch\release\swiftright_render.dll` (11,742,208 bytes, 09:45:50) | `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1` (also in `docs/sr0-freeze-*.md` and `matrix-rev4/RESULT.md`) |
| FreshOnBridge.exe used by matrix-20b | `D:\Claude\sr0s-bridge\scratch\release\FreshOnBridge.exe` (2,987,520 bytes, 11:18:16) | `DD6C9CE69F06D9C28EF300E7FEA5B499AEA0F7AF9AF364C3F2B4C4D67BED8CC6` (matches the "binary DD6C9CE6…" in commit `65e0f29`) |

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
| Packaging pin | `@rightkit/release` 0.2.138, publish pending (plan R4) | `examples/SliceApp/package.json`, `PACKAGING.md` |

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
