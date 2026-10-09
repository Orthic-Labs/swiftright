#if os(macOS)
import Foundation

/// SR1 inventory fixtures G1..G8 (docs/architecture.md section 5, "Initial inventory").
/// Steps record Mac outcomes as `observe` events, which normalize-hash.py includes in the hash.
/// Checks assert only internal consistency: the driver ran every step, and the model reflects its own last write.
/// The recorded outcome is the oracle; a config is qualified only when all 20 runs agree.
@MainActor
func sr1Case(_ fixture: FixtureConfig.Fixture, model: SR1Model) -> SelfTestCase {
    func noUnknownSteps(_ e: Evidence) -> Check {
        e.check("no-unknown-steps", e.find(node: "driver", tag: "unknown-step").isEmpty)
    }
    func activationHeld(_ e: Evidence) -> Check {
        e.check("activation-held", e.find(node: "driver", tag: "activation-failed").isEmpty)
    }

    switch fixture {
    case .G1:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-focus", "id": "g1/toggle", "label": "focus"],
            ["step": "g-snap", "id": "g1/toggle", "label": "before-space"],
            ["step": "g-key", "key": "space", "label": "space"],
            ["step": "g-snap", "id": "g1/toggle", "label": "after-space"],
            ["step": "g-press", "id": "g1/toggle", "label": "ax-press"],
            ["step": "g-snap", "id": "g1/toggle", "label": "after-ax-press"],
            ["step": "g-model", "op": "toggle", "value": true, "label": "binding-write-true"],
            ["step": "g-snap", "id": "g1/toggle", "label": "after-binding-write"],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("nine-actions-observed", e.find(kind: "observe").count == 9,
                        "observe=\(e.find(kind: "observe").count)"),
                e.check("model-holds-last-write", model.toggleOn == true, "toggle=\(model.toggleOn)"),
            ]
        })

    case .G2:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-focus", "id": "g2/editor", "label": "focus"],
            ["step": "g-text", "text": "ab", "label": "type-ab"],
            ["step": "g-key", "key": "return", "label": "return"],
            ["step": "g-text", "text": "cd", "label": "type-cd"],
            ["step": "g-snap", "id": "g2/editor", "label": "after-typing"],
            ["step": "g-range", "id": "g2/editor", "location": 1, "length": 2, "label": "range-1-2"],
            ["step": "g-snap", "id": "g2/editor", "label": "range-set"],
            ["step": "g-key", "key": "a", "flags": ["command"], "label": "cmd-a"],
            ["step": "g-snap", "id": "g2/editor", "label": "select-all"],
            ["step": "g-model", "op": "note", "text": "ext", "label": "model-note"],
            ["step": "g-snap", "id": "g2/editor", "label": "after-model-write"],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("twelve-actions-observed", e.find(kind: "observe").count == 12,
                        "observe=\(e.find(kind: "observe").count)"),
                e.check("model-holds-last-write", model.note == "ext", "note=\(model.note)"),
            ]
        })

    case .G3:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-tables", "label": "tables"],
            ["step": "g-model", "op": "single", "row": 2, "label": "model-single-2"],
            ["step": "g-table", "table": 0, "label": "single-after-model"],
            ["step": "g-select-rows", "table": 0, "rows": [3], "label": "ax-select-single-3"],
            ["step": "g-table", "table": 0, "label": "single-after-ax"],
            ["step": "g-model", "op": "multi", "rows": [0, 2], "label": "model-multi-0-2"],
            ["step": "g-table", "table": 1, "label": "multi-after-model"],
            ["step": "g-select-rows", "table": 1, "rows": [0, 2, 4], "label": "ax-multi-0-2-4"],
            ["step": "g-table", "table": 1, "label": "multi-after-ax-cmd"],
            ["step": "g-select-rows", "table": 1, "rows": [1, 2, 3], "label": "ax-multi-range-1-3"],
            ["step": "g-table", "table": 1, "label": "multi-after-range"],
            ["step": "g-model", "op": "multi", "rows": [], "label": "model-multi-clear"],
            ["step": "g-dump", "label": "final"],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("fourteen-actions-observed", e.find(kind: "observe").count == 14,
                        "observe=\(e.find(kind: "observe").count)"),
                e.check("model-multi-cleared", model.multiSelection.isEmpty, "multi=\(model.multiSelection.count)"),
            ]
        })

    case .G4:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-model", "op": "g4-select", "row": 2, "label": "select-entry-2"],
            ["step": "g-focus", "id": "g4/list", "label": "focus-list"],
            ["step": "g-ax-focus", "table": 0, "label": "ax-focus-table"],
            ["step": "g-tables", "label": "tables"],
            ["step": "g-key", "key": "delete", "label": "delete-key"],
            ["step": "g-dump", "label": "after-delete-key"],
            ["step": "g-model", "op": "g4-delete", "offsets": [0], "label": "model-delete-first"],
            ["step": "g-dump", "label": "after-model-delete"],
            ["step": "g-ax-focus", "table": 0, "label": "ax-focus-table-again"],
            ["step": "g-key", "key": "delete", "label": "delete-key-again"],
            ["step": "g-dump", "label": "final"],
        ], checks: { e in
            // Each removal (onDelete or model command) logs one "delete" state event; the model count must agree.
            let removals = e.find(kind: "state", node: "g4/list", tag: "delete").count
            return [
                noUnknownSteps(e),
                e.check("count-equals-initial-minus-removals", model.g4Items.count == 4 - removals,
                        "count=\(model.g4Items.count) removals=\(removals)"),
            ]
        })

    case .G5:
        // In-process menus are recorded as UNAVAILABLE. AXShowMenu on a SwiftUI context menu or Menu never returned or
        // never produced a popup in this process (see RESULT.md, SR1 G5), so the fixture records the advertised actions
        // of the target and menu elements and does not invoke AXShowMenu, AXPress on items, or Escape.
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-snap", "id": "g5/target", "label": "target-attrs"],
            ["step": "g-snap", "id": "g5/menu", "label": "menu-attrs"],
            ["step": "g-record", "id": "g5/popup", "label": "popup-status",
             "status": "AX-unavailable", "scope": "in-process", "popupVisibility": "not-observed",
             "itemInvocation": "not-performed", "disabledItemPress": "not-performed",
             "reason": "AXShowMenu not invoked: in-process popup open blocked the self-test"],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("four-records-observed", e.find(kind: "observe").count == 4,
                        "observe=\(e.find(kind: "observe").count)"),
            ]
        })

    case .G6:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-press", "id": "g6/open-alert", "label": "open-alert"],
            ["step": "g-sheet", "label": "alert-sheet", "ms": 600],
            ["step": "g-press-title", "title": "Cancel", "role": "AXButton", "label": "press-cancel"],
            ["step": "g-dump", "label": "after-cancel"],
            ["step": "g-press", "id": "g6/open-dialog", "label": "open-dialog"],
            ["step": "g-sheet", "label": "dialog-sheet", "ms": 600],
            ["step": "g-key", "key": "escape", "label": "escape-dialog"],
            ["step": "g-dump", "label": "after-escape-dialog"],
            ["step": "g-press", "id": "g6/open-alert", "label": "open-alert-2"],
            ["step": "g-key", "key": "escape", "label": "escape-alert"],
            ["step": "g-dump", "label": "after-escape-alert"],
            ["step": "g-press", "id": "g6/open-alert", "label": "open-alert-3"],
            ["step": "g-press-title", "title": "Delete", "role": "AXButton", "label": "press-delete"],
            ["step": "g-dump", "label": "after-delete"],
        ], checks: { e in
            // The binding write log for the alert must end on the same value the model holds.
            let alertBindings = e.find(kind: "state", node: "g6/alert", tag: "binding")
            let lastPresented = alertBindings.last.flatMap { e.payload($0)["presented"] as? Bool }
            return [
                noUnknownSteps(e),
                activationHeld(e),
                e.check("alert-binding-logged", !alertBindings.isEmpty, "binding-events=\(alertBindings.count)"),
                e.check("alert-binding-matches-model", lastPresented == model.alertShown,
                        "last-logged=\(lastPresented.map(String.init) ?? "nil") model=\(model.alertShown)"),
            ]
        })

    case .G7:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-key", "key": "s", "flags": ["command"], "label": "cmd-s"],
            ["step": "g-key", "key": "e", "flags": ["command"], "label": "cmd-e"],
            ["step": "g-key", "key": "l", "flags": ["command"], "label": "cmd-l-disabled"],
            ["step": "g-key", "key": "s", "flags": ["command", "shift"], "label": "cmd-shift-s"],
            ["step": "g-wait", "label": "settle-final", "ms": 300],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("five-actions-observed", e.find(kind: "observe").count == 5,
                        "observe=\(e.find(kind: "observe").count)"),
            ]
        })

    case .G8:
        return SelfTestCase(steps: [
            ["step": "g-activate", "label": "activate"],
            ["step": "g-snap", "id": "g8/image", "label": "snap-image"],
            ["step": "g-snap", "id": "g8/label", "label": "snap-label"],
            ["step": "g-snap", "id": "g8/divider", "label": "snap-divider"],
            ["step": "g-snap", "id": "g8/enabled", "label": "snap-enabled"],
            ["step": "g-snap", "id": "g8/disabled", "label": "snap-disabled-unlocked"],
            ["step": "g-model", "op": "locked", "value": true, "label": "lock"],
            ["step": "g-snap", "id": "g8/disabled", "label": "snap-disabled-locked"],
            ["step": "g-press", "id": "g8/disabled", "label": "press-disabled-locked"],
            ["step": "g-model", "op": "locked", "value": false, "label": "unlock"],
            ["step": "g-snap", "id": "g8/disabled", "label": "snap-disabled-unlocked-again"],
            ["step": "g-press", "id": "g8/enabled", "label": "press-enabled"],
        ], checks: { e in
            [
                noUnknownSteps(e),
                e.check("model-holds-last-write", model.controlsLocked == false, "locked=\(model.controlsLocked)"),
                e.check("twelve-actions-observed", e.find(kind: "observe").count == 12,
                        "observe=\(e.find(kind: "observe").count)"),
            ]
        })

    default:
        return SelfTestCase(steps: [], checks: { _ in [] })
    }
}
#endif
