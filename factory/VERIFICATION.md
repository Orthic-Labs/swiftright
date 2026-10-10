# Phase 0 start — 10 October 2026

Plan revision committed first as `56be363`. This batch adds factory files only. SR0 remains OPEN in
`docs/sr0-status.md`; frozen-contract/ABI integration, native parity & golden promotion remain held.

## Checked

| Check | Observed result |
|---|---|
| Local factory unit suite | 16/16 PASS |
| Rectangle synthetic example schemas | 12/12 valid |
| F8 synthetic timing controls | Bounded jitter passes; all 15 fault controls fail or reject |
| Mac spike build | Swift package builds; both executables target macOS 15+ |
| Host structural render | TextRenderer metrics, Layout proposals/placements & 280 × 72 offscreen image observed |
| VM guard | Host rejected; `VirtualMac2,1` guest accepted |
| Guest structural render | TextRenderer & Layout callbacks observed |
| Guest popover | `isShown=true`; pixels not classified |
| Guest ScreenCaptureKit | BLOCKED: TCC denial, error `-3801` |
| Guest external AX client | BLOCKED: target-window query returned `-25204` |
| Dell second session | No qualified concurrent lane; Windows 11 Pro inventory supports shared-lock routing |

The F8 spike compares exact semantic event order/types separately from bounded duration, interruption velocity &
presented-frame gaps, including missing initial/tail coverage. It retains raw observations. Its values are synthetic,
so these controls establish comparator behavior only. [Recorded selftest](evidence/20261010/f8-timing-selftest.json).

Mac guest binaries matched host SHA-256 hashes. [Raw guest output](hosts/evidence/20261010-mac-capture/guest-capture.stdout.json),
[host output](hosts/evidence/20261010-mac-capture/host-structural.stdout.json) &
[source/binary hashes](hosts/evidence/20261010-mac-capture/run-metadata.json) are archived. Guest process had an external
25-second termination deadline; SSH wall time includes watchdog cleanup. `COMPLETE_WITH_LIMITS` is the spike's own
completion label, not native capture qualification. Factory VM was stopped after collection; original base was unchanged.

Dell preflight opened no windows, sent no input & left SR0's existing lock untouched.
[Inventory & reasoning](spikes/windows/RESULT.md) record session feasibility.

## Next executable work

Provision & qualify VM capture/AX permissions, then collect compositor pixels & external control identity. Native
presented-frame timing & per-channel mutation calibration still need measured captures. Repeat candidate captures
20 times per case before reviewed promotion. Bind frozen contract/ABI only after recorded SR0 closure, then add
foundations needed by Round 1. Existing runtime, renderer, bridge, qualification & SR0 probe edits remain with their owner.

Independent review found no remaining blockers to these draft/start claims. Schema edge cases, root-schema bypass,
timing-tail coverage & external AX scheduling were corrected before this verification record.
