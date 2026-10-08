# SR0 stage status

Updated 9 October 2026. Evidence lives in each probe's `RESULT.md`.

| Stage | Status | Evidence | Open |
|---|---|---|---|
| SR0-D dependencies & hosts | PASS on Windows x64 & Mac arm64 | `probes/sr0-d/*` | Windows arm64 lane blocked (no host); MSIX/Swift packaging adapters missing in `@rightkit/release` (blocks P); RightKit services lack C ABI & `rightkit-shell` requires Tauri (blocks SR2) |
| SR0-C slice contract | DRAFT v0.1 | `conformance/sr0-slice/CONTRACT.md`, `probes/sr0-c/same-source` | Freeze after B text-pattern & frame-clock probes |
| SR0-O oracle & comparator | IN PROGRESS | `probes/sr0-o/ax-routes` | Signed recorder with own AX grant; comparator & fault injection |
| SR0-B bridge & measurement | IN PROGRESS | `probes/sr0-b/gpui-drain` | Text measurement & runs, TextPattern, DPI coordinates, display ticks, stall diagnosis, caret-anchored IME, stale handles & teardown |
| SR0-S seed comparison | NOT STARTED | | Needs O & B |
| SR0-P packaged qualification | BLOCKED | `probes/sr0-d/release-preflight` | `@rightkit/release` MSIX & Swift adapters |
| SR0-A automation | NOT STARTED | | Needs P |

Host facts: Windows GUI probes need the interactive desktop session (DXGI unavailable over SSH); hosts loading the renderer need the ComCtl v6 manifest; automated IME input must use virtual-key SendInput, not Unicode packets.
