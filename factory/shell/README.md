# F12 shell journeys

Inventory is a source-bound demand baseline for Tauri/React shell journeys described by RightKit UI package contracts and discovered ViewRight/SliceApp consumer sources. It records triggers, user actions, observable outcomes, service dependencies, pilot block IDs and demands that still need registry mapping. This is source inventory only; it does not assert shell acceptance or prove service integration. Tauri adapters and SR2–SR4 service, reliability and performance gates remain open.

Existing package IDs remain alongside concrete ViewRight rows: `vr-entry-window`, `vr-format-routes`, `vr-launch-open`, `vr-session-restore`, `vr-settings-shell`, `vr-native-menu`, `vr-single-instance-window`, `vr-native-drop`, `vr-web-deeplink`, `vr-file-authority`, `vr-watch-conflict` and `vr-updates-license`. Existing `slice-editor` remains the sole SliceApp row; its boundary is SwiftUI/SwiftRight with no Tauri/React route. `inventory.json` records `/Volumes/D/claude/viewright`, `/Volumes/D/claude/rightkit` and `/Volumes/D/claude/swiftright` as source roots.

`inventory.json` holds journey/evidence records; `demand.json` holds pilot block IDs and flattened journey demands. Source receipts include absolute paths, whole-file SHA-256, line number and exact line text.

From repository root, run:

```sh
python -m factory.shell
```

Command rescans source files and verifies hashes, anchor lines and map consistency. A missing or changed source, moved anchor, unknown pilot ID or stale demand map returns nonzero. Refresh source receipts only as part of an intentional inventory review.
