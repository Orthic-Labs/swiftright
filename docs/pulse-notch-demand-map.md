# Pulse notch: SwiftRight porting demand map (plan step F12)

Status: first draft, 14 October 2026. Written for Adrian's choice of the Pulse notch as SwiftRight's first real consumer ("the first one can be pulse, its notch is swift"). Pulse was read, never changed. Every count below comes from `factory/tools/demand-map/` (regenerate with the command in "Reproduce") or from a cited file.

## Summary

1. **The Windows notch is not a GPUI app.** `windows/Cargo.toml` (name `pulse-windows-prototype`) depends on the `windows` crate, `rightkit-*` crates and nothing from GPUI; the notch is drawn by a software rasteriser into a layered Win32 window (`windows/README.md:3,7`; `windows/src/canvas.rs:3`, `windows/src/surface.rs:1-3`). GPUI appears in Pulse only as a donor: `vendor/petal` is a macOS disk explorer built on `gpui-ce` (`vendor/petal/Cargo.toml:5,15`), and `docs/implementation-plan.md:23` lists GPUI among the "earlier options rejected". The brief's "Windows GPUI notch" therefore means "the Windows Win32 software notch", and a SwiftRight port changes the renderer from a hand-written rasteriser to SwiftRight's GPUI-seeded renderer. That matters for the memory baseline (section 5).
2. **The Mac notch is 49,677 lines of Swift in 184 files, 19,341 lines in the 42 files that import SwiftUI.** It uses 237 distinct SwiftUI-level APIs. Against the 20 delivered blocks: 40 are covered by a block, 26 partly, 36 exist only in the SR0 runtime without a gated case, 124 are missing, 8 are Combine pieces the architecture excludes, and 3 are AppKit escapes (table in section 2).
3. **The notch has 17 journeys.** The Windows notch has the same surface for most of them; the real Windows gaps are session activity (J15), the Mac-only helper and Finder pieces (J16), display choice (J11) and several launcher and conveniences items (section 1).
4. **Recommended first slice: S1, the notch face with ring gauges, read-only** (J01 and J03, 15 SwiftUI files, 5,086 lines). It needs 40 missing APIs, spread over eight block families, four service adapters and a Mac-side carve-out (section 4).
5. **The baseline is thin.** Pulse has one 60 s idle CPU reading (0.21 percent of a core) and one private-memory reading (10.9 MB) for the Windows notch; it has no startup, wakeup or shipped-byte figure, and no 30-launch or three-sample protocol (section 5). Architecture section 11 says a missing comparable baseline blocks the performance claim.

## Method and limits

**Paths.** `docs/architecture.md`, `docs/sr1-*.md`, `docs/pulse-notch-demand-map.md`, `factory/`, `probes/` and `packages/` are in the SwiftRight repository. Everything else (`windows/`, `mac/`, `core/`, `qa/`, `README.md`, `STATUS*.md`, `PENDING-WINDOWS.md`, `docs/settings.md`, `docs/comparison/`, `docs/feasibility.md`, `docs/implementation-plan.md`, `docs/measurement.md`, `docs/resource-audit-astra-2026-10-12.md`) is in the Pulse repository at `/Volumes/D/claude/pulse`, with a `pulse/` prefix where that avoids doubt. Line numbers are as read on 14 October 2026.

<!-- generated:scan-meta -->
| Input | Value |
|---|---|
| Pulse checkout (read-only) | `/Volumes/D/claude/pulse` at `d6118f99d`; uncommitted changes under `mac/Notch`: 0 |
| SwiftRight checkout | `d07df2581` (manifest `swiftui-pilot-rounds-1-2`, 20 blocks) |
| Swift files / lines scanned | 184 files, 49,677 lines under `mac/Notch` (all targets: notch, Helper, Elevate, FinderExtension, Shared) |
| Files that `import SwiftUI` | 42 files, 19,341 lines |
| SwiftUI index | public declarations of `SwiftUI` and `SwiftUICore` in the pinned SDK (`SDKs/MacOSX.sdk`, `arm64e-apple-macos.swiftinterface`) |
| Witness sources read for coverage | 132 `Witness.swift` files of delivered cases under `factory/pipeline` |
<!-- /generated:scan-meta -->

The scan is lexical, not a compiler run. Comments and string contents are blanked (`factory/tools/demand-map/lexer.py`). A token counts as SwiftUI only if the pinned SDK's interface declares it (`swiftui_index.py`): types and property wrappers by name, View modifiers by name when followed by a call, receiver calls (`Path.addLine`, `GraphicsContext.fill`, ...) from a hand-checked allow-list in `scan_api.py`, and implicit members (`.leading`) only inside the arguments of a SwiftUI call. Known precision limits:

- A modifier name that a project method shares is skipped only where `scan_api.py` lists the case (`offset(for:)`, `position(of:)`, `frame(forContentRect:)`). Other collisions would be counted.
- Implicit members inside an array literal of a project enum can be counted as SwiftUI (for example `ForEach([ClipKind.text, .link ...])` at `mac/Notch/Sources/Launcher/ClipboardStripView.swift:1003`). These are single-digit counts.
- String interpolation is treated as code; uses inside `#if` branches are counted whether or not they compile on macOS.
- Coverage by a block is by name and, for initializers, by first label against the manifest's USRs (`coverage.py`); it says a block lists the symbol, not that every overload or composition the notch uses is gated. The block limits in section 2 apply.
- "Journeys" counts a journey when one of its files, or a shared file it inherits, uses the API. The shared groups are the design system and the notch surface (`journeys.json`); several journeys share `NotchWindowController.swift`, so spread numbers overstate independence. Both the inclusive count and the own-files count are shown.

## 1. Journeys

A journey is something a person does with the notch. The Mac notch is a Swift app (`mac/Notch/`, forked from Codenotch, `mac/Notch/FORK.md`); the hub (Tauri) and the Rust core are shared with Windows and are not part of the port (`README.md:9`). Settings live in the hub, not in the notch: a click on a ring opens the hub on a section (`mac/Notch/FORK.md`, rows "Clicks" and "Settings window").

<!-- generated:journey-table -->
| ID | Journey | What the user does | Source files (under `mac/Notch`) | SwiftUI files | APIs | Missing APIs |
|---|---|---|---|---|---|---|
| J01 | **Resting pill and open notch** | The always-present notch: a pill at the chosen edge that is open with every ring visible, drawn as one liquid silhouette on all four edges. | `App/AppDelegate.swift`, `App/CodenotchMain.swift`, `Features/NotchBulb.swift`, `Notch/BackgroundCursor.swift`, `Notch/NotchEdge.swift`, `Notch/NotchLayout.swift`, `Notch/NotchPanel.swift`, `Notch/NotchPlacement.swift`, `Notch/NotchWindowController.swift`, `Settings/NotchSize.swift`, `Settings/NotchVisibility.swift` | 4 own, 18 with shared | 118 | 43 |
| J02 | **Hover open, peek and fold** | Pointer contact opens the pill; events peek it open for 3, 5 or 10 seconds; a full-screen app folds it away. | `Notch/FullScreenDetector.swift`, `Notch/NotchWindowController.swift`, `Settings/PeekDuration.swift` | 1 own, 7 with shared | 91 | 32 |
| J03 | **Ring gauges (Claude, Codex, System, Disks)** | Per-provider cells: a glyph in a usage ring, an inner thin ring, colour bands, weekly headline and pace. | `Features/DailyPace.swift`, `Features/ProviderRing.swift`, `Features/UsagePace.swift`, `Features/WeeklyHeadline.swift`, `Model/UsageBand.swift`, `Providers/GlyphOutline.swift`, `Providers/ProviderGlyph.swift`, `Settings/WeeklyRing.swift` | 4 own, 17 with shared | 119 | 46 |
| J04 | **Hover cards and session list** | A card slides out of the notch on a neck for each ring: limit windows, resets, plan, account, drives, GPU, session rows. | `Features/TooltipCard.swift`, `Features/UsageResetCard.swift`, `Sessions/ActivitySummary.swift` | 3 own, 17 with shared | 131 | 53 |
| J05 | **Send and LocalSend nearby share** | The fifth cell: device picker card, drop target, Cmd-V to send the clipboard, transfer progress, incoming-share toast. | `Features/NoticeCard.swift`, `Sharing/NearbySharing.swift`, `Sharing/SendCard.swift`, `Sharing/SendProvider.swift` | 2 own, 16 with shared | 123 | 46 |
| J06 | **Tools cell and middle-click wheel** | The sixth cell lists one-tap tools; the middle button opens a liquid ring of tools round the pointer. | `Conveniences/ToolWheel.swift`, `Conveniences/ToolWheelMotion.swift`, `Conveniences/Tools.swift`, `Sharing/ToolsProvider.swift` | 2 own, 10 with shared | 72 | 29 |
| J07 | **Launcher** | Option+Space panel: apps, files, calculator, clipboard rows, snippets, notes, custom commands. | `Launcher/LauncherActions.swift`, `Launcher/LauncherConfig.swift`, `Launcher/LauncherController.swift`, `Launcher/LauncherFileSearch.swift`, `Launcher/LauncherHotKey.swift`, `Launcher/LauncherIndex.swift`, `Launcher/LauncherModel.swift`, `Launcher/LauncherNotes.swift`, `Launcher/LauncherView.swift` | 2 own, 10 with shared | 88 | 22 |
| J08 | **Clipboard history strip** | A strip of clip cards with boards, filters, preview and paste-back. | `App/ClipboardStripPicture.swift`, `Launcher/ClipboardCapture.swift`, `Launcher/ClipboardDrag.swift`, `Launcher/ClipboardModel.swift`, `Launcher/ClipboardPaster.swift`, `Launcher/ClipboardStripContent.swift`, `Launcher/ClipboardStripController.swift`, `Launcher/ClipboardStripView.swift` | 4 own, 12 with shared | 135 | 54 |
| J09 | **Settings entry points and hub hand-off** | Settings bulb with its neck, the move grip, click-to-open-hub on each ring, right-click Quit; the hub is a separate process. | `Features/MoveHandle.swift`, `Features/SettingsHandle.swift`, `Notch/NotchWindowController.swift`, `System/HubBridge.swift`, `System/HubLauncher.swift` | 3 own, 9 with shared | 110 | 46 |
| J10 | **Alerts, toasts and notifications** | Usage reset, limit reached, drive filling, session ended: a toast from the notch, a system banner, a chime. | `App/SessionChime.swift`, `Features/NoticeCard.swift`, `Features/UsageResetCard.swift`, `Model/DriveCapacityWatcher.swift`, `Model/NotificationChannel.swift`, `Model/ThresholdNotifier.swift`, `Model/UsageLimitWatcher.swift`, `Model/UsageResetWatcher.swift`, `Notch/NoticeStage.swift` | 3 own, 16 with shared | 120 | 44 |
| J11 | **Multi-display, placement and edges** | One notch per display, four edges, Option-drag along and round corners, per-display scope and preference. | `Features/MoveHandle.swift`, `Notch/CornerPassage.swift`, `Notch/NotchFleet.swift`, `Notch/NotchGeometry.swift`, `Notch/NotchPlacement.swift`, `Settings/DisplayPreference.swift`, `Settings/NotchScreenScope.swift` | 3 own, 9 with shared | 94 | 34 |
| J12 | **Accounts (Claude and Codex)** | Which account each ring reads, account switch, the Sync chats button on the Claude card, credentials read, plan and sign-in rows. | `Providers/ClaudeAccountBook.swift`, `Providers/ClaudeOAuthProvider.swift`, `Providers/ClaudeProfile.swift`, `Providers/CodexLocalProvider.swift`, `System/ClaudeAccountWatcher.swift`, `System/ClaudeChatSync.swift` | 1 own, 9 with shared | 46 | 10 |
| J13 | **Updates and the disk-image installer** | Update card (Update/Later), restart-after-update, and the disk-image card that installs, replaces or undoes an app. | `App/Updater.swift`, `Conveniences/DiskImageInstaller.swift`, `Conveniences/DiskImageWork.swift`, `Features/DiskImageCard.swift`, `Features/UpdateCard.swift` | 2 own, 16 with shared | 102 | 36 |
| J14 | **Keyboard and window conveniences (no notch UI)** | Fn as Command, window moves, Finder cut and paste, Auto Quit, Dock click, snippet expansion. | `Conveniences/AutoQuit.swift`, `Conveniences/ConveniencesService.swift`, `Conveniences/EventTapHub.swift`, `Conveniences/FinderCutPaste.swift`, `Conveniences/SnippetExpansion.swift`, `Conveniences/Windows/WindowActions.swift`, `Conveniences/Windows/WindowHotKeys.swift`, `Keyboard/FnCommand.swift` | 0 own, 0 with shared | 0 | 0 |
| J15 | **Agent session activity** | Watches Claude, Codex and Pi sessions: activity arc on the ring, finished-session peek, terminal tab focus. | `Sessions/ActivityCoordinator.swift`, `Sessions/ClaudeSessionMonitor.swift`, `Sessions/CodexActivityMonitor.swift`, `Sessions/PiResponseMonitor.swift`, `Sessions/SessionCompletionWatcher.swift`, `Sessions/TerminalTabFocus.swift` | 0 own, 0 with shared | 0 | 0 |
| J16 | **Uninstall helper, Finder extension and elevation** | Privileged launch daemon that moves apps to the Trash, the Finder Sync menu, the elevation client. | `Elevate/main.swift`, `FinderExtension/FinderSync.swift`, `Helper/TrashPolicy.swift`, `Helper/main.swift`, `Shared/HelperProtocol.swift`, `Conveniences/FinderMenuState.swift`, `System/PrivilegedHelper.swift` | 0 own, 0 with shared | 0 | 0 |
| J17 | **View-shot harness (CI acceptance pictures)** | Renders every view in qa/notch-views.json on the Mac; the Windows side renders the same list for the comparison. | `App/ClipboardStripPicture.swift`, `App/ViewShots.swift` | 2 own, 16 with shared | 122 | 46 |
<!-- /generated:journey-table -->

Two properties of the Mac notch decide how a port is cut. First, the panel handles pointer input before SwiftUI sees it: `NotchPanel.sendEvent` takes the right-click and the click and drag on the chrome because "the hit test lands on a SwiftUI subview that may consume it" (`mac/Notch/Sources/Notch/NotchPanel.swift:7-24`), so clicks, Option-drag and the menu are a window-service contract, not SwiftUI gestures. Second, the panel sits at `.statusBar` level on all Spaces and is non-activating (`mac/Notch/Sources/Notch/NotchPanel.swift:125-131`), which is what lets it float over the menu bar and full-screen apps without taking focus.

### Windows: has, lacks, differs

"Has" means the Windows notch ships the journey; "differs" means it ships it with a documented gap; "lacks" means it does not. Sources: `windows/README.md`, `docs/settings.md` ("Still to add on Windows"), `docs/comparison/behaviour.md` (60 rows, 7 high, 24 medium, 29 low) and `docs/comparison/README.md` (picture verdicts).

`docs/comparison/behaviour.md` is dated 12 October ("Read-only inventory from source, 2026-10-12"). Windows work continued on 13 October (`pulse/STATUS-WINDOWS.md`), so a row there can already be closed; where a later Pulse document says so, the note below says so. Treat the remaining rows as open on 12 October, not as verified today.

<!-- generated:journey-windows -->
| ID | Journey | Windows notch | Evidence (Pulse docs) | Windows files (`windows/src`) |
|---|---|---|---|---|
| J01 | Resting pill and open notch | has | Windows draws the same cells in a software rasteriser into a layered window per monitor (windows/README.md 'The notch'); comparison rows 'Resting/Expanded notch' all match. Windows has no surface style or colour transition (docs/settings.md 'Still to add on Windows'). | `main.rs`, `layout.rs`, `render.rs`, `canvas.rs`, `surface.rs`, `motion.rs` |
| J02 | Hover open, peek and fold | has | Show: Always show, On hover or Hidden, folds for a borderless full-monitor window (windows/README.md 'The notch'); peek length is a Windows setting too (docs/settings.md, 'Peek length'). | `main.rs`, `visibility.rs`, `lifecycle.rs` |
| J03 | Ring gauges (Claude, Codex, System, Disks) | differs | Windows has the five cells (windows/README.md 'The notch'). Differs: no inner activity arc while an agent works (docs/comparison/behaviour.md row 10, high), no refresh press-in (row 11), CPU and Memory are one System ring (docs/settings.md 'Still to add on Windows'), no daily pace ring. | `layout.rs`, `render.rs`, `glyphs.rs`, `canvas.rs` |
| J04 | Hover cards and session list | differs | Windows has the hover cards (windows/src/card.rs; comparison group 'Notch: hover-card' is low-severity glyph differences only). Windows lacks the running-session list and session-row click (behaviour.md rows 12-13, high and med). | `card.rs` |
| J05 | Send and LocalSend nearby share | has | Windows has the Send cell with device rows, drop or Ctrl+V, progress and Accept/Decline (windows/README.md 'Nearby sharing'; behaviour.md 'Checked, no material difference: Send'). Gap: Chat rows on the Send card (behaviour.md row 14, med). The LocalSend protocol runs in the hub on both platforms (windows/src/send.rs:3). | `send.rs`, `send_sys.rs` |
| J06 | Tools cell and middle-click wheel | differs | Windows has the wheel and Tools card (windows/README.md 'Tools'). The tool set differs from the Mac's (behaviour.md row 28, written 12 October when Windows had no notes, clipboard or task-view; docs/settings.md lists the current Windows wheel default, which now includes Clipboard). Comparison group 'Notch: wheel' is five low-severity glyph rows. | `wheel.rs`, `send.rs` |
| J07 | Launcher | differs | Windows launcher exists, off by default (windows/README.md 'Launcher'); Mac-only sources: dictionary, Apple Shortcuts, per-app hotkeys, content search, snippet expansion (docs/settings.md 'Still to add on Windows'; behaviour.md rows 38-40). | `launcher.rs`, `launcher_files.rs`, `launcher_notes.rs`, `launcher_commands.rs` |
| J08 | Clipboard history strip | has | Windows strip landed on 2026-10-13 (docs/settings.md 'Clipboard' rows; windows/src/clip_strip.rs); a few spec parts are still open (docs/settings.md 'Still to add on Windows'). | `clip_strip.rs`, `clip.rs`, `clip_capture.rs`, `clip_paste.rs` |
| J09 | Settings entry points and hub hand-off | differs | Windows has the Settings disc, move grip, right-click Quit and hub launch (windows/README.md 'The notch', hub.rs:1-9, bridge.rs:1-9). Differs: permission-dot click and outside-ring click (behaviour.md rows 24-25), relaunch route to Settings when hidden (row 27). | `hub.rs`, `bridge.rs`, `main.rs`, `layout.rs` |
| J10 | Alerts, toasts and notifications | differs | Windows has the toast queue, hover hold and reset, limit, drive, agent and update toasts (windows/README.md 'Toasts'; windows/src/alerts.rs). Toasts now come out in every Show state, including a Hidden notch (windows/README.md 'Toasts'), which closes the high-severity row 15 of docs/comparison/behaviour.md (written 12 October). Delivery and sound rows 17-23 are still listed as differences. | `alerts.rs`, `notify.rs`, `update.rs` |
| J11 | Multi-display, placement and edges | differs | Windows has one panel per monitor with its own edge and position (behaviour.md row 26, Windows-only). Missing on Windows: display choice and which displays (`displayPreference`, `notchScope`; docs/settings.md 'Still to add on Windows'); comparison rows 'appearance/all-displays', 'main-display' are windows-missing. | `main.rs`, `lifecycle.rs`, `runtime.rs` |
| J12 | Accounts (Claude and Codex) | differs | Windows reads one Claude account (no per-folder profiles), no Sign in action, no reset-credit extras (behaviour.md rows 1-5, high and med). Account rename and forget match (behaviour.md 'Checked, no material difference'). The hub's Accounts section is shared. | `usage.rs`, `claude_accounts.rs`, `desktop.rs`, `claude_sync.rs` |
| J13 | Updates and the disk-image installer | differs | Windows has update cards (windows/src/update.rs) and an installer card for new .msi/.msix/.exe downloads (windows/src/installer.rs); the trigger differs by platform (behaviour.md row 35, accepted) and auto-install defaults differ (rows 32-34, med). | `update.rs`, `installer.rs` |
| J14 | Keyboard and window conveniences (no notch UI) | differs | Windows has Alt-as-Ctrl editing keys and 34 window chords (windows/README.md 'Editing keys and window shortcuts'); Auto Quit, snippet expansion and Dock-click minimise are missing or redundant (behaviour.md rows 41-45). | `keys.rs`, `window_keys.rs` |
| J15 | Agent session activity | lacks | Windows has no session monitor; its 'agent turn ended' toast is inferred from transcript writes and is off by default (behaviour.md rows 10, 12, 13, 18; windows/src/alerts.rs `finish_loop`). | `alerts.rs`, `claude_watch.rs` |
| J16 | Uninstall helper, Finder extension and elevation | lacks | Mac-only by platform: Windows apps are removed through their own uninstaller (behaviour.md row 58, accepted) and Explorer has its own Copy as path (row 44). | none |
| J17 | View-shot harness (CI acceptance pictures) | has | windows/src/viewshots.rs renders the same list (windows/README.md 'Checks'); docs/comparison/README.md holds the pairs. | `viewshots.rs` |
<!-- /generated:journey-windows -->

The picture comparison covers the notch surfaces view by view. Rows are Mac against Windows renders of the same fixture (`docs/comparison/README.md`, header table: 231 match, 293 differ, 39 windows-missing, 217 mac-missing across notch and hub). Notch groups only:

<!-- generated:comparison-counts -->
| Notch group (docs/comparison/README.md) | match | differs | windows-missing | mac-missing |
|---|---|---|---|---|
| alert | 5 | 0 | 0 | 0 |
| disk | 20 | 6 | 0 | 0 |
| disk-image-card | 12 | 3 | 0 | 0 |
| hover-card | 14 | 12 | 0 | 0 |
| launcher | 7 | 3 | 0 | 0 |
| menu | 1 | 2 | 0 | 0 |
| nearby-card | 12 | 2 | 0 | 0 |
| notch | 16 | 0 | 0 | 0 |
| ring | 26 | 0 | 0 | 0 |
| send | 34 | 10 | 0 | 0 |
| send-card | 7 | 3 | 0 | 0 |
| tooltip | 0 | 6 | 0 | 0 |
| update | 0 | 4 | 0 | 0 |
| update-card | 2 | 2 | 0 | 0 |
| wheel | 0 | 5 | 0 | 0 |
| **all notch groups** | 156 | 58 | 0 | 0 |
<!-- /generated:comparison-counts -->

Every "differs" row in the notch groups is marked low severity: glyph shapes, clock hands, highlight insets (`docs/comparison/README.md`, groups `hover-card`, `send-card`, `wheel`, `launcher`, `update`). The behaviour gaps in `docs/comparison/behaviour.md` are where the Windows notch actually differs from the Mac's.

### The acceptance fixtures already exist

`qa/notch-views.json` and `qa/notch-views-hover.json` hold platform-neutral view fixtures that the Mac's `ViewShots` renders (`mac/Notch/Sources/App/ViewShots.swift:6-12`) and the Windows notch renders from the same list (`windows/src/viewshots.rs`; `windows/README.md` "Checks"). They are the natural picture acceptance for a ported notch.

<!-- generated:view-fixtures -->
| File | Area | Entries |
|---|---|---|
| `qa/notch-views.json` | hover-card | 27 |
| `qa/notch-views.json` | ring | 26 |
| `qa/notch-views.json` | clipboard | 23 |
| `qa/notch-views.json` | notch | 16 |
| `qa/notch-views.json` | disk-image-card | 15 |
| `qa/notch-views.json` | nearby-card | 14 |
| `qa/notch-views.json` | launcher | 11 |
| `qa/notch-views.json` | send-card | 10 |
| `qa/notch-views.json` | wheel | 6 |
| `qa/notch-views.json` | alert | 5 |
| `qa/notch-views.json` | update-card | 4 |
| `qa/notch-views.json` | menu | 1 |
| `qa/notch-views.json` | **total** | **158** |
| `qa/notch-views-hover.json` | (hover variant) | 82 |
| `qa/notch-views-hover.json` | **total** | **82** |
<!-- /generated:view-fixtures -->

## 2. API inventory

Generated by `factory/tools/demand-map/demand_map.py` over the 42 SwiftUI files. Status values:

- **delivered**: a delivered block's manifest (`factory/registry/manifest.json`, 20 blocks) lists the symbol.
- **partly**: the symbol is used in the sources of delivered cases (the `Witness.swift` files) but no block lists it, or a block covers one receiver and the notch uses another (the note says which).
- **ungated**: the SR0 runtime implements the declaration (`probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime`) but no delivered case gates it. It exists; its parity is unproven.
- **missing**: none of the above.
- **excluded**: Combine-based `ObservableObject`, `@Published`, `ObservedObject` and `onReceive` are outside the initial inventory (`docs/architecture.md` section 5, "Compatibility categories"); the model layer needs an Observation rewrite on the Mac first.
- **platform**: an AppKit escape that Windows replaces by runtime or service (`NSHostingView`, `NSViewRepresentable`, the app delegate adaptor).

<!-- generated:api-summary -->
| Kind | Delivered block | Partly covered | Runtime only, ungated | Missing | Excluded by architecture | AppKit escape | Distinct |
|---|---|---|---|---|---|---|---|
| Types | 18 | 5 | 11 | 34 | 0 | 2 | 70 |
| View modifiers | 11 | 6 | 4 | 48 | 0 | 0 | 69 |
| Builder and receiver calls (Path, GraphicsContext, Shape, Image, Gesture ...) | 2 | 3 | 1 | 22 | 0 | 0 | 28 |
| Explicit static members (`Type.member`) | 2 | 1 | 1 | 0 | 0 | 0 | 4 |
| Implicit members (`.leading`, `.semibold` ...) | 4 | 9 | 19 | 18 | 0 | 0 | 50 |
| Property wrappers | 2 | 1 | 0 | 2 | 1 | 1 | 7 |
| Environment keys | 1 | 1 | 0 | 0 | 0 | 0 | 2 |
| Combine / ObservableObject pieces | 0 | 0 | 0 | 0 | 7 | 0 | 7 |
| **total distinct APIs** | **40** | **26** | **36** | **124** | **8** | **3** | **237** |
<!-- /generated:api-summary -->

### Top missing APIs, ranked by journeys that need them

Rank key: journeys that use the API including the shared notch surface, then journeys whose own files use it, then use count. The shared surface puts many APIs at 14 or fewer, so read the own-files column to see which journeys depend on an API independently.

<!-- generated:missing-ranked -->
| # | Missing API | Kind | Journeys (with shared surface) | Journeys (own files) | Uses | Files | Own-file journeys (J-number) | First example |
|---|---|---|---|---|---|---|---|---|
| 1 | `background` | modifier | 14 | 9 | 40 | 13 | 04 05 07 08 09 10 11 12 17 | `mac/Notch/Sources/App/ClipboardStripPicture.swift:110` |
| 2 | `scaleEffect` | modifier | 14 | 8 | 24 | 11 | 01 03 05 06 08 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:492` |
| 3 | `onHover` | modifier | 14 | 2 | 5 | 4 | 05 08 | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:50` |
| 4 | `Path` | type | 12 | 7 | 44 | 10 | 01 03 06 08 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:342` |
| 5 | `clipShape` | modifier | 12 | 7 | 11 | 9 | 04 07 08 09 10 11 17 | `mac/Notch/Sources/App/ClipboardStripPicture.swift:111` |
| 6 | `color` (BlendMode/GraphicsContext.Shading) | implicit | 12 | 6 | 16 | 7 | 01 06 08 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:410` |
| 7 | `fixedSize` | modifier | 12 | 6 | 13 | 6 | 03 04 05 06 10 12 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:503` |
| 8 | `Canvas` | type | 12 | 6 | 9 | 7 | 01 06 08 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:407` |
| 9 | `addLine` (Path) | member-call | 11 | 6 | 39 | 8 | 01 03 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:368` |
| 10 | `offset` | modifier | 11 | 6 | 19 | 9 | 01 02 08 09 11 17 | `mac/Notch/Sources/App/ClipboardStripPicture.swift:130` |
| 11 | `move` (Path) | member-call | 11 | 6 | 17 | 8 | 01 03 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:366` |
| 12 | `position` | modifier | 11 | 6 | 16 | 5 | 01 02 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:495` |
| 13 | `closeSubpath` (Path) | member-call | 11 | 6 | 13 | 8 | 01 03 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:351` |
| 14 | `Group` | type | 11 | 6 | 10 | 7 | 03 04 05 08 10 17 | `mac/Notch/Sources/App/ViewShots.swift:43` |
| 15 | `Capsule` | type | 11 | 5 | 22 | 5 | 04 05 08 10 17 | `mac/Notch/Sources/App/ViewShots.swift:61` |
| 16 | `allowsHitTesting` | modifier | 11 | 5 | 17 | 7 | 01 08 09 10 11 | `mac/Notch/Sources/Features/MoveHandle.swift:142` |
| 17 | `addFilter` (GraphicsContext) | member-call | 11 | 5 | 14 | 6 | 01 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:421` |
| 18 | `addQuadCurve` (Path) | member-call | 11 | 5 | 12 | 5 | 01 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:367` |
| 19 | `Animatable` | type | 11 | 5 | 9 | 5 | 01 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:385` |
| 20 | `drawLayer` (GraphicsContext) | member-call | 11 | 5 | 7 | 6 | 01 06 09 10 11 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:424` |
| 21 | `AnyView` | type | 11 | 3 | 37 | 5 | 08 10 17 | `mac/Notch/Sources/App/ClipboardStripPicture.swift:12` |
| 22 | `addArc` (Path) | member-call | 11 | 3 | 8 | 3 | 03 06 10 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:347` |
| 23 | `ViewModifier` | type | 11 | 1 | 3 | 2 | 08 | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:60` |
| 24 | `ButtonStyleConfiguration` | type | 11 | 0 | 1 | 1 | none (shared surface only) | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:32` |
| 25 | `Glass` | type | 11 | 0 | 1 | 1 | none (shared surface only) | `mac/Notch/Sources/Settings/NotchSurfaceStyle.swift:58` |
| 26 | `brightness` | modifier | 11 | 0 | 1 | 1 | none (shared surface only) | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:47` |
| 27 | `AnimatablePair` | type | 10 | 4 | 52 | 5 | 01 09 10 11 | `mac/Notch/Sources/Features/MoveHandle.swift:66` |
| 28 | `GeometryReader` | type | 10 | 4 | 4 | 4 | 04 05 10 17 | `mac/Notch/Sources/App/ViewShots.swift:59` |
| 29 | `delay` (Animation) | member-call | 10 | 2 | 5 | 3 | 09 10 | `mac/Notch/Sources/Features/SettingsHandle.swift:237` |
| 30 | `glassEffect` | modifier | 10 | 2 | 4 | 3 | 09 11 | `mac/Notch/Sources/Features/MoveHandle.swift:209` |
| 31 | `accessibilityHidden` | modifier | 10 | 1 | 4 | 2 | 01 | `mac/Notch/Sources/Features/NotchBulb.swift:117` |
| 32 | `applying` (Path) | member-call | 10 | 1 | 4 | 2 | 10 | `mac/Notch/Sources/Notch/NoticeStage.swift:256` |
| 33 | `tint` | modifier | 10 | 1 | 3 | 2 | 17 | `mac/Notch/Sources/App/ViewShots.swift:51` |
| 34 | `bouncy` (Animation/Spring) | implicit | 10 | 1 | 2 | 2 | 09 | `mac/Notch/Sources/Features/SettingsHandle.swift:282` |
| 35 | `snappy` (Animation/Spring) | implicit | 10 | 1 | 2 | 2 | 09 | `mac/Notch/Sources/Features/SettingsHandle.swift:281` |
| 36 | `addCurve` (Path) | member-call | 10 | 0 | 2 | 2 | none (shared surface only) | `mac/Notch/Sources/Notch/NotchRootView.swift:792` |
| 37 | `contentShape` | modifier | 7 | 7 | 14 | 7 | 04 05 06 07 08 10 12 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:680` |
| 38 | `StrokeStyle` | type | 7 | 7 | 13 | 6 | 03 04 05 06 09 10 17 | `mac/Notch/Sources/App/ViewShots.swift:71` |
| 39 | `rotationEffect` | modifier | 6 | 6 | 8 | 5 | 01 03 04 05 09 10 | `mac/Notch/Sources/Features/NotchBulb.swift:110` |
| 40 | `trim` (Shape) | member-call | 6 | 6 | 5 | 5 | 03 04 05 09 10 17 | `mac/Notch/Sources/App/ViewShots.swift:70` |
<!-- /generated:missing-ranked -->

### Missing APIs by family (the block backlog)

The notch's 124 missing APIs fall into families that a block recipe would cover together. A name sits in the family whose table row lists it; the "plan" column says where `docs/sr1-plan.md` or `docs/sr1-decisions.md` already speaks to it.

<!-- generated:families -->
| Family | What it is | APIs the notch uses | Missing | Runtime only | Uses | Uses in S1 files | Journeys (all / own) | Where the SR1 plan stands |
|---|---|---|---|---|---|---|---|---|
| F-path | Vector paths (Path, its builders, StrokeStyle, trim) | 15 | 15 | 0 | 162 | 66 | 12 / 10 | docs/sr1-plan.md Foundations lists vector paths (fill, stroke, caps, joins, dashes, trim) as a renderer foundation still to add |
| F-canvas | Canvas drawing (Canvas, GraphicsContext, shading, layers, filters) | 7 | 7 | 0 | 50 | 0 | 12 / 7 | not in the SR1 plan; needs a retained-tree escape or a drawing-command ABI |
| F-transform | Transforms and placement (scaleEffect, rotationEffect, offset, position, degrees, radians) | 8 | 7 | 1 | 81 | 18 | 14 / 11 | docs/sr1-plan.md Foundations: full affine transforms (today translation only) |
| F-animatable | Animatable data and spring animation (Animatable, AnimatablePair, spring, snappy, bouncy, delay, keyframes) | 11 | 9 | 2 | 94 | 55 | 11 / 7 | block 18 covers linear, easeIn/Out/InOut and the default spring (docs/sr1-decisions.md C3-C4); custom springs and Animatable are new |
| F-pointer | Pointer, hit testing and gestures (onHover, allowsHitTesting, contentShape, onTapGesture, gestures) | 13 | 13 | 0 | 58 | 7 | 14 / 10 | docs/sr1-plan.md Foundations lists hit-testing; blocks 11 and 16 gate clicks only |
| F-style | Backgrounds, clipping and effects (background, clipShape, clipped, mask, shadow, brightness, tint, glassEffect, Glass) | 13 | 12 | 1 | 99 | 10 | 14 / 10 | docs/sr1-plan.md Foundations: clipping by shape; glass has no Windows source (the Windows notch is solid, pulse/docs/settings.md) |
| F-text | Type: Font.system, weights, text modifiers | 16 | 10 | 6 | 168 | 10 | 14 / 12 | block 4 gates Font.custom with bundled Tinos; Font.system is implemented in the runtime (Controls.swift:327) without a case |
| F-compose | Composition helpers (Group, AnyView, EmptyView, Spacer, ViewModifier, GeometryReader, EnvironmentKey, fixedSize) | 11 | 8 | 3 | 114 | 23 | 14 / 10 | ZStack and overlay are block 3; VStack and HStack are exercised in witnesses only |
| F-a11y | Accessibility modifiers | 8 | 7 | 1 | 35 | 5 | 13 / 8 | docs/architecture.md section 11: every inventory control needs an AccessKit mapping and UIA assertions |
<!-- /generated:families -->

### Initializer forms the delivered blocks do not list

A delivered type can still be used through an initializer label its block does not list. Project-defined initializers are excluded.

<!-- generated:form-gaps -->
| Initializer form | Uses | Files | Block that covers the type | Seen in a witness | First example |
|---|---|---|---|---|---|
| `Color(nsColor:)` | 4 | 4 | color-scheme | no | `mac/Notch/Sources/App/ViewShots.swift:278` |
| `Color(white:)` | 11 | 3 | color-scheme | no | `mac/Notch/Sources/App/ViewShots.swift:698` |
| `Image(nsImage:)` | 6 | 3 | image | no | `mac/Notch/Sources/App/ViewShots.swift:85` |
| `Transaction(animation:)` | 2 | 2 | animation | yes | `mac/Notch/Sources/Features/NoticeCard.swift:537` |
<!-- /generated:form-gaps -->

`Color(white:)` and `Color(nsColor:)` are the only two SwiftUI forms of `Color` the notch uses outside the block's statics; `Image(nsImage:)` is used only by the view-shot harness (`mac/Notch/Sources/App/ViewShots.swift:85-90`) and the shipped code never calls it.

### Block limits to read before claiming coverage

<!-- generated:block-table -->
| Block (`factory/registry/manifest.json`) | Manifest symbols | Notch APIs it covers | Limits to read before claiming coverage |
|---|---|---|---|
| `swiftui.shapes.fill-stroke` | 22 | 4 | Continuous stroke only; hairline strokes below 1.5 px untested (docs/sr1-status.md 'Known gaps'). Path, trim and dashes are not in this block's symbol list. |
| `swiftui.image` | 3 | 1 | SF Symbols map to Segoe Fluent Icons; 41 symbol sizes use measured ink overrides; glyph shape is reported, not gated (docs/sr1-decisions.md decision 3; docs/sr1-status.md 'Known gaps'). |
| `swiftui.stack-overlay` | 3 | 3 | ZStack and overlay only (factory/registry/manifest.json); VStack and HStack have no manifest entry. |
| `swiftui.text.bundled-font` | 7 | 2 | Segoe UI is the Windows body font, so glyph pixels are excluded (decision 2); the bundled Tinos font is exact through ABI 0.7. |
| `swiftui.custom-layout` | 10 | 2 | Layout protocol, left-to-right and right-to-left, exact (docs/sr1-status.md block 5). |
| `swiftui.scroll-view` | 3 | 1 | No ScrollViewReader or scrollPosition in the runtime; vertical offset 0, bottom anchor and horizontal axis measured (docs/sr1-status.md blocks 6). |
| `swiftui.toggle` | 5 | 0 | Switch and checkbox styles, measured at scale 2.5, light and dark (decisions 7, 8, D2). |
| `swiftui.disabled` | 1 | 2 | .disabled dims controls, not plain views (decision 10). |
| `swiftui.padding-frame` | 6 | 3 | padding all, per edge, EdgeInsets; fixed and flexible frames, 9 alignments (docs/sr1-status.md block 9). |
| `swiftui.preference-key` | 5 | 0 | Custom reduce, nil default, first contribution wins (docs/sr1-status.md block 10). |
| `swiftui.animation` | 17 | 8 | One explicit transaction per flush decides for every changed node; spring cases use a 2 px extent tolerance (docs/sr1-status.md block 18; decisions C1-C6). No Animatable, keyframes or TimelineView in the block's symbol list. |
| `swiftui.opacity-transition` | 5 | 4 | Image fade excluded; no .scale or custom Transition (docs/sr1-status.md block 19). |
| `swiftui.binding` | 9 | 1 | Setter transaction, constant, derived bindings (docs/sr1-status.md block 12). |
| `swiftui.textfield` | 10 | 3 | Windows focus ring not drawn; real IME and TSF deferred to hardware (docs/sr1-status.md block 13). |
| `swiftui.focus-state` | 7 | 3 | UIA keyboard focus is false in the Sandbox; gated through @FocusState text (docs/sr1-status.md block 14). |
| `swiftui.ime-marked-text` | 1 | 1 | Posted WM_IME messages only; real composition needs hardware (docs/sr1-status.md block 15). |
| `swiftui.alert` | 19 | 1 | Windows TaskDialog compared by semantics; main-window pixels reported, never a gate (docs/sr1-status.md block 17). |
| `swiftui.color-scheme` | 10 | 6 | Semantic colours measured light and dark; toggle artwork at scale 2.5 only (docs/sr1-status.md block 20). |
| `swiftui.button` | 25 | 4 | Every style measured in light only; pressed and focused states unmeasured; bordered and prominent are 7-8 px narrower (docs/sr1-status.md block 11). |
| `swiftui.list` | 10 | 2 | No scrolling, no sidebar or grouped styles, no dark appearance, no multi-selection adjacency (docs/sr1-decisions.md A10). |
<!-- /generated:block-table -->

### Full inventory: types

<!-- generated:api-types -->
| API | Uses | Files | Journeys (all / own files) | Status | Block or note | First example |
|---|---|---|---|---|---|---|
| `View` | 211 | 23 | 14 / 13 | delivered | alert, animation, button, color-scheme, disabled, focus-state, list, opacity-transition, padding-frame, stack-overlay, textfield | `mac/Notch/Sources/App/ClipboardStripPicture.swift:162` |
| `Color` | 185 | 20 | 14 / 12 | delivered | color-scheme | `mac/Notch/Sources/App/ViewShots.swift:278` |
| `Text` | 94 | 10 | 14 / 9 | delivered | text.bundled-font | `mac/Notch/Sources/App/ViewShots.swift:684` |
| `AnimatablePair` | 52 | 5 | 10 / 4 | missing |  | `mac/Notch/Sources/Features/MoveHandle.swift:66` |
| `Path` | 44 | 10 | 12 / 7 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:342` |
| `VStack` | 40 | 10 | 13 / 8 | partly | exercised in witnesses of alert, animation, binding and 12 more; no block of its own | `mac/Notch/Sources/App/ClipboardStripPicture.swift:144` |
| `ZStack` | 40 | 15 | 14 / 12 | delivered | stack-overlay | `mac/Notch/Sources/App/ViewShots.swift:60` |
| `Image` | 39 | 12 | 12 / 12 | delivered | image | `mac/Notch/Sources/App/ViewShots.swift:85` |
| `AnyView` | 37 | 5 | 11 / 3 | missing |  | `mac/Notch/Sources/App/ClipboardStripPicture.swift:12` |
| `Circle` | 36 | 11 | 13 / 11 | partly | exercised in witnesses of disabled, stack-layout; no block of its own | `mac/Notch/Sources/App/ViewShots.swift:69` |
| `ForEach` | 36 | 10 | 13 / 9 | delivered | list | `mac/Notch/Sources/App/ClipboardStripPicture.swift:144` |
| `HStack` | 36 | 9 | 13 / 7 | partly | exercised in witnesses of animation, binding, button and 4 more; no block of its own | `mac/Notch/Sources/App/ClipboardStripPicture.swift:148` |
| `RoundedRectangle` | 30 | 9 | 11 / 6 | delivered | shapes.fill-stroke | `mac/Notch/Sources/App/ClipboardStripPicture.swift:110` |
| `Rectangle` | 25 | 7 | 12 / 7 | delivered | shapes.fill-stroke | `mac/Notch/Sources/Features/MoveHandle.swift:209` |
| `Animation` | 23 | 4 | 11 / 1 | delivered | animation | `mac/Notch/Sources/Conveniences/ToolWheel.swift:671` |
| `Capsule` | 22 | 5 | 11 / 5 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:61` |
| `Spacer` | 21 | 6 | 6 / 6 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/App/ViewShots.swift:685` |
| `StrokeStyle` | 13 | 6 | 7 / 7 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:71` |
| `EnvironmentKey` | 11 | 8 | 11 / 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/App/ViewShots.swift:20` |
| `EmptyView` | 10 | 5 | 11 / 5 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/App/CodenotchMain.swift:10` |
| `EnvironmentValues` | 10 | 8 | 11 / 2 | delivered | color-scheme | `mac/Notch/Sources/App/ViewShots.swift:24` |
| `Group` | 10 | 7 | 11 / 6 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:43` |
| `Animatable` | 9 | 5 | 11 / 5 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:385` |
| `Canvas` | 9 | 7 | 12 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:407` |
| `Font` | 8 | 2 | 11 / 2 | delivered | text.bundled-font | `mac/Notch/Sources/DesignSystem/Typography.swift:7` |
| `Shape` | 8 | 6 | 11 / 4 | delivered | shapes.fill-stroke | `mac/Notch/Sources/Conveniences/ToolWheel.swift:448` |
| `NSHostingView` | 7 | 5 | 13 / 4 | platform | AppKit escape hatch (Mac only) | `mac/Notch/Sources/Conveniences/ToolWheel.swift:156` |
| `ScrollView` | 6 | 3 | 3 / 3 | delivered | scroll-view | `mac/Notch/Sources/App/ViewShots.swift:123` |
| `UnevenRoundedRectangle` | 5 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/App/ClipboardStripPicture.swift:188` |
| `GeometryReader` | 4 | 4 | 10 / 4 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:59` |
| `NSViewRepresentable` | 4 | 2 | 2 / 2 | platform | AppKit escape hatch (Mac only) | `mac/Notch/Sources/Features/ProviderRing.swift:287` |
| `Alignment` | 3 | 2 | 10 / 1 | partly | exercised in witnesses of padding-frame, pixel-ties; no block of its own | `mac/Notch/Sources/Features/ProviderRing.swift:786` |
| `AnyLayout` | 3 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:247` |
| `ColorScheme` | 3 | 1 | 1 / 1 | delivered | color-scheme | `mac/Notch/Sources/Features/TooltipCard.swift:10` |
| `Divider` | 3 | 2 | 2 / 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:851` |
| `GridItem` | 3 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:306` |
| `LinearGradient` | 3 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:803` |
| `ProgressView` | 3 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:45` |
| `Transaction` | 3 | 3 | 10 / 3 | delivered | animation | `mac/Notch/Sources/Features/NoticeCard.swift:537` |
| `ViewModifier` | 3 | 2 | 11 / 1 | missing |  | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:60` |
| `ImageRenderer` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:270` |
| `LazyVGrid` | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:307` |
| `ProposedViewSize` | 2 | 1 | 1 / 1 | partly | exercised in witnesses of stack-layout; no block of its own | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:1058` |
| `ScrollViewReader` | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:265` |
| `SpringKeyframe` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:280` |
| `TapGesture` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:368` |
| `TimelineView` | 2 | 2 | 3 / 3 | missing |  | `mac/Notch/Sources/Features/MoveHandle.swift:302` |
| `App` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/CodenotchMain.swift:4` |
| `ButtonStyle` | 1 | 1 | 11 / 0 | delivered | button | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:7` |
| `ButtonStyleConfiguration` | 1 | 1 | 11 / 0 | missing |  | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:32` |
| `CommandGroup` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/CodenotchMain.swift:12` |
| `DragGesture` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:493` |
| `EventModifiers` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripContent.swift:206` |
| `FillStyle` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Providers/ProviderGlyph.swift:81` |
| `Glass` | 1 | 1 | 11 / 0 | missing |  | `mac/Notch/Sources/Settings/NotchSurfaceStyle.swift:58` |
| `GraphicsContext` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:425` |
| `HStackLayout` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:247` |
| `KeyEquivalent` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:856` |
| `Label` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:866` |
| `Layout` | 1 | 1 | 1 / 1 | delivered | custom-layout | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:1055` |
| `LazyHStack` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:271` |
| `LazyVStack` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:269` |
| `Menu` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:853` |
| `Scene` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/CodenotchMain.swift:7` |
| `Settings` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/CodenotchMain.swift:10` |
| `SpatialTapGesture` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:696` |
| `TextEditor` | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/LauncherView.swift:168` |
| `TextField` | 1 | 1 | 1 / 1 | delivered | ime-marked-text, textfield | `mac/Notch/Sources/Launcher/LauncherView.swift:29` |
| `UnitPoint` | 1 | 1 | 10 / 0 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Notch/NotchRootView.swift:360` |
| `VStackLayout` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:247` |
<!-- /generated:api-types -->

### Full inventory: View modifiers

<!-- generated:api-modifiers -->
| API | Uses | Files | Journeys (all / own files) | Status | Block or note | First example |
|---|---|---|---|---|---|---|
| `frame` | 193 | 18 | 14 / 12 | delivered | padding-frame | `mac/Notch/Sources/App/ClipboardStripPicture.swift:104` |
| `foregroundStyle` | 117 | 13 | 14 / 12 | partly | Text colour is gated (docs/sr1-status.md block 8 text-colour gate, decision 11) and Button label colour (decision A3); other receivers are not measured | `mac/Notch/Sources/App/ViewShots.swift:686` |
| `font` | 112 | 13 | 14 / 12 | partly | exercised in witnesses of text-shape-image; no block of its own | `mac/Notch/Sources/App/ViewShots.swift:688` |
| `padding` | 111 | 8 | 12 / 6 | delivered | padding-frame | `mac/Notch/Sources/App/ClipboardStripPicture.swift:112` |
| `opacity` | 103 | 17 | 14 / 12 | delivered | opacity-transition | `mac/Notch/Sources/App/ViewShots.swift:61` |
| `animation` | 43 | 10 | 14 / 7 | delivered | animation | `mac/Notch/Sources/Conveniences/ToolWheel.swift:494` |
| `background` | 40 | 13 | 14 / 9 | missing |  | `mac/Notch/Sources/App/ClipboardStripPicture.swift:110` |
| `lineLimit` | 39 | 7 | 7 / 7 | partly | exercised in witnesses of text-shape-image; no block of its own | `mac/Notch/Sources/Features/NoticeCard.swift:235` |
| `environment` | 26 | 5 | 12 / 5 | partly | exercised in witnesses of color-scheme, padding-frame, pixel-ties and 4 more; no block of its own | `mac/Notch/Sources/App/ViewShots.swift:255` |
| `scaleEffect` | 24 | 11 | 14 / 8 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:492` |
| `overlay` | 23 | 10 | 13 / 9 | delivered | stack-overlay | `mac/Notch/Sources/App/ClipboardStripPicture.swift:129` |
| `offset` | 19 | 9 | 11 / 6 | missing |  | `mac/Notch/Sources/App/ClipboardStripPicture.swift:130` |
| `allowsHitTesting` | 17 | 7 | 11 / 5 | missing |  | `mac/Notch/Sources/Features/MoveHandle.swift:142` |
| `buttonStyle` | 17 | 5 | 5 / 5 | delivered | button | `mac/Notch/Sources/Features/NoticeCard.swift:333` |
| `position` | 16 | 5 | 11 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:495` |
| `accessibilityLabel` | 15 | 7 | 13 / 7 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/NoticeCard.swift:359` |
| `contentShape` | 14 | 7 | 7 / 7 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:680` |
| `fixedSize` | 13 | 6 | 12 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:503` |
| `clipShape` | 11 | 9 | 12 / 7 | missing |  | `mac/Notch/Sources/App/ClipboardStripPicture.swift:111` |
| `onChange` | 9 | 6 | 12 / 6 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/NoticeCard.swift:363` |
| `rotationEffect` | 8 | 5 | 6 / 6 | missing |  | `mac/Notch/Sources/Features/NotchBulb.swift:110` |
| `transition` | 8 | 5 | 11 / 4 | delivered | opacity-transition | `mac/Notch/Sources/Conveniences/ToolWheel.swift:556` |
| `onAppear` | 6 | 4 | 12 / 4 | partly | exercised in witnesses of alert, animation, opacity-transition; no block of its own | `mac/Notch/Sources/Conveniences/ToolWheel.swift:681` |
| `accessibilityElement` | 5 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/ProviderRing.swift:528` |
| `multilineTextAlignment` | 5 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:321` |
| `onHover` | 5 | 4 | 14 / 2 | missing |  | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:50` |
| `onTapGesture` | 5 | 3 | 3 / 3 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:336` |
| `accessibilityHidden` | 4 | 2 | 10 / 1 | missing |  | `mac/Notch/Sources/Features/NotchBulb.swift:117` |
| `clipped` | 4 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:149` |
| `glassEffect` | 4 | 3 | 10 / 2 | missing |  | `mac/Notch/Sources/Features/MoveHandle.swift:209` |
| `minimumScaleFactor` | 4 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/ProviderRing.swift:837` |
| `scaledToFit` | 4 | 2 | 2 / 2 | partly | exercised in witnesses of text-shape-image; no block of its own | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:627` |
| `contextMenu` | 3 | 2 | 4 / 4 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:371` |
| `disabled` | 3 | 3 | 4 / 4 | delivered | disabled | `mac/Notch/Sources/Features/NoticeCard.swift:463` |
| `help` | 3 | 3 | 4 / 4 | missing |  | `mac/Notch/Sources/Features/NoticeCard.swift:334` |
| `onDrop` | 3 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:374` |
| `tint` | 3 | 2 | 10 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:51` |
| `truncationMode` | 3 | 3 | 3 / 3 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:666` |
| `accessibilityAddTraits` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:180` |
| `accessibilityValue` | 2 | 2 | 3 / 3 | missing |  | `mac/Notch/Sources/Features/NoticeCard.swift:360` |
| `contentTransition` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/ProviderRing.swift:839` |
| `focused` | 2 | 1 | 1 / 1 | delivered | focus-state | `mac/Notch/Sources/Launcher/LauncherView.swift:33` |
| `fontWeight` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:578` |
| `gesture` | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:696` |
| `keyboardShortcut` | 2 | 2 | 2 / 2 | delivered | button | `mac/Notch/Sources/App/CodenotchMain.swift:14` |
| `modifier` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:181` |
| `monospacedDigit` | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/ProviderRing.swift:833` |
| `simultaneousGesture` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:368` |
| `task` | 2 | 1 | 10 / 0 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Notch/NotchRootView.swift:65` |
| `textSelection` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:147` |
| `tracking` | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:63` |
| `accessibilityAction` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:502` |
| `aspectRatio` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:261` |
| `autocorrectionDisabled` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:34` |
| `brightness` | 1 | 1 | 11 / 0 | missing |  | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:47` |
| `controlSize` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:53` |
| `defaultAppStorage` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:254` |
| `foregroundColor` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:265` |
| `keyframeAnimator` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:277` |
| `layoutPriority` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:91` |
| `mask` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:154` |
| `matchedGeometryEffect` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:725` |
| `onContinuousHover` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:685` |
| `onDrag` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:373` |
| `popover` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:330` |
| `progressViewStyle` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:50` |
| `scrollContentBackground` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:169` |
| `shadow` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:678` |
| `textFieldStyle` | 1 | 1 | 1 / 1 | delivered | textfield | `mac/Notch/Sources/Launcher/LauncherView.swift:30` |
<!-- /generated:api-modifiers -->

### Full inventory: receiver calls and explicit statics

<!-- generated:api-members -->
| API | Uses | Files | Journeys (all / own files) | Status | Block or note | First example |
|---|---|---|---|---|---|---|
| `fill` (Shape/GraphicsContext) | 89 | 18 | 14 / 12 | partly | Shape.fill is delivered (shapes.fill-stroke); the Canvas GraphicsContext.fill form is not in any block | `mac/Notch/Sources/App/ClipboardStripPicture.swift:110` |
| `addLine` (Path) | 39 | 8 | 11 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:368` |
| `move` (Path) | 17 | 8 | 11 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:366` |
| `place` (LayoutSubview) | 15 | 3 | 5 / 5 | delivered | custom-layout | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:1065` |
| `addFilter` (GraphicsContext) | 14 | 6 | 11 / 5 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:421` |
| `stroke` (Shape/GraphicsContext) | 14 | 6 | 7 / 7 | partly | Shape.stroke is delivered (shapes.fill-stroke); the Canvas GraphicsContext.stroke form is not in any block | `mac/Notch/Sources/App/ViewShots.swift:71` |
| `closeSubpath` (Path) | 13 | 8 | 11 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:351` |
| `strokeBorder` (InsettableShape) | 13 | 7 | 8 / 8 | delivered | shapes.fill-stroke | `mac/Notch/Sources/App/ViewShots.swift:699` |
| `Animation.spring` | 12 | 2 | 11 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Conveniences/ToolWheelMotion.swift:49` |
| `addQuadCurve` (Path) | 12 | 5 | 11 / 5 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:367` |
| `addArc` (Path) | 8 | 3 | 11 / 3 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:347` |
| `resizable` (Image) | 8 | 4 | 4 / 4 | partly | exercised in witnesses of text-shape-image | `mac/Notch/Sources/App/ViewShots.swift:86` |
| `drawLayer` (GraphicsContext) | 7 | 6 | 11 / 5 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:424` |
| `delay` (Animation) | 5 | 3 | 10 / 2 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:237` |
| `trim` (Shape) | 5 | 5 | 6 / 6 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:70` |
| `Animation.easeInOut` | 4 | 2 | 11 / 1 | delivered | animation | `mac/Notch/Sources/Conveniences/ToolWheelMotion.swift:51` |
| `applying` (Path) | 4 | 2 | 10 / 1 | missing |  | `mac/Notch/Sources/Notch/NoticeStage.swift:256` |
| `onEnded` (Gesture) | 4 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:696` |
| `interpolation` (Image) | 3 | 3 | 3 / 3 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:87` |
| `Color.accentColor` | 2 | 2 | 2 / 2 | partly | exercised in witnesses | `mac/Notch/Sources/App/ViewShots.swift:693` |
| `addCurve` (Path) | 2 | 2 | 10 / 0 | missing |  | `mac/Notch/Sources/Notch/NotchRootView.swift:792` |
| `combined` (AnyTransition) | 2 | 2 | 10 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/SettingsHandle.swift:253` |
| `scrollTo` (ScrollViewProxy) | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:277` |
| `Animation.easeIn` | 1 | 1 | 10 / 0 | delivered | animation | `mac/Notch/Sources/Notch/NotchMotion.swift:109` |
| `addEllipse` (Path) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/ProviderRing.swift:749` |
| `commands` (Scene) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/CodenotchMain.swift:11` |
| `interactive` (Glass) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:173` |
| `offsetBy` (Path) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:527` |
| `onChanged` (Gesture) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:493` |
| `strokedPath` (Path) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:303` |
| `translateBy` (GraphicsContext) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Notch/CornerPassage.swift:170` |
| `trimmedPath` (Path) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:530` |
<!-- /generated:api-members -->

### Full inventory: implicit members

Owners in brackets are the SwiftUI value types that declare the name; the scan cannot resolve which one the call site means.

<!-- generated:api-implicit -->
| API | Uses | Files | Journeys (all / own files) | Status | Block or note | First example |
|---|---|---|---|---|---|---|
| `system` (Font) | 87 | 12 | 14 / 11 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/App/ViewShots.swift:688` |
| `leading` (Alignment/Edge/Edge.Set) | 53 | 7 | 12 / 6 | partly | exercised in witnesses of alert, animation, binding and 10 more; no manifest symbol | `mac/Notch/Sources/App/ViewShots.swift:60` |
| `top` (Alignment/Edge/Edge.Set) | 45 | 7 | 12 / 6 | partly | exercised in witnesses of button, opacity-transition, padding-frame and 1 more; no manifest symbol | `mac/Notch/Sources/App/ClipboardStripPicture.swift:113` |
| `topLeading` (Alignment/UnitPoint) | 40 | 9 | 12 / 7 | partly | exercised in witnesses of animation, binding, color-scheme and 3 more; no manifest symbol | `mac/Notch/Sources/App/ClipboardStripPicture.swift:129` |
| `horizontal` (Alignment/Axis/Axis.Set) | 32 | 8 | 12 / 6 | partly | exercised in witnesses of padding-frame, pixel-ties, scroll-view; no manifest symbol | `mac/Notch/Sources/App/ClipboardStripPicture.swift:112` |
| `semibold` (Font.Weight) | 32 | 10 | 14 / 8 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Conveniences/ToolWheel.swift:499` |
| `white` (Color/ShapeStyle) | 21 | 2 | 11 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/DesignSystem/Palette.swift:24` |
| `color` (BlendMode/GraphicsContext.Shading) | 16 | 7 | 12 / 6 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:410` |
| `bottom` (Alignment/Edge/Edge.Set) | 11 | 5 | 4 / 4 | partly | exercised in witnesses of padding-frame, pixel-ties, scroll-view; no manifest symbol | `mac/Notch/Sources/App/ClipboardStripPicture.swift:114` |
| `vertical` (Alignment/Axis/Axis.Set) | 10 | 4 | 4 / 4 | partly | exercised in witnesses of padding-frame, pixel-ties, scroll-view; no manifest symbol | `mac/Notch/Sources/App/ViewShots.swift:123` |
| `easeOut` (Animation) | 9 | 5 | 14 / 5 | delivered | animation | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:48` |
| `center` (Alignment/HorizontalAlignment/TextAlignment) | 8 | 3 | 4 / 4 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/NoticeCard.swift:263` |
| `regular` (ControlSize/Font.Weight/Material) | 8 | 6 | 13 / 5 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/DesignSystem/Typography.swift:27` |
| `radians` (Angle) | 7 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Conveniences/ToolWheel.swift:347` |
| `continuous` (RoundedCornerStyle) | 6 | 3 | 11 / 3 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:69` |
| `dark` (ColorScheme) | 6 | 5 | 12 / 5 | delivered | color-scheme | `mac/Notch/Sources/App/ViewShots.swift:258` |
| `medium` (Font.Weight/Image.Scale) | 6 | 3 | 3 / 3 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Conveniences/ToolWheel.swift:490` |
| `monospaced` (Font/Font.Design) | 6 | 2 | 2 / 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:578` |
| `opacity` (AnyTransition/Color/ShapeStyle) | 6 | 4 | 11 / 3 | delivered | opacity-transition | `mac/Notch/Sources/Conveniences/ToolWheel.swift:556` |
| `spring` (Animation) | 6 | 4 | 10 / 4 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/ProviderRing.swift:160` |
| `degrees` (Angle) | 5 | 4 | 5 / 5 | missing |  | `mac/Notch/Sources/Features/NoticeCard.swift:506` |
| `bold` (Font/Font.Weight) | 4 | 3 | 4 / 4 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/NoticeCard.swift:319` |
| `isButton` (AccessibilityTraits) | 4 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:180` |
| `black` (Color/Font.Weight/ShapeStyle) | 3 | 1 | 11 / 0 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/DesignSystem/Palette.swift:25` |
| `circular` (RoundedCornerStyle) | 3 | 2 | 2 / 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/TooltipCard.swift:62` |
| `topTrailing` (Alignment/UnitPoint) | 3 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:335` |
| `animation` (AnyTransition/Transaction) | 2 | 2 | 3 / 3 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Features/MoveHandle.swift:302` |
| `bottomLeading` (Alignment/UnitPoint) | 2 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:713` |
| `bottomTrailing` (Alignment/UnitPoint) | 2 | 1 | 1 / 1 | partly | exercised in witnesses of padding-frame, pixel-ties, stack-layout; no manifest symbol | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:804` |
| `bouncy` (Animation/Spring) | 2 | 2 | 10 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:282` |
| `clear` (Color/KeyEquivalent/ShapeStyle) | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:215` |
| `heavy` (Font.Weight) | 2 | 1 | 2 / 2 | missing |  | `mac/Notch/Sources/Features/NoticeCard.swift:345` |
| `image` (ShapeStyle) | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:466` |
| `isSelected` (AccessibilityTraits) | 2 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:180` |
| `linear` (Animation/ColorRenderingMode) | 2 | 2 | 3 / 3 | delivered | animation | `mac/Notch/Sources/App/ViewShots.swift:50` |
| `middle` (Text.TruncationMode) | 2 | 2 | 2 / 2 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:666` |
| `snappy` (Animation/Spring) | 2 | 2 | 10 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:281` |
| `trailing` (Alignment/Edge/Edge.Set) | 2 | 1 | 1 / 1 | partly | exercised in witnesses of padding-frame, pixel-ties, stack-layout; no manifest symbol | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:334` |
| `asymmetric` (AnyTransition) | 1 | 1 | 10 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Notch/NoticeStage.swift:280` |
| `command` (EventModifiers) | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/App/CodenotchMain.swift:14` |
| `fill` (ContentMode/ShapeStyle) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/LauncherView.swift:261` |
| `firstTextBaseline` (VerticalAlignment) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:730` |
| `hidden` (Visibility) | 1 | 1 | 1 / 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Launcher/LauncherView.swift:169` |
| `link` (ShapeStyle) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:1003` |
| `logicallyComplete` (Animation) | 1 | 1 | 10 / 1 | partly | exercised in witnesses of animation; no manifest symbol | `mac/Notch/Sources/Notch/NoticeStage.swift:424` |
| `offset` (AnyTransition) | 1 | 1 | 10 / 0 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case | `mac/Notch/Sources/Notch/NotchRootView.swift:415` |
| `scale` (AnyTransition) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:253` |
| `small` (ControlSize/Image.Scale) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/App/ViewShots.swift:53` |
| `tail` (Text.TruncationMode) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Sharing/SendCard.swift:48` |
| `timingCurve` (Animation) | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/SettingsHandle.swift:236` |
<!-- /generated:api-implicit -->

### Full inventory: property wrappers, environment keys, Combine

<!-- generated:api-wrappers -->
| API | Uses | Files | Journeys (all / own files) | Status | Block or note | First example |
|---|---|---|---|---|---|---|
| `.sink {` | 52 | 6 | 12 / 6 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/App/AppDelegate.swift:204` |
| `@Published` | 51 | 5 | 13 / 3 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/Conveniences/ToolWheel.swift:635` |
| `Environment` | 51 | 13 | 14 / 11 | partly | used in witnesses of color-scheme | `mac/Notch/Sources/App/ViewShots.swift:37` |
| `.receive(on` | 38 | 4 | 5 / 5 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/App/AppDelegate.swift:203` |
| `State` | 23 | 9 | 14 / 6 | delivered | binding | `mac/Notch/Sources/Conveniences/ToolWheel.swift:647` |
| `ObservedObject` | 11 | 6 | 14 / 4 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/Conveniences/ToolWheel.swift:643` |
| `colorScheme` | 7 | 5 | 12 / 5 | delivered | color-scheme | `mac/Notch/Sources/App/ViewShots.swift:258` |
| `AnyCancellable` | 6 | 6 | 12 / 6 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/App/AppDelegate.swift:22` |
| `ObservableObject` | 6 | 5 | 13 / 3 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/Conveniences/ToolWheel.swift:634` |
| `import Combine` | 6 | 6 | 12 / 6 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/App/AppDelegate.swift:2` |
| `.objectWillChange` | 3 | 3 | 3 / 3 | excluded | outside inventory (architecture section 5) | `mac/Notch/Sources/App/AppDelegate.swift:559` |
| `FocusState` | 2 | 1 | 1 / 1 | delivered | focus-state | `mac/Notch/Sources/Launcher/LauncherView.swift:8` |
| `isEnabled` | 2 | 2 | 11 / 1 | partly | the runtime publishes isEnabled for .disabled (decision 10); reading it through EnvironmentValues is not a manifest symbol | `mac/Notch/Sources/App/ViewShots.swift:256` |
| `AppStorage` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Features/TooltipCard.swift:867` |
| `NSApplicationDelegateAdaptor` | 1 | 1 | 1 / 1 | platform | Mac app entry (architecture section 5: Windows uses an SDK-owned entry) | `mac/Notch/Sources/App/CodenotchMain.swift:5` |
| `Namespace` | 1 | 1 | 1 / 1 | missing |  | `mac/Notch/Sources/Launcher/ClipboardStripView.swift:64` |
<!-- /generated:api-wrappers -->

### AppKit and Core Graphics inside the SwiftUI files

These are not SwiftUI APIs; they are where a SwiftUI file reaches into AppKit. They decide the Mac-side carve-out work before a file can compile on Windows.

<!-- generated:interop -->
| AppKit / Core Animation / Core Graphics name inside SwiftUI files | Uses | First example |
|---|---|---|
| `NSColor` | 39 | `mac/Notch/Sources/App/ViewShots.swift:246` |
| `NSEvent` | 37 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:172` |
| `NSScreen` | 32 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:142` |
| `NSNumber` | 24 | `mac/Notch/Sources/App/ClipboardStripPicture.swift:14` |
| `NSWorkspace` | 23 | `mac/Notch/Sources/App/ViewShots.swift:85` |
| `CATransaction` | 22 | `mac/Notch/Sources/Features/ProviderRing.swift:344` |
| `NSRect` | 19 | `mac/Notch/Sources/App/ViewShots.swift:101` |
| `NSView` | 13 | `mac/Notch/Sources/Features/ProviderRing.swift:304` |
| `NSPoint` | 10 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:143` |
| `CGAffineTransform` | 8 | `mac/Notch/Sources/Notch/NoticeStage.swift:244` |
| `NSApp` | 7 | `mac/Notch/Sources/App/AppDelegate.swift:102` |
| `NSAppearance` | 7 | `mac/Notch/Sources/App/ViewShots.swift:168` |
| `NSHostingView` | 7 | `mac/Notch/Sources/Conveniences/ToolWheel.swift:156` |
| `NSDraggingInfo` | 7 | `mac/Notch/Sources/Notch/NotchHostingView.swift:55` |
| `NSImage` | 6 | `mac/Notch/Sources/App/ViewShots.swift:90` |
| `NSCursor` | 6 | `mac/Notch/Sources/DesignSystem/CardButtonStyle.swift:52` |
| `NSApplication` | 5 | `mac/Notch/Sources/App/AppDelegate.swift:1101` |
| `NSFont` | 5 | `mac/Notch/Sources/Features/NoticeCard.swift:49` |
| `CADisplayLink` | 5 | `mac/Notch/Sources/Notch/NotchWindowController.swift:801` |
| `NSRunningApplication` | 4 | `mac/Notch/Sources/App/AppDelegate.swift:58` |
| `NSGraphicsContext` | 4 | `mac/Notch/Sources/App/ViewShots.swift:97` |
| `CGColorSpace` | 4 | `mac/Notch/Sources/App/ViewShots.swift:289` |
| `NSString` | 4 | `mac/Notch/Sources/Features/NoticeCard.swift:164` |
| `NSViewRepresentable` | 4 | `mac/Notch/Sources/Features/ProviderRing.swift:287` |
| `CGColor` | 4 | `mac/Notch/Sources/Features/ProviderRing.swift:319` |
| `NSObject` | 3 | `mac/Notch/Sources/App/AppDelegate.swift:5` |
| `NSBitmapImageRep` | 3 | `mac/Notch/Sources/App/ViewShots.swift:93` |
| `CAShapeLayer` | 3 | `mac/Notch/Sources/Features/ProviderRing.swift:315` |
| `NSCoder` | 3 | `mac/Notch/Sources/Features/ProviderRing.swift:333` |
| `CABasicAnimation` | 3 | `mac/Notch/Sources/Features/ProviderRing.swift:392` |
| geometry value types (`CGFloat` 876, `CGPoint` 599, `CGRect` 66, `CGSize` 47, `CGVector` 15) | 1603 | portable: delivered blocks already use `CoreFoundation.CGFloat` and `CGSize` (factory/registry/manifest.json) |
<!-- /generated:interop -->

The ring's arc is the clearest case: `GaugeArcLayer` is an `NSViewRepresentable` that animates a `CAShapeLayer` stroke with `CABasicAnimation` (`mac/Notch/Sources/Features/ProviderRing.swift:287-392`). A Windows build needs that arc expressed as a SwiftUI `Shape` with `trim` and a spring, which is the F-path and F-animatable families, and the Mac notch would have to switch to the same view so that one source serves both.

## 3. Platform services

These are the AppKit and macOS services the notch relies on, scanned over every Swift file in `mac/Notch` (notch, helper, elevation client, Finder extension). They become SwiftRight service adapters under SR2 (`docs/architecture.md` section 7: WindowService, TrayService, ShortcutService, ClipboardService, DialogService, NotificationService, LaunchService, SecureStore, EngineService), not view blocks. The Windows column cites what the Win32 notch does today; the RightKit column is the answer from `rightkit owns <capability>` run on 14 October 2026 (`rightkit owns --compact` lists the index; capabilities used: `desktop-overlay`, `global-hotkeys`, `desktop-shell`, `os-credential-store`, `settings-persistence`, `desktop-automation`, `file-watching`, `owned-processes`, `http-client`, `local-services`, `safe-filesystem`, `structured-logging`, `crash-reporting`).

<!-- generated:services-table -->
| Mac service | Hits | Files | Examples | Windows notch today | RightKit owner (`rightkit owns`) | SwiftRight adapter (SR2) |
|---|---|---|---|---|---|---|
| Borderless panel windows (NSPanel/NSWindow subclasses, styleMask, collectionBehavior, ignoresMouseEvents) | 48 | 7 | `mac/Notch/Sources/Launcher/ClipboardStripController.swift:14`, `mac/Notch/Sources/Notch/NotchWindowController.swift:480` | One borderless layered window per monitor, WS_EX_NOACTIVATE plus rightkit_overlay OverlayStyle::PASSIVE (windows/src/main.rs:1293), per-pixel alpha through UpdateLayeredWindow (windows/src/surface.rs:1-3); the clipboard strip and launcher use the same pattern (windows/src/clip_strip.rs:3323, windows/src/launcher.rs:2910). | desktop-overlay: rightkit-overlay 0.1.1 (staged-unverified); Swift RightKitOverlay is in use by the Mac notch (5 imports) but the notch panel itself is 'not portable yet' (pulse/STATUS.md, 'Not swapped') | WindowService: overlay panel (non-activating, per-display, click-through regions) |
| Window levels above the menu bar (.level, CGShieldingWindowLevel, statusWindow) | 4 | 3 | `mac/Notch/Sources/Launcher/ClipboardStripController.swift:22`, `mac/Notch/Sources/Notch/CornerPassage.swift:437` | rightkit_overlay::windows::reassert_topmost (windows/src/main.rs:1517) and WS_EX_TOPMOST (windows/src/clip_strip.rs:3323). | desktop-overlay: rightkit-overlay 0.1.1 (reassert_topmost, show_noactivate, hide) | WindowService: window level policy for overlay panels |
| SwiftUI hosting inside AppKit (NSHostingView, NSHostingController, NSViewRepresentable, NSApplicationDelegateAdaptor) | 14 | 9 | `mac/Notch/Sources/Features/ProviderRing.swift:287`, `mac/Notch/Sources/App/ViewShots.swift:270` | None needed: the Windows notch is not a hosted view. SwiftRight's SDK-owned entry and renderer replace NSHostingView (docs/architecture.md section 5, 'Application entry'). | none (SwiftRight runtime) | Not a service: runtime and renderer |
| Screen, notch and safe-area geometry (NSScreen, safeAreaInsets, auxiliaryTopLeftArea, visibleFrame, backingScaleFactor) | 55 | 12 | `mac/Notch/Sources/Notch/NotchWindowController.swift:59`, `mac/Notch/Sources/Notch/NotchFleet.swift:204` | EnumDisplayMonitors (windows/src/main.rs:992), per-monitor DPI awareness (windows/src/main.rs:856; GetDpiForMonitor at windows/src/clip_strip.rs:1468), WM_DISPLAYCHANGE and work-area changes (windows/src/main.rs:773, :3869). Windows has no hardware-notch geometry; the Mac's safeAreaInsets / auxiliary areas (NotchGeometry) have no counterpart. | desktop-overlay: monitor_at and foreground_fills_monitor are listed as the owner's functions (pulse/STATUS-WINDOWS.md, 'Layered windows'); no owner for the display's own notch | WindowService: display list, work area, scale, change notifications |
| Hover and pointer tracking (NSTrackingArea, NSEvent monitors, mouseLocation, mouse moved/dragged) | 21 | 5 | `mac/Notch/Sources/Launcher/ClipboardStripController.swift:31`, `mac/Notch/Sources/Notch/NotchWindowController.swift:544` | TrackMouseEvent / WM_MOUSELEAVE (windows/src/main.rs:2810, :2861) plus cursor polling (windows/src/main.rs:2986, :3068); the wheel's pointer hook runs on its own thread (windows/src/wheel.rs:2063). | desktop-overlay: hit-region rule is RightKit's on the Mac (RightKitOverlayHitRegions, NotchWindowController.swift:1510); no hover-tracking owner | WindowService: pointer enter/leave, hit regions, global pointer position |
| Full-screen and foreground-app detection (CGWindowListCopyWindowInfo, frontmostApplication, presentationOptions) | 22 | 14 | `mac/Notch/Sources/Conveniences/SnippetExpansion.swift:102`, `mac/Notch/Sources/Conveniences/AutoQuit.swift:51` | Topmost visible, non-owned window covering the whole monitor with no caption or frame, ignoring cloaked windows (windows/src/visibility.rs:1-6; DwmGetWindowAttribute at windows/src/main.rs:1486). | desktop-overlay: foreground_fills_monitor (pulse/STATUS-WINDOWS.md); machine matrix still pending (pulse/docs/feasibility.md 'Fullscreen hide') | WindowService: foreground-occupancy signal |
| Menus and status items (NSStatusItem, NSMenu, right-click menu) | 13 | 6 | `mac/Notch/FinderExtension/FinderSync.swift:47`, `mac/Notch/Sources/Notch/NotchPanel.swift:11` | The notch has no tray or taskbar item (windows/README.md); right-click opens one 'Quit' card drawn by the notch itself (windows/src/main.rs:3674). | desktop-shell: rightkit-shell 0.1.4 / 0.2.0 (tray) is not needed for the notch; it is Tauri-specific (docs/architecture.md section 7) | TrayService: not needed by the notch (card drawn by the SDK) |
| Global hotkeys (Carbon RegisterEventHotKey) | 25 | 9 | `mac/Notch/Sources/Launcher/LauncherHotKey.swift:1`, `mac/Notch/Sources/Conveniences/Windows/SettingsHotKey.swift:1` | rightkit-hotkeys GlobalHotkeys for window chords, the launcher key, the clipboard strip key and Ctrl+V on the Send cell (windows/src/window_keys.rs:1-12, windows/src/launcher.rs:34, windows/src/clip_strip.rs:42, windows/src/send_sys.rs:1-5). | global-hotkeys: rightkit-hotkeys 0.1.0 (staged-unverified; Pulse takes a snapshot copy, pulse/windows/Cargo.toml); Swift RightKitHotkeys 'designed' (pulse/STATUS.md) | ShortcutService: register, conflict report, repeat, release |
| Keyboard and mouse event taps (CGEventTap, cghidEventTap) | 15 | 9 | `mac/Notch/Sources/Conveniences/EventTapHub.swift:24`, `mac/Notch/Sources/Conveniences/ToolWheel.swift:28` | One WH_KEYBOARD_LL hook on a dedicated thread (windows/src/keys.rs:3, :230) and a WH_MOUSE_LL hook for the wheel (windows/src/wheel.rs:2017, :2063). | global-hotkeys: HookHotkeys primitives for chords Windows refuses (pulse/STATUS-WINDOWS.md, ledger row 159); Swift side 'designed' | ShortcutService: low-level input hooks (Mac extension: CGEventTap) |
| Synthesised input and pasteboard paste (CGEvent post, keyDown events) | 19 | 6 | `mac/Notch/Sources/Launcher/ClipboardPaster.swift:47`, `mac/Notch/Sources/Keyboard/FnCommand.swift:38` | SendInput for paste keystrokes (windows/src/clip_paste.rs:369, :392). | desktop-automation: rightkit-automation 0.1.0 (staged-unverified) has an input ladder; Pulse does not use it | ShortcutService / ClipboardService: paste-back keystroke |
| Accessibility API automation (AXUIElement, AXObserver, AXIsProcessTrusted) | 87 | 15 | `mac/Notch/Sources/Conveniences/AXSupport.swift:8`, `mac/Notch/Sources/Conveniences/AutoQuit.swift:21` | UI Automation only for link detection under a middle click (windows/src/wheel.rs:1893-1927); window moves use SetWindowPos on the foreground window (windows/src/window_keys.rs:459-466). Auto Quit has no Windows version (docs/comparison/behaviour.md row 43). | desktop-automation: rightkit-automation 0.1.0 (staged-unverified, AX and UIA); Swift RightKitAccessibility 'designed' (pulse/STATUS.md) | Mac extension module plus an automation adapter; not a view block |
| CPU, memory and disk metrics (host_statistics, sysctl, vm_statistics, statfs, volume resource keys) | 51 | 22 | `mac/Notch/Sources/System/SystemProviders.swift:81`, `mac/Notch/Sources/App/ViewShots.swift:148` | GetSystemTimes deltas, GlobalMemoryStatusEx, PDH counters and GetDiskFreeSpaceExW (windows/src/sensors.rs:2, :32, :36, :237); 2 s visible and 10 s hidden cadence (windows/src/lifecycle.rs:5-6). | none: `rightkit owns --compact` lists no system-metrics owner; pulse/STATUS-WINDOWS.md 'Ruled local' keeps sensors in Pulse | SensorService (new; not in architecture section 7) |
| IOKit sensors (IOAccelerator GPU utilisation, IOHIDEventSystemClient temperature) | 22 | 3 | `mac/Notch/Sources/System/SystemSensors.swift:2`, `mac/Notch/Sources/System/Sensors/BatteryReader.swift:2` | GPU temperature from an NVML helper started only while the System card is open, CPU zones from MSAcpi_ThermalZoneTemperature through a hidden PowerShell (windows/src/sensors.rs:11, :948-959, :992). | none (same as system-metrics) | SensorService: GPU busy and temperatures (Mac extension for IOKit) |
| User notifications and sounds (UNUserNotificationCenter, NSSound) | 13 | 3 | `mac/Notch/Sources/Model/NotificationChannel.swift:3`, `mac/Notch/Sources/Model/ThresholdNotifier.swift:2` | WinRT ToastNotificationManager through a hidden PowerShell under PowerShell's own AUMID (windows/src/notify.rs:5, :19, :94), stock sounds by PlaySoundW (windows/src/notify.rs:3, :64). | desktop-shell: rightkit-shell 0.1.4 (registry-recorded) / 0.2.0 (staged-unverified) lists notifications; Tauri-specific parts must be separated (docs/architecture.md section 7) | NotificationService: post, sound, permission state |
| Launch at login and privileged daemon (SMAppService) | 16 | 3 | `mac/Notch/Sources/System/PulsePermissions.swift:4`, `mac/Notch/Sources/Settings/Preferences.swift:3` | One HKCU Run value, per user, no elevation (windows/src/autostart.rs:1-9). The Mac's privileged SMAppService.daemon has no Windows counterpart (docs/comparison/behaviour.md rows 50-51). | desktop-shell: rightkit-shell lists autostart | LaunchService: launch at login |
| Open links, files and apps; running-application control (NSWorkspace, NSRunningApplication) | 156 | 38 | `mac/Notch/Sources/Conveniences/DiskImageInstaller.swift:84`, `mac/Notch/Sources/Conveniences/AutoQuit.swift:31` | Hub start and show-section through a child process and a named event (windows/src/hub.rs:1-9, :178); explorer.exe for 'show in folder' (windows/src/send.rs:2198). | owned-processes: rightkit-process 0.3.3 (registry-recorded); pulse/STATUS-WINDOWS.md asks for 0.4.0 | LaunchService: open file, link, app |
| Single-instance and app-to-hub signalling (Darwin notifications, Distributed notifications, CFNotificationCenter) | 10 | 5 | `mac/Notch/Sources/System/HubBridge.swift:700`, `mac/Notch/FinderExtension/FinderSync.swift:100` | Named mutex with newest-wins (windows/src/main.rs:735) and named events `Local\dev.orthic.pulse.hub.show.<section>` and `Local\dev.orthic.pulse.notch.state` (windows/src/hub.rs:1-9, windows/src/bridge.rs:1-9). | desktop-shell: rightkit-shell (single instance); local-services: rightkit-service 0.1.4 (staged-unverified) for the hub channel | LaunchService (single instance) and EngineService (hub channel) |
| Keychain credential reads (SecItem, Keychain) | 6 | 5 | `mac/Notch/Sources/Providers/KeychainPrompt.swift:2`, `mac/Notch/Sources/Conveniences/DiskImageWork.swift:5` | No credential store: the Windows notch reads Claude Code's and Codex's own credential files read-only (windows/src/usage.rs:1-8; docs/comparison/behaviour.md header, usage.rs:989-995). The Mac reads the Keychain through RightKitAppleCredentials (mac/Notch/Sources/Providers/KeychainItem.swift:2). | os-credential-store: rightkit-secrets 0.1.3 (staged-unverified, Credential Manager) and RightKitSwift (rightkit-swift 0.4.0, registry-pinned; pulse/STATUS.md says tag 0.7.0 is in use, a version disagreement to settle) | SecureStore: read-only keychain item; file read on Windows |
| Settings persistence (UserDefaults, @AppStorage, JSON state files) | 31 | 14 | `mac/Notch/Sources/Settings/Preferences.swift:691`, `mac/Notch/Sources/System/PrivilegedHelper.swift:14` | pill-settings.json with an own bounded parser and a restricted-ACL atomic writer (windows/src/settings.rs:1-10; pulse/STATUS-WINDOWS.md 'Blocked on RightKit'). | settings-persistence: rightkit-settings 0.1.1 (staged-unverified); waits on rightkit-fs 0.3.4 (pulse/STATUS-WINDOWS.md) | Settings adapter (rightkit-settings through the swiftright-services C ABI, docs/architecture.md section 7) |
| Clipboard (NSPasteboard, change count, paste) | 62 | 8 | `mac/Notch/Sources/Sharing/NearbySharing.swift:488`, `mac/Notch/Sources/Conveniences/SnippetExpansion.swift:47` | AddClipboardFormatListener worker (windows/src/clip_capture.rs:2, windows/src/clip_win.rs:42) and OpenClipboard reads (windows/src/send_sys.rs:51, :224). | desktop-shell: @rightkit/shell lists rich clipboard (0.1.0, declaration-only); the clipboard store is a held row until RightKit answers (pulse/STATUS-WINDOWS.md) | ClipboardService: read/write types, change observation, sensitive-content policy |
| Drag and drop (NSDraggingSource, onDrop, onDrag, NSItemProvider) | 20 | 5 | `mac/Notch/Sources/Notch/NotchHostingView.swift:55`, `mac/Notch/Sources/Launcher/ClipboardDrag.swift:63` | WM_DROPFILES and DragQueryFileW (windows/src/send_sys.rs:1-5, windows/src/clip_win.rs:49, :224). | none found in `rightkit owns --compact` | ClipboardService / DialogService: drop target |
| File and directory watching (FSEvents, DispatchSource file system objects) | 14 | 4 | `mac/Notch/Sources/Sessions/CodexActivityMonitor.swift:248`, `mac/Notch/Sources/Conveniences/ClaudeChatMirror.swift:2` | Three ReadDirectoryChangesW watchers on their own threads (windows/src/claude_watch.rs:1-5). | file-watching: rightkit-watch 0.3.2 (staged-unverified); Windows backend 'not started' (pulse/STATUS.md, STATUS-WINDOWS.md); the Mac notch already imports RightKitWatch (2 files) | Watch adapter (new; not in architecture section 7) |
| Child processes and shell commands (Foundation.Process, posix_spawn) | 51 | 15 | `mac/Notch/Sources/Updater/PulseRelauncher.swift:60`, `mac/Notch/Sources/Launcher/LauncherActions.swift:150` | std::process::Command for the hub, drive health and installers (windows/src/hub.rs:178, windows/src/drive_health.rs:182, windows/src/installer.rs:1117). | owned-processes: rightkit-process 0.3.3 (registry-recorded); 0.4.0 requested | EngineService: child process lifecycle |
| Privileged helper over XPC and Apple Events (NSXPCConnection, NSAppleScript, Apple Events) | 7 | 4 | `mac/Notch/Helper/main.swift:135`, `mac/Notch/Sources/System/PrivilegedHelper.swift:10` | No equivalent: Windows apps are removed through their own uninstaller (docs/comparison/behaviour.md row 58, accepted difference). | none | Mac extension module only |
| Local-network discovery and sharing (Network.framework, Bonjour, NWListener, URLSession) | 14 | 5 | `mac/Notch/Sources/Updater/UpdateDownload.swift:13`, `mac/Notch/Sources/Providers/CodexLocalProvider.swift:11` | LocalSend runs in the hub's core on both platforms (windows/src/send.rs:3); the notch makes WinHTTP calls for usage and updates (windows/src/http.rs:25). | http-client: rightkit-http 0.2.5 (staged-unverified); Send engine: rightkit-send 'unpublished' (pulse/STATUS.md); local-services: rightkit-service 0.1.4 | EngineService (nearby-share engine in the hub) plus an HTTP adapter |
| Core Animation layers and display links (CALayer, CAShapeLayer, CADisplayLink, CVDisplayLink) | 37 | 2 | `mac/Notch/Sources/Features/ProviderRing.swift:315`, `mac/Notch/Sources/Notch/NotchWindowController.swift:801` | A software rasteriser stepped by a 16 ms timer only while something moves (windows/src/motion.rs:1-6, windows/src/canvas.rs:3). | none (renderer) | Not a service: SwiftRight renderer, animation and clock (SR1 blocks 18-19) |
| System materials and glass (NSVisualEffectView, glassEffect) | 8 | 5 | `mac/Notch/Sources/Launcher/LauncherView.swift:276`, `mac/Notch/Sources/Features/SettingsHandle.swift:146` | None: the Windows notch is solid; surface style and colour transition are listed as still to add (pulse/docs/settings.md, 'Still to add on Windows'). | none (renderer) | Not a service: renderer foundation (SR1 plan, Foundations) |
| Finder Sync extension and Finder automation | 5 | 1 | `mac/Notch/FinderExtension/FinderSync.swift:2` | None: Explorer has its own Copy as path and Open in Terminal (docs/comparison/behaviour.md row 44). | none | Mac extension module only |
| Disk images, code signing and Gatekeeper (hdiutil, SecStaticCode, spctl, ditto) | 9 | 4 | `mac/Notch/Sources/Conveniences/DiskImageWork.swift:306`, `mac/Notch/Sources/Updater/UpdateVerifier.swift:49` | Installer card for new .msi, .msix and setup .exe downloads (windows/src/installer.rs:5-8); update download checked with WinVerifyTrust (windows/src/update.rs:10). | update-policy: @rightkit/updates 0.2.5 (JS, Tauri); signing and publication are RightKit release tooling | Mac extension module; Windows needs its own installer-check adapter |
| Screenshots (screencapture, CGWindowListCreateImage, ScreenCaptureKit, CGPreflightScreenCaptureAccess) | 2 | 1 | `mac/Notch/Sources/System/PulsePermissions.swift:50` | BitBlt from the screen DC after the overlay is gone, CF_DIB to the clipboard (windows/src/shot.rs:16). | none (desktop-qa and screen-recording owners do not cover product capture) | CaptureService (new; not in architecture section 7) |
| Privacy-permission state probes (TCC, Full Disk Access, local network, Accessibility prompt) | 6 | 3 | `mac/Notch/Sources/System/PulsePermissions.swift:134`, `mac/Notch/Sources/Conveniences/ConveniencesService.swift:244` | None needed: Windows needs no permission grants; the hub shows startup, notifications and firewall (pulse/README.md 'Permissions'; docs/comparison/behaviour.md row 50). | none | Mac extension module only |
| Logging and diagnostics (os.Logger, os_log, NSLog) | 12 | 6 | `mac/Notch/Sources/App/Log.swift:2`, `mac/Notch/Helper/main.swift:2` | diag.rs writes notch.log (windows/README.md 'Diagnostics'); crashes through rightkit-crash 0.2.1 (pulse/STATUS-WINDOWS.md). | structured-logging: rightkit-logs 0.2.1 (staged-unverified; Mac notch imports RightKitDiagnostics, mac/Notch/Sources/App/Log.swift:3); crash-reporting: rightkit-crash 0.2.1 | Diagnostics adapter (docs/architecture.md section 7, 'Diagnostics and native QA') |
<!-- /generated:services-table -->

Modules the notch imports, as a view of what each target depends on (all 184 files):

<!-- generated:imports -->
| Module | Files |
|---|---|
| `import Foundation` | 115 |
| `import AppKit` | 64 |
| `import SwiftUI` | 42 |
| `import Combine` | 17 |
| `import ApplicationServices` | 16 |
| `import Darwin` | 11 |
| `import Carbon.HIToolbox` | 9 |
| `import os` | 6 |
| `import CoreGraphics` | 5 |
| `import RightKitOverlay` | 5 |
| `import Security` | 4 |
| `import ServiceManagement` | 3 |
| `import IOKit` | 3 |
| `import notify` | 2 |
| `import RightKitDiagnostics` | 2 |
| `import RightKitWatch` | 2 |
| `import CryptoKit` | 2 |
| `import UniformTypeIdentifiers` | 2 |
| `import CoreServices` | 2 |
| `import UserNotifications` | 2 |
| `import SQLite3` | 2 |
| `import RightKitAppleCredentials` | 2 |
<!-- /generated:imports -->

Observations that change the plan:

- **RightKit owns the overlay panel, global hotkeys and credentials but not sensors, screen geometry beyond placement, system metrics, screen capture or the nearby-send engine.** `rightkit owns --compact` has no capability for them; `pulse/STATUS.md` says "Send engine: rightkit-send, unpublished". Under `docs/architecture.md` section 7 these are reported against RightKit, not copied. The Windows sensors already live in the notch (`windows/src/sensors.rs`) and are ruled local (`pulse/STATUS-WINDOWS.md`, "Ruled local").
- **Four RightKit packages are staged, not registry-recorded.** `rightkit-overlay` 0.1.1, `rightkit-hotkeys` 0.1.0, `rightkit-settings` 0.1.1 and `rightkit-http` 0.2.5 are "staged-unverified"; Pulse itself builds against snapshot copies marked "RIGHTKIT OVERRIDE" (`pulse/windows/Cargo.toml`). Architecture section 7 says declaration alone is not integration evidence.
- **A version disagreement to settle.** `pulse/STATUS.md` says the Mac notch uses the RightKit Swift package at exact tag 0.7.0 (Mac logging, keychain reads, file events, overlay panels); `rightkit owns os-credential-store` reports `rightkit-swift@0.4.0` as registry-pinned. One of them is stale; SwiftRight should pin whichever the Mac notch actually builds (`mac/Notch/project.yml`).
- **The Mac notch panel is not yet on RightKit's panel.** `pulse/STATUS.md` ("Not swapped") says the notch panel, its pointer tracking and display planning are "not portable yet: the panel class cannot be subclassed and three helpers do not fit"; `NotchWindowController.swift:1507-1510` keeps the toggling local and says `NotchPanel` is not a `RightKitOverlayPanel`.

## 4. Port slice

### Recommendation: S1, the notch face with ring gauges (read-only)

S1 is the smallest set of journeys that is a real notch a user can see and trust on Windows built from the same SwiftUI source: the pill at the chosen edge, the four ring cells and their glyphs drawn from live readings, and a click that opens the hub on the clicked section. It is J01 plus J03, with the click of J09 only; no neck, bulb, cards, toasts, Send, Tools, launcher or clipboard. The Windows notch already ships all of those, so S1's value is one source for the notch surface, not new behaviour; it also exercises the largest block families first, which is what the SR1 plan wants from a first consumer ("Shell screens are written in SwiftUI on Mac first; their Windows compile errors give the block backlog", `docs/sr1-plan.md:223-227`).

Slice order and size (the slices are cumulative; "new" counts APIs not already missing in an earlier slice):

<!-- generated:slice-summary -->
| Slice | Contents | Journeys | SwiftUI files | Lines | APIs used | Missing (all) | Missing, new in this slice | Partly covered | Combine uses to rewrite | AppKit escape uses |
|---|---|---|---|---|---|---|---|---|---|---|
| S1 | Notch face with ring gauges (read-only) | J01, J03 | 15 | 5,086 | 108 | 40 | 40 | 18 | 47 | 3 |
| S2 | Hover cards and toasts | J04, J10 | 6 | 2,179 | 101 | 43 | 19 | 18 | 0 | 0 |
| S3 | Send and Tools | J05, J06 | 3 | 1,030 | 69 | 27 | 9 | 12 | 3 | 1 |
| S4 | Settings handle, move grip and multi-display | J09, J11 | 5 | 2,395 | 74 | 38 | 10 | 7 | 3 | 2 |
| S5 | Launcher and clipboard strip | J07, J08 | 6 | 3,915 | 139 | 57 | 35 | 22 | 28 | 4 |
<!-- /generated:slice-summary -->

<!-- generated:slice-new -->
| Slice | New missing APIs | Names (uses in the slice) |
|---|---|---|
| S1 | 40 | `AnimatablePair` (36), `addLine` (28), `Path` (13), `move` (7), `scaleEffect` (7), `closeSubpath` (6), `allowsHitTesting` (4), `background` (4), `offset` (4), `position` (4), `Group` (3), `applying` (3), `fixedSize` (3), `onHover` (3), `AnyView` (2), `StrokeStyle` (2), `accessibilityHidden` (2), `addArc` (2), `addCurve` (2), `contentTransition` (2), `delay` (2), `ButtonStyleConfiguration`, `Capsule`, `FillStyle`, `GeometryReader`, `Glass`, `ViewModifier`, `accessibilityElement`, `addEllipse`, `bouncy`, `brightness`, `clipShape`, `degrees`, `glassEffect`, `minimumScaleFactor`, `monospacedDigit`, `rotationEffect`, `snappy`, `tint`, `trim` |
| S2 | 19 | `contentShape` (8), `GridItem` (2), `addFilter` (2), `addQuadCurve` (2), `fontWeight` (2), `heavy` (2), `help` (2), `onTapGesture` (2), `Animatable`, `AppStorage`, `Canvas`, `LazyVGrid`, `TimelineView`, `accessibilityValue`, `color`, `drawLayer`, `firstTextBaseline`, `foregroundColor`, `layoutPriority` |
| S3 | 9 | `radians` (4), `GraphicsContext`, `SpatialTapGesture`, `gesture`, `onContinuousHover`, `onEnded`, `shadow`, `tail`, `truncationMode` |
| S4 | 10 | `SpringKeyframe` (2), `interactive`, `keyframeAnimator`, `mask`, `offsetBy`, `scale`, `strokedPath`, `timingCurve`, `translateBy`, `trimmedPath` |
| S5 | 35 | `UnevenRoundedRectangle` (5), `multilineTextAlignment` (5), `clipped` (4), `isButton` (4), `AnyLayout` (3), `LinearGradient` (3), `onDrop` (3), `ScrollViewReader` (2), `TapGesture` (2), `accessibilityAddTraits` (2), `clear` (2), `image` (2), `interpolation` (2), `isSelected` (2), `middle` (2), `modifier` (2), `scrollTo` (2), `simultaneousGesture` (2), `textSelection` (2), `tracking` (2), `DragGesture`, `HStackLayout`, `LazyHStack`, `Namespace`, `VStackLayout`, `accessibilityAction`, `aspectRatio`, `autocorrectionDisabled`, `fill`, `link`, `matchedGeometryEffect`, `onChanged`, `onDrag`, `popover`, `scrollContentBackground` |
<!-- /generated:slice-new -->

### S1 block gaps, ordered by dependency

The 40 missing APIs the S1 files use, by use count:

<!-- generated:slice-gaps-s1 -->
| Missing API used by S1 | Kind | Uses in slice | Files in slice |
|---|---|---|---|
| `AnimatablePair` (struct) | type | 36 | 2 |
| `addLine` (Path) | member-call | 28 | 3 |
| `Path` (struct) | type | 13 | 3 |
| `move` (Path) | member-call | 7 | 3 |
| `scaleEffect` | modifier | 7 | 4 |
| `closeSubpath` (Path) | member-call | 6 | 3 |
| `allowsHitTesting` | modifier | 4 | 1 |
| `background` | modifier | 4 | 2 |
| `offset` | modifier | 4 | 1 |
| `position` | modifier | 4 | 1 |
| `Group` (struct) | type | 3 | 3 |
| `applying` (Path) | member-call | 3 | 1 |
| `fixedSize` | modifier | 3 | 2 |
| `onHover` | modifier | 3 | 2 |
| `AnyView` (struct) | type | 2 | 1 |
| `StrokeStyle` (struct) | type | 2 | 1 |
| `accessibilityHidden` | modifier | 2 | 1 |
| `addArc` (Path) | member-call | 2 | 1 |
| `addCurve` (Path) | member-call | 2 | 2 |
| `contentTransition` | modifier | 2 | 1 |
| `delay` (Animation) | member-call | 2 | 1 |
| `ButtonStyleConfiguration` (struct) | type | 1 | 1 |
| `Capsule` (struct) | type | 1 | 1 |
| `FillStyle` (struct) | type | 1 | 1 |
| `GeometryReader` (struct) | type | 1 | 1 |
| `Glass` (struct) | type | 1 | 1 |
| `ViewModifier` (protocol) | type | 1 | 1 |
| `accessibilityElement` | modifier | 1 | 1 |
| `addEllipse` (Path) | member-call | 1 | 1 |
| `bouncy` (Animation/Spring) | implicit | 1 | 1 |
| `brightness` | modifier | 1 | 1 |
| `clipShape` | modifier | 1 | 1 |
| `degrees` (Angle) | implicit | 1 | 1 |
| `glassEffect` | modifier | 1 | 1 |
| `minimumScaleFactor` | modifier | 1 | 1 |
| `monospacedDigit` | modifier | 1 | 1 |
| `rotationEffect` | modifier | 1 | 1 |
| `snappy` (Animation/Spring) | implicit | 1 | 1 |
| `tint` | modifier | 1 | 1 |
| `trim` (Shape) | member-call | 1 | 1 |
<!-- /generated:slice-gaps-s1 -->

The APIs S1 uses that are not missing but are not fully gated either need cases before the slice can claim parity:

<!-- generated:slice-ungated-s1 -->
| API used by S1 | Kind | Uses in slice | Files in slice | Status | Evidence |
|---|---|---|---|---|---|
| `Environment` | wrapper | 15 | 3 | partly | used in witnesses of color-scheme |
| `Animation.spring` (explicit) | static | 11 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `EnvironmentKey` (protocol) | type | 10 | 7 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `environment` | modifier | 10 | 1 | partly | exercised in witnesses of color-scheme, padding-frame, pixel-ties and 4 more; no block of its own |
| `fill` (Shape/GraphicsContext) | member-call | 8 | 3 | partly | Shape.fill is delivered (shapes.fill-stroke); the Canvas GraphicsContext.fill form is not in any block |
| `semibold` (Font.Weight) | implicit | 6 | 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `Circle` (struct) | type | 4 | 2 | partly | exercised in witnesses of disabled, stack-layout; no block of its own |
| `foregroundStyle` | modifier | 4 | 2 | partly | Text colour is gated (docs/sr1-status.md block 8 text-colour gate, decision 11) and Button label colour (decision A3); other receivers are not measured |
| `Alignment` (struct) | type | 3 | 2 | partly | exercised in witnesses of padding-frame, pixel-ties; no block of its own |
| `black` (Color/Font.Weight) | implicit | 3 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `font` | modifier | 3 | 2 | partly | exercised in witnesses of text-shape-image; no block of its own |
| `white` (Color/ShapeStyle) | implicit | 3 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `EmptyView` (struct) | type | 2 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `VStack` (struct) | type | 2 | 2 | partly | exercised in witnesses of alert, animation, binding and 12 more; no block of its own |
| `accessibilityLabel` | modifier | 2 | 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `lineLimit` | modifier | 2 | 1 | partly | exercised in witnesses of text-shape-image; no block of its own |
| `spring` (Animation) | implicit | 2 | 2 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `stroke` (Shape/GraphicsContext) | member-call | 2 | 1 | partly | Shape.stroke is delivered (shapes.fill-stroke); the Canvas GraphicsContext.stroke form is not in any block |
| `task` | modifier | 2 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `topLeading` (Alignment/UnitPoint) | implicit | 2 | 1 | partly | exercised in witnesses of animation, binding, color-scheme and 3 more; no manifest symbol |
| `HStack` (struct) | type | 1 | 1 | partly | exercised in witnesses of animation, binding, button and 4 more; no block of its own |
| `UnitPoint` (struct) | type | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `combined` (AnyTransition) | member-call | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `continuous` (RoundedCornerStyle) | implicit | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `horizontal` (Alignment/Axis) | implicit | 1 | 1 | partly | exercised in witnesses of padding-frame, pixel-ties, scroll-view; no manifest symbol |
| `isEnabled` | env-key | 1 | 1 | partly | the runtime publishes isEnabled for .disabled (decision 10); reading it through EnvironmentValues is not a manifest symbol |
| `leading` (Alignment/Edge) | implicit | 1 | 1 | partly | exercised in witnesses of alert, animation, binding and 10 more; no manifest symbol |
| `offset` (AnyTransition) | implicit | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `onChange` | modifier | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `regular` (ControlSize/Font.Weight) | implicit | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `resizable` (Image) | member-call | 1 | 1 | partly | exercised in witnesses of text-shape-image |
| `scaledToFit` | modifier | 1 | 1 | partly | exercised in witnesses of text-shape-image; no block of its own |
| `system` (Font) | implicit | 1 | 1 | ungated | implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case |
| `top` (Alignment/Edge) | implicit | 1 | 1 | partly | exercised in witnesses of button, opacity-transition, padding-frame and 1 more; no manifest symbol |
<!-- /generated:slice-ungated-s1 -->

Order the blocks so each one's witnesses can use the previous ones. This is my reading of the dependency, not a measured fact:

1. **Composition, styling and text primitives (F-compose, F-style, F-text).** `Group`, `AnyView`, `GeometryReader`, `ViewModifier`, `fixedSize`, `background`, `clipShape`, `Capsule`, `minimumScaleFactor`, `monospacedDigit`, plus `EmptyView`, `Spacer`, `Font.system` and its weights, which the runtime implements without a gated case and `Circle`, `VStack`, `HStack`, which only witnesses exercise (table above). Every later block's witness uses a background or a group, and `ZStack` plus `overlay` (block 3) already exist. Cheapest, widest.
2. **Vector paths (F-path).** `Path` with `move`, `addLine`, `addArc`, `addQuadCurve`, `addCurve`, `closeSubpath`, `applying`, `StrokeStyle`, `trim`. `SideNotchShape` (8 `Path` uses), the neck in `NotchRootView.swift` (3) and the provider glyph outlines in `ProviderGlyph.swift` (2) are paths, the ring arcs need the same, and `docs/sr1-plan.md:230-233` already lists vector paths as a foundation to add through an ABI revision. This is the first block that needs renderer and bridge work, so it gates the schedule.
3. **Transforms and placement (F-transform).** `scaleEffect`, `rotationEffect`, `offset`, `position`. The plan says transforms are translation only today (`docs/sr1-plan.md:233`). `scaleEffect` has 7 uses in 4 S1 files; `offset` and `position` have 4 uses each in one file.
4. **Animatable data and spring animation (F-animatable).** `Animatable`, `AnimatablePair`, `Animation.spring`, `delay`. `AnimatablePair` has 36 uses in S1: 26 in `SideNotchShape.swift` and 10 in `NotchRootView.swift`, so the notch silhouette and its neck are animatable shapes. Block 18 covers linear, ease and the default spring (`docs/sr1-decisions.md` C3 and C4); custom springs and animatable data are new and need the manual-clock cases from F1.
5. **Pointer and hit testing (F-pointer).** `onHover` (3 uses in S1) and `allowsHitTesting` (4); `contentShape` arrives with S2. Needs the window service to deliver pointer enter, leave and hit regions (section 3, "pointer-tracking" and "panel-window"); the pill opens on pointer contact.
6. **Environment keys (F-compose).** `EnvironmentKey` with `.environment(\.key, value)`; 10 uses across 7 S1 files. Block 20 covers `colorScheme` only (`docs/sr1-status.md` block 20).
7. **Accessibility (F-a11y).** `accessibilityLabel`, `accessibilityHidden`, `accessibilityElement`. Every inventory control needs a UIA mapping (`docs/architecture.md` section 11).
8. **Glass (F-style).** `glassEffect` and `Glass` have no Windows source; the Windows notch is solid (`pulse/docs/settings.md`, "Still to add on Windows: surface style"). Decide to map them to a solid fill as an "Adapted" entry rather than build a material.

### S1 service adapters, ordered by dependency

1. **WindowService, overlay panel.** One non-activating, click-through-where-empty, topmost layered window per monitor with pointer enter and leave, click, drag and right-click delivered at the window (not through SwiftUI), per-monitor DPI and work-area. Windows uses `rightkit_overlay` `OverlayStyle::PASSIVE` plus `UpdateLayeredWindow` today (`windows/src/main.rs:1293`, `windows/src/surface.rs:1-3`). RightKit's `rightkit-overlay` is the owner, staged-unverified. This adapter blocks everything visible, so it comes first with the F-compose block.
2. **EngineService client.** The notch needs usage, CPU, memory and disk readings. The shared Rust core already produces `pulse usage --json` and `pulse monitor --json` (`README.md` "Command line"; `core/src/main.rs:511-523,741-744`), and the Windows notch reads usage itself in `windows/src/usage.rs` and sensors in `windows/src/sensors.rs`, not from the core. The adapter is a child process plus JSON (`rightkit-process`, registry-recorded 0.3.3) rather than Swift ports of the Mac providers. Unverified: whether `pulse monitor --json` or `pulse status --json` carries every figure the System and Disks rings read; check before committing to this route.
3. **LaunchService, open the hub.** Start `pulse-hub.exe --section <name>` or signal the named event the hub waits on (`windows/src/hub.rs:1-9`). The click path needs only this; supervision of the hub stays in the existing notch until S4.
4. **Settings read.** Edge, size, visibility and colours come from `pill-settings.json` (`windows/src/settings.rs:1-10`); S1 reads it through `rightkit-settings` or a thin file reader and does not write.
5. **Deferred to later slices:** fullscreen fold (`windows/src/visibility.rs`), multiple monitors (`windows/src/lifecycle.rs`), notifications, hotkeys, clipboard, file watching, secure store.

### Mac-side carve-out S1 needs (not Windows blocks)

- **Observation rewrite.** S1's files use 47 Combine pieces, 42 of them `@Published` in `NotchViewModel` (`mac/Notch/Sources/Notch/NotchViewModel.swift:5`); the architecture excludes `ObservableObject` (`docs/architecture.md` section 5). This changes the shipping Mac notch; a Mac regression blocks release (SR4).
- **Ring arc as a SwiftUI shape** instead of `GaugeArcLayer` (see section 2).
- **A platform-neutral target.** `NotchRootView.swift` (885 lines) wires the face, the handle and the cards together; S1 needs the face split from them, and `NotchHostingView` and `NotchPanel` stay Mac-only (`mac/Notch/Sources/Notch/NotchHostingView.swift`).

### S1 acceptance (journeys, not only pictures)

Per `docs/sr1-plan.md:223-227` journeys are the acceptance tests: (a) on Windows the pill appears at the saved edge without taking focus; (b) readings update on the existing cadence; (c) pointer contact opens it and leaving closes it; (d) a click on a ring opens the hub on the Mac-matching section; (e) the existing `ring` (26) and `notch` (16) fixtures in `qa/notch-views.json` match the Mac renders under the SR1 pair gates; (f) a UI Automation walk exposes every ring with a label (`docs/architecture.md` section 11). Screen parity alone is not shell acceptance (`docs/sr1-plan.md:226-227`).

## 5. Baseline

Architecture section 11 (`docs/architecture.md:285`) requires, for SR2 and SR4, measuring "same feature and engine in the existing shell on each reference machine before migration" and freezing package size, process-tree memory, CPU wakeups and startup-to-interactive. Non-regression limits: startup p95, steady-state process-tree memory, idle wakeups and shipped bytes each at most 110 percent of the OS baseline; startup from 30 fresh launches with cache state recorded; memory from three 60-second samples; idle wakeups from three 60-second idle samples; screen-only incremental build median at or below baseline over 10 edits per shell. "Missing comparable baseline blocks that performance claim."

The existing shell for this feature is the Win32 software notch, not React/Tauri; the section's wording ("existing React/Tauri shell") has to be read as "existing shell". What to measure, and what Pulse already has:

| Measure (architecture section 11) | What Pulse has today | What is missing |
|---|---|---|
| Idle CPU (a proxy for wakeups) | 0.21 percent of one core over 60 s at build `60a9d0d7`, "one short reading", and 0.56 percent at `803b09d2` while agents were writing (`pulse/PENDING-WINDOWS.md:21`; `pulse/docs/feasibility.md:10`). Budget: at most 0.5 percent average (`pulse/docs/implementation-plan.md:49`). | Three 60 s idle samples at the final build; the same on the ported notch. |
| Steady-state memory | Notch private memory 10.9 MB on the Dell at `6ba0f963` (`pulse/STATUS-WINDOWS.md:16`). Budget: at most 25 MB resident (`pulse/docs/implementation-plan.md:48`). The launcher adds 11 to 19 MB after one opening, cause unknown (`pulse/PENDING-WINDOWS.md:23`). The Mac notch read 1.01 percent CPU and 33 MB in the audit of 12 October (`pulse/docs/resource-audit-astra-2026-10-12.md:3`). | Three 60 s steady samples; process-tree scope (the notch starts the hub with `--background` and restarts it, `windows/src/hub.rs:1-9`, so the notch's tree includes `pulse-hub.exe` and its web view processes). |
| Idle wakeups | None recorded. The audit lists source intervals only, "not measured hardware wakeup" (`pulse/docs/resource-audit-astra-2026-10-12.md:27`). By source: 2 s visible and 10 s hidden sampling (`windows/src/lifecycle.rs:5-6`), a 16 ms timer only while something moves (`windows/src/motion.rs:1-3`), bridge publication on an event or a 2 s timeout (`pulse/docs/resource-audit-astra-2026-10-12.md:109`). | A measured wakeup or context-switch rate per process over three 60 s idle samples. |
| Startup-to-interactive p95 | None recorded. | 30 fresh launches with cache state recorded; define "interactive" as the first frame with live readings. |
| Shipped bytes | None recorded in the files read. CI builds `Pulse-Setup-x64.exe` and a `dev-windows-<sha>` artifact (`pulse/windows/README.md:3`; `pulse/README.md` "Install"). | Installer size and installed payload size for the notch alone, from a green main run. |
| Screen-only incremental build | Not measurable under Pulse's rules: "Compilation and tests run in GitHub Actions. Local work is static" (`pulse/README.md` "Building"). | A Windows host where a local build is allowed, or a decision to use CI timings (section 6). |

Tools that exist: `pulse/scripts/probes/footprint-probe.mjs` samples one named PID read-only and reports private bytes, working set, handle count, CPU time and start time, and reports n, min, median and nearest-rank p95 per metric (`pulse/docs/measurement.md`); it does not report wakeups and "no measurements are recorded here". `windows/src/tick_cost.rs:1-4` writes per-step tick costs to the log when `tick-cost.on` exists. Arithmetic on cited figures, not a measurement: 110 percent of 10.9 MB is about 12.0 MB, so a GPU renderer in the notch process has little room against today's number; the SR4 rule is that a failed non-regression gate keeps the existing shell and goes back to Adrian (`docs/architecture.md`, SR4).

The reference machine in Pulse's notes is the Dell (`pulse/STATUS-WINDOWS.md`, `pulse/PENDING-WINDOWS.md`); SwiftRight's SR0 Windows hosts are recorded in `docs/sr0-snapshot.md`, and I did not check whether they include the Dell. Which Windows machine is "the reference" for this comparison is an open decision.

## 6. Open decisions for Adrian

1. **Replace or sit behind an option.** Architecture section 10 keeps the current app working and adds the new shell "behind a development/release option". Recommendation: a dev-only switch that starts the SwiftRight notch instead of `pulse-windows-prototype`, off by default, so the Win32 notch stays the shipped notch until SR4 passes. Pulse's rule that every behaviour has a switch (`pulse/docs/settings.md`, header) suggests a settings key; Adrian decides the key and whether release builds carry the option at all (RightKit rule: no test or dev code in release builds, behind a flag or otherwise).
2. **Who edits Pulse, and where the shared source lives.** Another session owns Pulse and I did not touch it. S1 needs the notch face extracted into a platform-neutral SwiftPM target that both the Mac notch and the SwiftRight Windows build consume, plus the Observation rewrite and the arc change on the Mac. That edits shipping Mac code. Options: (a) Pulse's Mac session does the carve-out in `mac/Notch`, SwiftRight consumes it as a package; (b) SwiftRight keeps a copy and the two drift. I recommend (a); it needs Adrian to say who does it and to tell the Pulse sessions (the workspace rule is to message the peer session first).
3. **Engine route for readings.** Route readings through the shared Rust core (`pulse usage --json`, `pulse monitor --json`) or port the Mac providers to Swift on Windows. Recommendation: the core, because it already serves the hub and CLI and the notch would stop duplicating usage code. Open question inside it: the Windows sensors are in the notch (`windows/src/sensors.rs`), not the core, and RightKit has no sensors owner; move them into the core, or accept a SensorService adapter owned by Pulse.
4. **Baseline scope and machine.** Notch process only, or its tree including `pulse-hub.exe`; which Windows machine; and how to treat the "screen-only incremental build" criterion when Pulse forbids local builds. Recommendation: measure the notch process alone plus the tree separately, on the Dell, using CI timings for build time and labelling them as CI timings.
5. **The memory gate.** The recorded private memory is 10.9 MB (single reading). If the SwiftRight renderer cannot stay near 110 percent of the measured baseline, section 11 and SR4 say the existing shell stays. Decide now whether the notch is worth porting under that risk, or whether the first consumer should be a screen where the renderer's cost does not count against an always-on process (a hub screen, for example).
6. **First slice.** S1 as above, or S1 plus hover cards (S2), so the first Windows build is not just rings. S2 adds 19 missing APIs (mostly `contentShape` with 8 uses, then `Canvas`, `TimelineView`, `GridItem`, `LazyVGrid`, `addFilter` and `drawLayer`) and pulls in the neck drawing in `NoticeStage.swift`.
7. **Scope of Mac-only journeys.** J15 (session activity), J16 (uninstall helper, Finder extension) and parts of J14 are Mac-only or lacking on Windows. Confirm they stay out of the port; the demand map treats them as Mac extension modules (`docs/architecture.md` section 7, "Mac-specific features stay first-class").
8. **Version pin for RightKit Swift.** `pulse/STATUS.md` says tag 0.7.0; `rightkit owns` says 0.4.0. Not Adrian's call to resolve alone, but SwiftRight needs one answer before the Mac adapters are written.

## Reproduce

```sh
python3 factory/tools/demand-map/demand_map.py \
    --pulse /Volumes/D/claude/pulse \
    --json factory/tools/demand-map/pulse-notch-demand-data.json \
    --doc docs/pulse-notch-demand-map.md
```

The script reads `mac/Notch`, `qa/`, `docs/comparison/README.md` and git metadata from Pulse (read-only), the pinned SDK's `SwiftUI` and `SwiftUICore` interfaces through `xcrun --show-sdk-path`, `factory/registry/manifest.json`, the `Witness.swift` sources under `factory/pipeline`, and the runtime sources under `probes/sr0-s/fresh-runtime`. It rewrites the generated blocks of this file and the JSON. Hand-authored inputs: `journeys.json` (journeys, shared groups, slices), `services.json` (service patterns and the Windows, RightKit and adapter columns), `coverage-notes.json` (block limits, families, excluded names, partial overrides). The tables in this file and the narrative numbers were produced from one run; rerun after any change to Pulse and re-read the narrative.

## Delivered APIs (22 Oct 2026, #82 and #84)

S2: LazyVGrid/GridItem (lazy-vgrid-v1), contentShape, help, AppStorage, TimelineView, Canvas/GraphicsContext (canvas-v1), shadow (shadow-v1), truncationMode head/middle (truncation-mode-v1). S3 to S5: LazyHStack, HStackLayout/VStackLayout/ZStackLayout, AnyLayout, ScrollViewReader/scrollTo, TapGesture/SpatialTapGesture/DragGesture with gesture/simultaneousGesture/highPriorityGesture (gesture-drag-tap-v1, pixel-exact against SwiftUI), onContinuousHover, UnevenRoundedRectangle (uneven-rect-v1), timingCurve, accessibilityAction, mask (shape masks), popover, keyframeAnimator with Linear/Move/Cubic/Spring keyframes (values equal SwiftUI's KeyframeTimeline to 0.1), Path.strokedPath, Spring, UnitCurve, onDrag/onDrop (compile surface and host entry points), and accepted with no effect: textSelection, autocorrectionDisabled, scrollContentBackground, matchedGeometryEffect/Namespace.

Known differences, each stated in its source header: popover is an overlay without an arrow or outside-click dismissal (NSPopover is not capturable, so it has no Mac pair); onDrag starts nothing and onDrop runs only when a host delivers a drop; mask applies only a Shape; AnyLayout switches rebuild the container (child state resets); shadow traces shapes, Color, Gradient and Image frames, not Text; matchedGeometryEffect does not morph. Counts above (124 missing on 20 Oct) have not been recounted.

### Probe refresh, 22 Oct 2026 (after #82 and #84)

`probes/sr1-pulse-probe` (ProviderRing.swift and TooltipCard.swift, read-only copies) rebuilt against the current runtime: no error names a SwiftUI API the runtime lacks. What remains is (1) `@Environment(\.viewShotStill)`, `\.codenotchReduceTransparency`, `\.usageWatchLimit`, `\.colorTransitionStyle`, `\.tooltipSecondaryInk`: custom EnvironmentValues keys defined elsewhere in Pulse that the probe stubs do not declare (a probe artefact, not a runtime gap); (2) the AppKit/CoreAnimation island in ProviderRing (`NSViewRepresentable`, `NSView`, `CAShapeLayer`, `CASpringAnimation`, `NSColor`), which is exactly the Mac carve-out of #56. Log: probes/sr1-pulse-probe/out/iter9.txt (gitignored).
