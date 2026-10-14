# Pulse hub in SwiftUI: SwiftRight track

Updated 14 October 2026.

## Decision and ownership

- Adrian chose Pulse as SwiftRight's first real consumer. The Pulse hub (React and Tauri today) is being rebuilt in SwiftUI. The hub goes first because its Tauri baseline makes the §11/SR4 budgets reachable. The Pulse notch's Win32 baseline is 10.9 MB private memory, which a SwiftRight port is unlikely to meet (see [pulse-notch-demand-map.md](pulse-notch-demand-map.md) §6).
- RightKit owns the shared base: RightKitHub (shell, section registry, theme tokens, settings kit, components, platform-service protocols) and RightKitEngine (an EngineClient over the rightkit-job-queue C ABI). The Mac uses a supervised child; on Windows the hub attaches to the Rust notch's engine over rightkit-daemon.
- The Pulse Swift chat builds the Pulse sections. SwiftRight builds the Windows hub exe and proves its controls.

## What SwiftRight provides (requested by RightKit session Rk3, 14 October)

| # | Deliverable | Path | State |
|---|---|---|---|
| 1 | Machine-readable proven-control list, with a `--check` drift mode | `docs/proven-controls.json`, `factory/tools/proven-controls/` | in progress |
| 2 | MarkdownUI (gonzalezreal/swift-markdown-ui) Windows probe | `docs/probes/markdownui-windows.md` | in progress |
| 3 | Hub-base gap check: a compile probe per candidate API | `docs/probes/hub-base-gap-check.md` | in progress |

## Constraints the base must respect

- Build only from proven controls. Block 13 (TextField) is NOT-DELIVERED until the bezel text-inset fix passes review; blocks 14 and 15 inherit it.
- No Canvas and no Swift Charts; charts are drawn with shapes. Path itself is not yet a delivered block.
- Expect these to be missing or unproven until delivered as blocks: Path, Circle().trim, ProgressView, sheet/confirmationDialog (round 4), searchable, NavigationSplitView/NavigationStack, toolbar, Form/Picker/Slider. The gap check confirms each.
- Known Windows differences: text fields draw no focus ring; IME on real hardware is deferred; toggle label widths differ; ImageRenderer renders a ScrollView blank on the Mac.

## Next blocks this track drives

Round 4 picks its blocks from the gap check and the hub's real screens, ordered by how many hub sections need each.
