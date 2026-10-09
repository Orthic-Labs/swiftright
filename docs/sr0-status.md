# SR0 stage status

Updated 9 October 2026 (evening, HEAD ee5a4db). Evidence lives in each probe's `RESULT.md`.

**SR0 overall: about 68% (estimate, not a measured figure).** Basis: D, C, O, B, S carry the bulk of the work and are PASS or green on the evidence below (about 85-95% each); P is blocked (0%) and A not started (0%); the 20-run Windows matrix, F1 Mac-Windows rerun, Stage B desktop runs and arm64 are open. Previous status text gave no percentage.

| Stage | Status | Evidence | Open |
|---|---|---|---|
| SR0-D dependencies & hosts | PASS on Windows x64 & Mac arm64 | `probes/sr0-d/*` | Windows arm64 lane blocked (no host); MSIX/Swift packaging adapters missing in `@rightkit/release` (blocks P); RightKit services lack C ABI & `rightkit-shell` requires Tauri (blocks SR2) |
| SR0-C slice contract | DRAFT v0.1, freeze proposal v1.0 written | `conformance/sr0-slice/CONTRACT.md`, `docs/sr0-freeze-slice-contract-v1.md`, `probes/sr0-c/same-source` | Negative compile fixtures MET (5afd873); C9 Windows repeat count (contract asks 20 runs, only 3 run) still OPEN; F1 Mac-Windows compare rerun blocked; freeze decision pending |
| SR0-O oracle & comparator | Mac side complete | `probes/sr0-o/{ax-routes,comparator,fixtures}`, `fixtures/REPEAT20.md` | Mac repeatability 17 configs x 20 PASS (4ff202f). F1 cross-platform: 317 diffs -> 52 after List AX roles (`compare-strict-m1-w5.json`, only text-field labels), label fix in cc4c93a; rerun BLOCKED (Windows desktop runs blocked by desktop-intrusion hook, pending Adrian). Signed `F1MacRecord.app` built (7a91608), needs Adrian's one-time Accessibility grant |
| SR0-B bridge & measurement | ABI 0.5 smoke 26/26, timeout mode 27/27; budgets met | `probes/sr0-b/*`, `render/`, `packages/SwiftRightBridge`, `examples/BridgeSmoke/result-smoke-rev05c.txt`, `result-smoke-timeout05c.txt` | AutomationId 5/5; underline accepted (acceptance only, no per-primitive draw counter); early/repeat `shutdown_complete` PASS, 5 s timeout path PASS (timeouts=1, run returned 5.00 s); README struct sizes complete (02e660f). Renderer changed after 10c4877 (d45c98c); freeze names DLL sha256 `2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1`. Stage B modal-loop probe (23933e1) and late-dispatch test + degenerate caret check (88bfc7a) built, desktop runs PENDING (blocked as above). Modal p99 31 ms was the one-off TaskDialog open stall, now reported as `modal_open_one_off` (SR1 budget item) |
| SR0-S seed comparison | Fresh runtime green on Windows matrix | `probes/sr0-s/{fresh-runtime,fresh-on-bridge,swiftcrossui-assessment}`, `fresh-on-bridge/out/matrix-rev4/RESULT.md`, `matrix-rev4b` | All 15 configs 3/3 PASS (rev4 44/45 + rev4b reruns). Root causes fixed: cc605bf (post-close teardown commit), cc4c93a (commits after close dropped, F9 live_nodes timing, text-field label), d45c98c (renderer post-close pump survives GPUI quit-on-last-window). Seed decision: fresh runtime; fork 17/22 + 5 blocked (a7b43ac/b771c20); green matrix supports finalizing. 20-run Windows matrix OPEN |
| SR0-P packaged qualification | BLOCKED | `probes/sr0-d/release-preflight` | `@rightkit/release` MSIX & Swift adapters; needs RightKit release adapters and Adrian approval |
| SR0-A automation | NOT STARTED | | Needs P |

Still open or blocked: arm64 host (no hardware), stages P and A, 20-run Windows matrix, F1 rerun and Stage B desktop runs (desktop-intrusion hook).

Host facts: Windows GUI probes need the interactive desktop session (DXGI unavailable over SSH); hosts loading the renderer need the ComCtl v6 manifest; automated IME input must use virtual-key SendInput, not Unicode packets.
