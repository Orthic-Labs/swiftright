# F12 shell journey correction proposal

Scope: source inventory only. Scanned concrete ViewRight Tauri 2 + React 19 sources, RightKit desktop template, & `examples/SliceApp`. No GUI, install, acceptance, or service claim.

## Boundary finding

`examples/SliceApp` has one SwiftUI/SwiftRight root window with `EditorScreen`; no Tauri, React, URL router, settings route, update route, or deep-link route exists there. Existing F12 `slice-editor` journey is correctly bounded to SwiftUI/SwiftRight. Tauri/React route evidence belongs to ViewRight (`/Volumes/D/claude/viewright`) & RightKit template (`/Volumes/D/claude/rightkit/desktop-app-template`).

## Correction set

| ID | Status against current F12 | Actual source journey | Exact anchors |
|---|---|---|---|
| `vr-entry-window` | Omitted | Hidden Tauri window reveals after first React commit; legal gate path fixes 960×560 non-resizable state; accepted path restores normal controls & maximize. Print-preview query mounts separate window. | `viewright/src/main.tsx:33-45`; `viewright/src/app/useReadyShow.ts:88-100`; `viewright/src/app/AppRoot.tsx:79-99,117-171`; `viewright/src/app/PrintPreviewWindow.tsx:7-9,20-43` |
| `vr-format-routes` | Omitted / F12 media/PDF rows too generic | `DocumentRouter` dispatches `web`, `pdf`, `docx`, `image`, `txt`, `html`, `mdx`, & `md`; each route owns viewer/editor, save, find, view, & error boundary. | `viewright/src/documents/DocumentRouter.tsx:242-435` |
| `vr-launch-open` | Omitted | Startup registers `open-file` & native-drop listeners before `initial_open_paths`; argv/Finder/second-instance paths are brokered, opened, ordered, & activated. | `viewright/src/app/useDocumentRuntimeEffects.ts:142-188,273-321`; `viewright/src-tauri/src/commands/dialogs.rs:69-113`; `viewright/src-tauri/src/app_lifecycle.rs:37-60,82-87` |
| `vr-session-restore` | F12 persistence row too broad | Untitled drafts persist in localStorage; file tabs persist in SQLite; launch restores saved active/background tabs, missing files toast, setup recovery restores dirty snapshot. | `viewright/src/app/useDocumentRuntimeEffects.ts:106-140,299-415`; `viewright/src-tauri/src/commands/library.rs:217-265` |
| `vr-settings-shell` | F12 settings row generic | Settings modal has focus trap, section navigation, platform-gated file associations, theme/editor/privacy sections; provider hydrates localStorage then SQLite mirror & debounced writes. | `viewright/src/settings/SettingsPanel.tsx:35-57,60-110`; `viewright/src/settings/settings.tsx:352-419`; `viewright/src/app/App.tsx:741-746` |
| `vr-native-menu` | F12 native menu row generic | macOS native menu creates settings, file/edit/find/view/format/insert/window commands; `vr-key`, `vr-event`, & `vr-cmd` bridge into web shortcuts; quit enters dirty-save gate. | `viewright/src-tauri/src/lib.rs:373-500,514-540`; `viewright/src/app/App.tsx:741-746` |
| `vr-single-instance-window` | Omitted | Second launch focuses/unminimizes main window, handles `--prepare-setup`, & routes argv paths; macOS `Opened` & `Reopen` restore/focus main window. | `viewright/src-tauri/src/app_lifecycle.rs:37-87`; `viewright/src-tauri/src/lib.rs:674-692` |
| `vr-native-drop` | Omitted | Tauri `DragDrop` brokers paths + scale-adjusted position; React claims image drops with timeout, then opens unclaimed paths in source order. | `viewright/src-tauri/src/lib.rs:541-576,701-770`; `viewright/src/app/dropCoordination.ts:121-157` |
| `vr-web-deeplink` | Omitted | HTTP(S) new-window/context actions become ViewRight web tabs; explicit browser escape uses opener; app event routes URL foreground/background tabs & recents. | `viewright/src-tauri/src/context_menu.rs:98-140,246-275`; `viewright/src/app/AppLifecycle.ts:69-97`; `viewright/src-tauri/src/external_navigation.rs:19-34` |
| `vr-file-authority` | Omitted | Native open/save dialogs, recent tokens, linked local paths, relative HTML/MDX grants, revocation, & stream tokens form purpose-scoped path journeys. | `viewright/src-tauri/src/commands/dialogs.rs:117-218`; `viewright/src/state/tauriBridge.ts:179-263` |
| `vr-watch-conflict` | Omitted | One watcher covers open files + HTML subpages; `file-changed` reloads clean docs or raises dirty conflict flow while preserving edits. | `viewright/src/app/AppLifecycle.ts:37-67`; `viewright/src/app/useDocumentWatcher.ts:404-466` |
| `vr-updates-license` | F12 update row incomplete | Settings checks signed updater, maps current/available/license-required/failure states, installs & relaunches, retries failed install, or opens signed public installer; auto-check emits toast. | `viewright/src/settings/sections/UpdatesSection.tsx:43-89,174-258`; `viewright/src/state/updateLicense.ts:507-657`; `viewright/src/app/AppLifecycle.ts:46-67` |
| `vr-slice-boundary` | Existing F12 `slice-editor` retained | SliceApp has one `Window("SliceApp", id: "main")` root; editor supports insert/edit/move/delete & model persistence. This is SwiftUI/SwiftRight, not Tauri/React. | `examples/SliceApp/Sources/SliceApp/Entry/SliceAppEntry.swift:5-20`; `.../EditorScreen.swift:18-40,43-59`; `.../EditorModel.swift:66-125` |

## Intentional future / package-only rows

Keep RightKit package journeys as demand contracts where no concrete ViewRight consumer exists: generic onboarding/model-permission flow, generic media audio/video playback, generic app-shell navigation/shortcut registry, generic settings backend revisions, generic legal receipt port, & generic dialog/provider contracts. They should remain marked package-only until consumer source appears. RightKit desktop template currently has one `home` destination with no router (`desktop-app-template/src/App.tsx:7-24`).

## Recommended inventory edits

1. Add concrete ViewRight IDs above to next F12 inventory, preserving existing package IDs & `slice-editor`.
2. Split `settings`, `updates`, `native menu/deep links`, `persistence`, & `error recovery` into concrete source rows so outcomes name actual Tauri events/commands.
3. Add explicit boundary note: no Tauri/React SliceApp route exists; SliceApp source is SwiftUI/SwiftRight.
4. Retain source-only status; no runtime or acceptance field should be inferred from this proposal.

Evidence receipts & machine-readable comparison live in [`inventory-correction.json`](inventory-correction.json).
