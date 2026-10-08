# SR0-O first probe: macOS AX observation routes

Host: macOS 27.0.1 (26A434), arm64, Xcode 27 RC (Swift 6.4, swiftlang-6.4.0.34.1). Swift 6 language mode, SwiftPM tools 6.2, platform macOS 15 floor for the probe.
Scope: `probes/sr0-o/ax-routes/` only. No commits, no branches, no TCC or system-setting changes.

## Commands

```
cd probes/sr0-o/ax-routes
swift build                       # build 1: actor isolation error in AXRecorder top-level code, fixed with @MainActor on helper funcs
swift build                       # build 2: clean
./.build/debug/FixtureApp &       # launch fixture (stdout to out/fixture-stdout.log)
./.build/debug/AXRecorder         # run 1 (see incident below)
./.build/debug/FixtureApp &       # relaunch for clean run 2
./.build/debug/AXRecorder > out/run2.log
pkill -f debug/FixtureApp
```

Fix iterations: 2 build-level (actor isolation; typing guard after run 1). Within the limit of 4.

## Incident: stray keystrokes in run 1

Run 1 posted "abc" and "d" through `CGEvent.post(tap: .cghidEventTap)` without first confirming FixtureApp was frontmost. The frontmost app was the Claude desktop app (`osascript` check afterwards: "Claude"). Those keystrokes went to whatever field had focus in that app. I cannot confirm where they landed. Check the Claude app for stray "abcd" text. Run 2 added a guard: HID keystrokes only if FixtureApp is frontmost, otherwise `CGEvent.postToPid(fixture pid)`.

## Run 2 output (trimmed, verbatim where quoted)

```
AXIsProcessTrusted=true
fixture pid=61751
row field identifiers found=10 toolbar/insert found=true
row5 identifier=row/5A5A5A5A-0000-4000-8000-000000000005/field
set AXFocused on row5 err=0
set AXSelectedTextRange to end err=0
typing abc route=skipped_not_frontmost(front=698) used=pid
AXPress toolbar/insert err=0
typing d route=pid
SUMMARY
tree walk: WORKS nodes-from-root-flatten=188
identifiers present: WORKS row fields=10 toolbar/insert=true
AXPress toolbar/insert: WORKS err=0 rows after=11
focus set (AXFocused on row5): WORKS focusedIsRow5=true
AXSelectedTextRange readable: WORKS ["length": 0, "location": 5]
AXBoundsForRange readable: WORKS ["x": 403.1083984375, "h": 16.0, "y": 285.0, "w": 0.0]
CGEvent typing reaches field: WORKS row5Value after abc=Row 5abc
row5 identity keeps focus after insert: WORKS focusIsRow5=true value=Row 5abc
typing 'd' after insert lands on row5: WORKS value=Row 5abcd focusIsRow5=true
```

In-process instrumentation (`$TMPDIR/sr0-fixture-events.jsonl`, copied to `out/fixture-events-run2.jsonl`), filtered to text and insert events:

```
{"ev":"text","row":"...000005","text":"Row 5a"}
{"ev":"text","row":"...000005","text":"Row 5ab"}
{"ev":"text","row":"...000005","text":"Row 5abc"}
{"ev":"insert","index":0,"row":"8739D4C7-..."}
{"ev":"text","row":"...000005","text":"Row 5abcd"}
```

Appear events: 11 (10 initial rows plus the inserted row). Disappear events: none, since no row was removed.

## Route table

| Route | Works? | Evidence |
|---|---|---|
| AX tree walk from app root (AXWindows, AXChildren) | Yes | 188 nodes; `out/ax-tree.json` |
| Identifiers via AXIdentifier | Yes | 10 `row/<uuid>/field` on AXTextField; `toolbar/insert` on AXButton |
| Button label | Yes, via AXDescription | label "Insert above"; AXTitle is empty |
| TextField value | Yes, via AXValue | "Row 1" ... "Row 5abcd" |
| Action names | Yes | AXButton exposes AXPress; AXTextField exposes AXShowMenu, AXConfirm |
| Focus set (AXFocused=true on row 5) | Yes | err=0; focused identifier matches row 5 |
| AXPress on toolbar button | Yes | err=0; row count 10 to 11; focus stays on row 5 identity |
| AXSelectedTextRange read and set | Yes | caret at location 5 after set-to-end |
| AXBoundsForRange (caret range) | Yes, but zero-width | returns a rect at x=403.1, y=285, w=0, h=16 |
| CGEvent typing via HID tap | Not verified | skipped: FixtureApp never frontmost (activation refused) |
| CGEvent typing via postToPid | Yes | "abc" and "d" reached AXValue; instrumentation text events match |
| Row identity keeps focus across unrelated insert above | Yes | focused identifier unchanged; value "Row 5abcd" |

Run 1 showed the same AX results except the typing step; its HID keystrokes went to the wrong app (see incident).

## Findings that change CONTRACT.md §5

1. Canonical role mapping needs more entries than the draft lists. On macOS, SwiftUI `List` is `AXOutline`, rows are `AXRow` with subrole `AXOutlineRow` (list-item), and each row wraps an `AXCell`. Text fields sit under the cell. The normalizer must map AXOutline to list and AXOutlineRow to list-item, and strip AXHostingView, AXScrollArea, AXCell, AXColumn, AXGroup.
2. Button labels come from AXDescription, not AXTitle. The Mac normalizer must read AXDescription for button label.
3. Keyboard stimulus on Mac from an out-of-process driver needs a target-process route. HID keystrokes require the fixture to be frontmost. From this terminal session, the process could not be activated (cooperative activation), so HID typing is unverified. `postToPid` works and should be the default unless the driver can prove frontmost state.
4. AXBoundsForRange on a zero-length caret returns width 0. The F5 "paint = hit-test = AX bounds" check and the caret checks need a non-empty selection range to measure real geometry.
5. The recorder ran under the terminal's Accessibility grant (`AXIsProcessTrusted=true`). I did not check whether the recorder binary itself has its own TCC entry. The contract requires a signed recorder with its own AX permission; that is still open.

## Open items

- HID keystroke route (`cghidEventTap`) needs a frontmost fixture; test with an activation method that succeeds, or with user-granted focus.
- Verify the Claude app for stray "abcd" text from run 1.
- Confirm recorder code signing and per-binary TCC grant before SR0 freeze.
- Mac AX caret routes for SwiftUI TextField: this probe covered one caret position only (end of text). Non-empty ranges are still open.
