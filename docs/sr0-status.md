# SR0 stage status

Updated 9 October 2026 (late). Evidence lives in each probe's `RESULT.md`.

| Stage | Status | Evidence | Open |
|---|---|---|---|
| SR0-D dependencies & hosts | PASS on Windows x64 & Mac arm64 | `probes/sr0-d/*` | Windows arm64 lane blocked (no host); MSIX/Swift packaging adapters missing in `@rightkit/release` (blocks P); RightKit services lack C ABI & `rightkit-shell` requires Tauri (blocks SR2) |
| SR0-C slice contract | DRAFT v0.1, near freeze | `conformance/sr0-slice/CONTRACT.md`, `probes/sr0-c/same-source` | Freeze after modal-loop results; §11 presentation budget revision 1 applied |
| SR0-O oracle & comparator | IN PROGRESS | `probes/sr0-o/{ax-routes,comparator,fixtures}` | F1–F9 deterministic on macOS 27; comparator rejects injected faults; signed recorder with own AX grant still needed |
| SR0-B bridge & measurement | IN PROGRESS, budgets met | `probes/sr0-b/*`, `render/`, `packages/SwiftRightBridge`, `examples/BridgeSmoke` | ABI rev 0.4 smoke 19/19; modal loops proven; presentation budget MET (batch 5, 30/30 valid); ABI freeze pending runtime-gap rerun |
| SR0-S seed comparison | PREP | `probes/sr0-s/{fresh-runtime,swiftcrossui-assessment}` | Fresh runtime 21/21 headless on both OSes; SwiftCrossUI assessment favours fresh seed; needs ABI v0 backend |
| SR0-P packaged qualification | BLOCKED | `probes/sr0-d/release-preflight` | `@rightkit/release` MSIX & Swift adapters |
| SR0-A automation | NOT STARTED | | Needs P |

Host facts: Windows GUI probes need the interactive desktop session (DXGI unavailable over SSH); hosts loading the renderer need the ComCtl v6 manifest; automated IME input must use virtual-key SendInput, not Unicode packets.
