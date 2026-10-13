# Blocks 17 (swiftui.alert) and 20 (swiftui.color-scheme), SR1 round 3 lane D

`make-cases.sh` writes every case (`new-case.py`: package/ + mac-source/, Witness byte-identical); `run-n20.sh <stage> [runs] [case...]` runs the pairs.

## Block 20: colour scheme (pixels)

Cases under `swiftui.color-scheme/`: semantic colours in dark, the Toggle in dark (switch and checkbox, on/off, enabled/disabled), `@Environment(\.colorScheme)` read branches, `.preferredColorScheme`.
Mac host: `shared-mac-host` (window appearance and root colour scheme stamped per case: `--appearance aqua|darkAqua|none --scheme light|dark|none`). A dark case's witness draws its own `.background` over the whole 320 x 240 viewport (the hosts only draw white behind it).
Measured numbers (SwiftUI on macOS 27, scale 2.5, `NSHostingView` in a never-shown window): `HostPaint.darkSemantic`, `ToggleDarkData` (`factory/tools/switch-artwork/derive_dark_profile.py`). Dark appearance is identical whether the scheme comes from `.environment(\.colorScheme, .dark)` or from the window appearance. `.preferredColorScheme(.dark)` sets the window appearance on macOS (it reaches `.background` outside its own subtree); the runtime does the same (`Graph.applyWindowSchemeRequest`).

## Block 17: alert and confirmationDialog (semantic only)

SwiftUI presents both through NSAlert on macOS. On Windows the host opens `SWR_MODAL_DIALOG` (TaskDialogIndirect) through `PresentationCoordinator` (SwiftRightHost) and maps the answer back (button -> action + dismiss; closed dialog -> cancel action, or just dismiss).

**Mac reference without a visible window.** Measured: an alert presented from a never-shown, ordered-out or off-screen window DOES present: AppKit orders the host window in and puts a sheet panel on a display (an off-screen host frame does not help, the panel is placed on a display). So the Mac host observes the alert instead: `factory/tools/mac-ax-dump/AlertHooks.swift` replaces `-[NSAlert beginSheetModalForWindow:completionHandler:]` (and the three other presenting entry points, and `-[NSWindow orderWindow:relativeTo:]`, which becomes a no-op for the whole process) for the life of the capture process. SwiftUI's own NSAlert object is recorded (title, informative text, buttons in order with key equivalents and the destructive flag) together with its completion handler; `--press K` calls the handler with `1000 + K` as AppKit does on a click, so SwiftUI runs the action and resets the binding. The host aborts if any window of the process is ever visible on a display. Nothing appears, nothing takes focus, no permission is asked. (Three earlier spike runs of the plain presentation DID put an alert window on the Mac's display for a moment before this hook existed: recorded as a caveat.)

**What gates** (`pair.json` `semanticGate`, comparator `factory/tools/pair_semantic_report.py`): in the `open` phase the Windows UIA tree of the TaskDialog against the Mac alert record (dialog count, title = alert message text, informative text, buttons: count, order, names, enabled, and the Mac default (Return) button holding the dialog's keyboard focus), in the final phase (after the button was pressed on each side) the main window has the same elements (the witness shows `Done` or `Waiting`) and no dialog remains. Pixels of the main window are reported and never gate.

### macOS button rules (measured from the NSAlert SwiftUI builds; `DialogLayout.buttons`)

| actions given (alert unless noted) | NSAlert buttons, first = default | 
| --- | --- |
| none | OK (default) |
| `[Delete(destructive), Cancel(cancel)]` or `[Cancel, Delete]` | Delete, Cancel (no default) |
| `[A, Cancel, B]` | A (default), Cancel, B |
| `[Cancel, A, B]` | Cancel, A, B (no default) |
| `[Cancel, A]` | A (default), Cancel |
| `[Delete(destructive), A]` | Delete, A, Cancel (a Cancel is added) |
| confirmationDialog `[A, B]` | A (default), B, Cancel (added) |
| confirmationDialog `[Never mind(cancel), A]` | A (default), Never mind |

A cancel button has Escape as key equivalent; the first button has Return unless it is a cancel or destructive one. Cancel-role buttons keep their own title.
