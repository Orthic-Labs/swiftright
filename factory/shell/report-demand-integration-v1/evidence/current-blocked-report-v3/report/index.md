# SwiftRight factory report

Local report generated from supplied registry, fixed case manifest, captures & verdicts.

Status counts use registered blocks; case counts use the fixed manifest per block. Synthetic inputs are identified and cannot establish parity.

## Dashboard

**Blocks:** 10 · **Passing:** 0 · **Failing:** 0 · **Blocked:** 10 · **Synthetic:** 0 · **No manifest cases:** 0

| Block | Status | Evidence label | Cases pass / fail / blocked / total | Capabilities | Shell demand | Report |
|---|---|---|---:|---|---|---|
| swiftui.shapes.fill-stroke | blocked | unmarked | 0 / 0 / 7 / 7 | unspecified | none mapped | [blocks/swiftui.shapes.fill-stroke.md](blocks/swiftui.shapes.fill-stroke.md) |
| swiftui.image | blocked | unmarked | 0 / 0 / 8 / 8 | unspecified | media-playback, image-view-edit, pdf-reading, vr-format-routes | [blocks/swiftui.image.md](blocks/swiftui.image.md) |
| swiftui.stack-overlay | blocked | unmarked | 0 / 0 / 8 / 8 | unspecified | media-playback, image-view-edit, dialogs, vr-file-authority | [blocks/swiftui.stack-overlay.md](blocks/swiftui.stack-overlay.md) |
| swiftui.text.bundled-font | blocked | unmarked | 0 / 0 / 11 / 11 | unspecified | navigation, settings, onboarding, media-playback, image-view-edit, pdf-reading, legal-acceptance, shortcuts, tray-menu, dialogs, persistence, updates, recovery, slice-editor, vr-entry-window, vr-format-routes, vr-launch-open, vr-session-restore, vr-settings-shell, vr-native-drop, vr-web-deeplink, vr-file-authority, vr-watch-conflict, vr-updates-license | [blocks/swiftui.text.bundled-font.md](blocks/swiftui.text.bundled-font.md) |
| swiftui.custom-layout | blocked | unmarked | 0 / 0 / 10 / 10 | unspecified | none mapped | [blocks/swiftui.custom-layout.md](blocks/swiftui.custom-layout.md) |
| swiftui.scroll-view | blocked | unmarked | 0 / 0 / 6 / 6 | unspecified | navigation, settings, onboarding, image-view-edit, pdf-reading, legal-acceptance, shortcuts, updates, slice-editor, vr-entry-window, vr-format-routes, vr-launch-open, vr-settings-shell, vr-updates-license | [blocks/swiftui.scroll-view.md](blocks/swiftui.scroll-view.md) |
| swiftui.toggle | blocked | unmarked | 0 / 0 / 6 / 6 | unspecified | settings, onboarding, legal-acceptance, persistence, vr-entry-window, vr-settings-shell | [blocks/swiftui.toggle.md](blocks/swiftui.toggle.md) |
| swiftui.disabled | blocked | unmarked | 0 / 0 / 6 / 6 | unspecified | settings, onboarding, media-playback, pdf-reading, legal-acceptance, dialogs, updates, recovery, vr-entry-window, vr-format-routes, vr-settings-shell, vr-file-authority, vr-watch-conflict, vr-updates-license | [blocks/swiftui.disabled.md](blocks/swiftui.disabled.md) |
| swiftui.padding-frame | blocked | unmarked | 0 / 0 / 11 / 11 | unspecified | navigation, settings, onboarding, media-playback, image-view-edit, pdf-reading, legal-acceptance, shortcuts, dialogs, persistence, updates, recovery, slice-editor, vr-entry-window, vr-format-routes, vr-launch-open, vr-session-restore, vr-settings-shell, vr-native-drop, vr-web-deeplink, vr-file-authority, vr-watch-conflict, vr-updates-license | [blocks/swiftui.padding-frame.md](blocks/swiftui.padding-frame.md) |
| swiftui.preference-key | blocked | unmarked | 0 / 0 / 8 / 8 | unspecified | none mapped | [blocks/swiftui.preference-key.md](blocks/swiftui.preference-key.md) |

## Capability status

| Capability | Passing blocks | Failing blocks | Blocked or synthetic blocks |
|---|---:|---:|---:|
| No capability mapping supplied | 0 | 0 | 0 |

## Shell demand

| Journey | Blocks in registry | Passing blocks | Held/failed/synthetic blocks |
|---|---:|---:|---:|
| navigation | 3 | 0 | 3 |
| settings | 5 | 0 | 5 |
| onboarding | 5 | 0 | 5 |
| media-playback | 5 | 0 | 5 |
| image-view-edit | 5 | 0 | 5 |
| pdf-reading | 5 | 0 | 5 |
| legal-acceptance | 5 | 0 | 5 |
| shortcuts | 3 | 0 | 3 |
| tray-menu | 1 | 0 | 1 |
| dialogs | 4 | 0 | 4 |
| persistence | 3 | 0 | 3 |
| updates | 4 | 0 | 4 |
| recovery | 3 | 0 | 3 |
| slice-editor | 3 | 0 | 3 |
| vr-entry-window | 5 | 0 | 5 |
| vr-format-routes | 5 | 0 | 5 |
| vr-launch-open | 3 | 0 | 3 |
| vr-session-restore | 2 | 0 | 2 |
| vr-settings-shell | 5 | 0 | 5 |
| vr-native-menu | 0 | 0 | 0 |
| vr-single-instance-window | 0 | 0 | 0 |
| vr-native-drop | 2 | 0 | 2 |
| vr-web-deeplink | 2 | 0 | 2 |
| vr-file-authority | 4 | 0 | 4 |
| vr-watch-conflict | 3 | 0 | 3 |
| vr-updates-license | 4 | 0 | 4 |

## Unmapped extended demands (107)

Statuses: 61 unmapped; 46 source-inventory-only. Registry mapping remains null.

| Demand | Status | Registry block |
|---|---|---|
| Binding(get:set:) | unmapped | unmapped |
| Button actions | unmapped | unmapped |
| HTML media element and codec recovery | unmapped | unmapped |
| List/ForEach/onMove | unmapped | unmapped |
| PDF.js worker/render pipeline | unmapped | unmapped |
| TextField/FocusState | unmapped | unmapped |
| TextField/control variety | unmapped | unmapped |
| animation and dismiss interactions | unmapped | unmapped |
| async loading and external-change reconciliation | unmapped | unmapped |
| canvas/image transform | unmapped | unmapped |
| command palette modal and focus trap | unmapped | unmapped |
| crash-safe atomic write | unmapped | unmapped |
| crop/text editing controls | unmapped | unmapped |
| custom pointer gestures | unmapped | unmapped |
| deep-link parsing/routing | unmapped | unmapped |
| diagnostics and logs | unmapped | unmapped |
| document scroll/acknowledgement gating | unmapped | unmapped |
| document/file adapter | unmapped | unmapped |
| document/session restoration | unmapped | unmapped |
| download progress/cancel/retry | unmapped | unmapped |
| download/install progress | unmapped | unmapped |
| duplicate/window targeting policy | unmapped | unmapped |
| durable state + service sequencing | unmapped | unmapped |
| error classification | unmapped | unmapped |
| external-link policy | unmapped | unmapped |
| find input and IME | unmapped | unmapped |
| focus/IME behavior | unmapped | unmapped |
| fullscreen host API | unmapped | unmapped |
| key event routing | unmapped | unmapped |
| keyboard focus and navigation | unmapped | unmapped |
| keyboard focus/roving selection | unmapped | unmapped |
| keyboard transport shortcuts | unmapped | unmapped |
| large resource lifecycle | unmapped | unmapped |
| legal modal/eligibility controls | unmapped | unmapped |
| media conversion service | unmapped | unmapped |
| modal stacking/focus restoration | unmapped | unmapped |
| native menu/tray lifecycle | unmapped | unmapped |
| native open/save/print dialogs | unmapped | unmapped |
| navigation transitions | unmapped | unmapped |
| ordered multi-step flow | unmapped | unmapped |
| permission prompts | unmapped | unmapped |
| persistence | unmapped | unmapped |
| platform installer and rollback | unmapped | unmapped |
| quit/close action | unmapped | unmapped |
| radio/checkbox controls | unmapped | unmapped |
| rebinding capture/conflict UX | unmapped | unmapped |
| receipt persistence/hash | unmapped | unmapped |
| restart/recovery strategy | unmapped | unmapped |
| schema migration | unmapped | unmapped |
| sequence timeout | unmapped | unmapped |
| settings storage/revision service | unmapped | unmapped |
| sidebar panels | unmapped | unmapped |
| sidebar selection state | unmapped | unmapped |
| startup/window recovery | unmapped | unmapped |
| storage adapters and cross-process consistency | unmapped | unmapped |
| text entry/IME | unmapped | unmapped |
| time/progress animation | unmapped | unmapped |
| update service/auth | unmapped | unmapped |
| validation/errors | unmapped | unmapped |
| version policy | unmapped | unmapped |
| view-state persistence | unmapped | unmapped |
| Tauri hidden-window reveal timing | source_inventory_only | unmapped |
| legal-gate window state transitions | source_inventory_only | unmapped |
| print-preview window isolation | source_inventory_only | unmapped |
| native window readiness | source_inventory_only | unmapped |
| format discriminator routing | source_inventory_only | unmapped |
| viewer/editor adapter coverage | source_inventory_only | unmapped |
| document save/find/view/error boundaries | source_inventory_only | unmapped |
| Tauri file and document service integration | source_inventory_only | unmapped |
| open-file event ordering | source_inventory_only | unmapped |
| argv/Finder/second-instance path broker | source_inventory_only | unmapped |
| initial_open_paths handoff | source_inventory_only | unmapped |
| active tab selection | source_inventory_only | unmapped |
| SQLite tab-session restoration | source_inventory_only | unmapped |
| untitled localStorage restoration | source_inventory_only | unmapped |
| missing-file recovery and dirty snapshot recovery | source_inventory_only | unmapped |
| cross-process session writes | source_inventory_only | unmapped |
| platform file-association controls | source_inventory_only | unmapped |
| focus-trap/section navigation | source_inventory_only | unmapped |
| localStorage-to-SQLite hydration | source_inventory_only | unmapped |
| debounced native settings mirror | source_inventory_only | unmapped |
| macOS menu construction | source_inventory_only | unmapped |
| menu event to keyboard/window bridge | source_inventory_only | unmapped |
| dirty-save quit gate | source_inventory_only | unmapped |
| single-instance focus/unminimize | source_inventory_only | unmapped |
| macOS Opened/Reopen routing | source_inventory_only | unmapped |
| prepare-setup handoff | source_inventory_only | unmapped |
| Tauri drag-drop path broker | source_inventory_only | unmapped |
| scale-adjusted drop coordinates | source_inventory_only | unmapped |
| React claim timeout | source_inventory_only | unmapped |
| source-order fallback opens | source_inventory_only | unmapped |
| target=_blank context routing | source_inventory_only | unmapped |
| explicit browser escape | source_inventory_only | unmapped |
| URL event foreground/background tab routing | source_inventory_only | unmapped |
| URL recent-history update | source_inventory_only | unmapped |
| open/save dialog path authority | source_inventory_only | unmapped |
| recent token lifecycle | source_inventory_only | unmapped |
| relative HTML/MDX grants | source_inventory_only | unmapped |
| linked-document stream tokens | source_inventory_only | unmapped |
| multi-tab file watcher | source_inventory_only | unmapped |
| HTML subpage watch set | source_inventory_only | unmapped |
| dirty external-change conflict | source_inventory_only | unmapped |
| clean-document auto-reload | source_inventory_only | unmapped |
| signed updater state mapping | source_inventory_only | unmapped |
| license eligibility | source_inventory_only | unmapped |
| download/install/relaunch | source_inventory_only | unmapped |
| failed-install retry/public-installer fallback | source_inventory_only | unmapped |

No publishing is performed. HTML escapes all supplied artifact text; filenames use sanitized block IDs.
