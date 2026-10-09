# SR0-O Windows UIA recorder (`UIARecorder`) and trace compare CLI (`UIACompare`)

Host: Dell XPS 15 (Bogus-Dell), Windows 11 Pro build 26300, x64, Swift 6.4.0 (swift-6.4-RELEASE), interactive session 1. Mac side: macOS 27, Swift 6.4 (compare CLI and unit tests only).
Scope: new directory `probes/sr0-o/uia-recorder/` only; `probes/sr0-o/comparator/` is a path dependency and was not edited. No commits, no branches.
Target: `D:\Claude\sr0b-abi0` BridgeSmoke.exe (bridge ABI v0): static text x3, button "Press me", edit node.

## Design

```
fixture step file (JSON, logical stimuli)
        |
UIARecorder.exe record --pid N --steps f --out trace.json [--sidecar extra.json]
   Recorder.swift   replays ops, then observes after every step
   UIA.swift        Swift wrapper: RawView walk, patterns, handles table
   Input.swift      VK chords/text via SendInput (never KEYEVENTF_UNICODE)
   Model.swift      portable: UIANode, WinNormalizer, step file, trace mirror types, NativeMapping text
   CUIA/shim.c      every COM call (IUIAutomation C interface) behind a flat C API
        |
trace.json  = TraceKit schema "sr0-o.trace/v0"      sidecar.json = bounds, caret rect, op results, raw tree
        |
UIACompare <accepted.json> <candidate.json> [--adapt f] [--json]   -> TraceKit.TraceComparator
```

- **Attach**: by PID; finds the largest visible unowned top-level window (`EnumWindows`), `ElementFromHandle`. The process sets per-monitor-v2 DPI awareness so UIA rectangles are physical pixels (verified: scale 2.5, a 400 logical px edit node reads 1000 px wide).
- **Tree**: RawView walk to `UIANode {AutomationId, ControlType, Name, Value (ValuePattern), className, patterns, BoundingRectangle px, hasFocus, children}`. `WinNormalizer` (own copy of the comparator stub, see deltas below) yields canonical `{id, role, label, value, actions, parent, order}` with the same id rule as the comparator (AutomationId if unique, else `id~parent#order`, none gives `anon:parent#order`).
- **Stimuli** (step file `ops`): `focus` (UIA SetFocus, verified by HasKeyboardFocus), `type` (per UTF-16 unit through `VkKeyScanW` virtual keys, shift/ctrl/alt state handled; a unit with no key on the layout is an error, not a Unicode packet), `key` (chord such as `ctrl+shift+z`, `tab`), `command` (`copy|paste|undo|redo|selectAll` mapped to Ctrl-C/V/Z/Y/A per CONTRACT §4), `invoke` (InvokePattern), `setValue` (ValuePattern), `select` (TextPattern: collapse document range, `Move` by characters, `MoveEndpointByUnit`, `Select`), `wait`. Keys are only sent when the target process owns the foreground (activated first, otherwise the op fails instead of typing blind).
- **Observation after every step**: focused element canonical id (deepest node with `HasKeyboardFocus`), TextPattern selection as UTF-16 location/length (selection start measured with `MoveEndpointByRange` on a document clone), selection text, caret rect from the one-character range at the selection start (CONTRACT §5; at end of text the previous character's trailing edge, width 0), model values from `modelNodes` selectors, canonical `axNodes` when the step says `capture: true`. `lifecycle` and `effects` stay empty (they come from in-process instrumentation, not UIA).
- **Selectors** match AutomationId or canonical id, plus `type`, `name`, `nth`, and are re-resolved against a fresh walk before each op, so a stale element never gets used.
- **Trace types**: TraceKit's structs have no public memberwise initialisers and the comparator must not be edited, so the recorder writes structurally identical Codable mirrors (`WTrace` etc.). `NormalizerTests.mirrorTraceDecodesWithTraceKit` and every `UIACompare` run decode them with TraceKit's own types, which is the compatibility proof.

### Normalizer deltas against comparator `UIANormalizer` (kept in `Sources/UIAKit/Model.swift`)

1. Returns `idByIndex` (raw node to canonical id), needed to turn the UIA focused element into the canonical `focusedNodeId`.
2. `TitleBar` subtree is dropped whole (system menu, Minimize, Maximize, Close). The stub only stripped Pane/Group/Custom, which would have promoted those buttons into window children. Needed for any real HWND.
3. Read-surface patterns (`TextPattern`, `LegacyIAccessiblePattern`, `WindowPattern`, `TransformPattern`, `ScrollItem/Selection/ScrollPattern`, …) are not actions. Without this every live node diffs on a `LegacyIAccessiblePattern` action. Added `TogglePattern` to `toggle`, `SelectionItemPattern` to `select`.

## Why Swift orchestration over a C shim, not pure Swift COM and not PowerShell

- PowerShell/C# (`System.Windows.Automation`, as `drive-smoke.ps1` does) would have worked for this slice and is the fallback. Swift was chosen because the replay driver should be a native binary built with the same toolchain as the fixtures (one signable artifact, no PowerShell/.NET runtime dependency in the oracle lane).
- Swift's `WinSDK` module has no UIAutomation module (`winsdk_um.modulemap` lists only `ole2.h`/`oleauto.h`). Importing `UIAutomationClient.h` through a clang module (SwiftPM C target) fails: `oleacc.h:171: error: missing '#include <windef.h>'; 'HWND' must be declared before it is used`. It persisted after adding explicit `windef.h`/`winuser.h`/`objbase.h` includes (2 attempts).
- Resolution: `Sources/CUIA/include/CUIA.h` is a flat, header-free C API (opaque `void*` handles, UTF-16 buffers); `shim.c` (about 300 lines) includes the Windows headers non-modularly and does all vtable calls. Everything else (walk, normalization, steps, input orchestration, trace, compare) is Swift. The shim compiles to nothing on macOS (`#ifdef _WIN32`), so the package builds on both.
- Consequence: the "Swift COM interop" is real but thin. A future pure-Swift COM layer is possible only with a module map that keeps UIA headers out of the module; not worth it for SR0.

## Commands

```
# build + test on Mac (portable parts)
cd probes/sr0-o/uia-recorder && swift build && swift test
# Mac -> Windows: sync comparator + recorder, build release (swift build -c release --scratch-path D:\Claude\sr0o-uia\scratch)
scripts/winbuild.sh
# Mac -> Windows: build, run one-shot INTERACTIVE scheduled task (launch BridgeSmoke, run recorder, delete the task)
scripts/winrun.sh record r1                       # tree | record ; tag
scripts/winrun.sh record ops "-Steps 'D:\Claude\sr0o-uia\uia-recorder\fixtures\bridgesmoke-ops-steps.json'"
# compare (Mac exe or Windows exe)
UIACompare fixtures/bridgesmoke-expected.json out/trace-r1.json [--adapt a.json] [--json]
scripts/compare-win.sh fixtures/bridgesmoke-expected.json 'D:\Claude\sr0o-uia\out\trace-r2.json'
# direct use on the Windows desktop session
UIARecorder.exe record --pid <pid> --steps steps.json --out trace.json --sidecar extra.json
UIARecorder.exe tree   --pid <pid> [--out tree.json]
```
Exit codes: recorder 0 ok, 1 an op failed (trace still written), 2 usage/attach error; compare 0 pass, 1 diffs, 2 error.
The interactive task is created, started, waited on, and `Unregister-ScheduledTask`d by `schedule-record.ps1`; `Get-ScheduledTask SR0O-UIA*` afterwards returns 0 tasks. No `Remove-Item -Recurse` anywhere.

## Verbatim outputs (trimmed)

### Windows build

```
swift build exit=0
UIACompare.exe 726016
UIARecorder.exe 924672
```

### Raw live tree (`tree --pid`, out/tree-t1.json), BridgeSmoke at idle

```
Window 'SwiftRight BridgeSmoke' class Zed::Window  [WindowPattern, TransformPattern, LegacyIAccessible]
  TitleBar  value 'SwiftRight BridgeSmoke'                  (MenuBar/MenuItem 'System', Button Minimize/Maximize/Close)
  Text ''  [LegacyIAccessible]   bounds x=978 y=558  w=539 h=60
  Text ''  [LegacyIAccessible]   bounds x=978 y=658  w=500 h=180
  Button 'Press me'  [Invoke, LegacyIAccessible]   x=978 y=888 w=400 h=100
  Edit 'Edit' value ''  [Value, LegacyIAccessible] hasFocus=True   x=978 y=1038 w=1000 h=90
  Text ''  [LegacyIAccessible]   x=978 y=1178 w=400 h=60
```

### Record run r1 (stdout of the scheduled task, trimmed)

```
registered=SR0O-UIA-record-r1 ...   state=Ready last_result=0   deleted=SR0O-UIA-record-r1 exists_after=False
target pid=41296
recorder exit=0   target exit=0
wrote D:\Claude\sr0o-uia\out\trace-r1.json steps=4 ok=true
event: AX action=2 node=2 / event: AX invoke node=2 ... / event: key a typed=a mods=0     (target's own log)
PASS AX Invoke handled [invokes=1 ...]
PASS typed character reached the text store [typed=[a] ime_replace_calls=1 key_events=1]
SMOKE PASS (18/18)
```

### Emitted trace (out/trace-r1.json), per step

```
platform {"arch":"x64","os":"windows","osBuild":"10.0.26300","toolchain":"Swift 6.4.0 (swift-6.4-RELEASE)"}
initial       model {node/edit: ''}  focus anon:anon:root#0#3  selection none
invoke_press  UIA InvokePattern.Invoke [type=Button,name=Press me]   (op ok)
focus_edit    UIA SetFocus [type=Edit]                               (op ok)
type_a        SendInput VK keys 'a' [type=Edit]   model {node/edit: 'a'}  focus anon:anon:root#0#3
              selection {location:1,length:0}   sidecar caretRect [1018,1053,0,60] px   focusedValue 'a'
canonical axNodes (initial):
  anon:root#0            window       label 'SwiftRight BridgeSmoke'
  anon:anon:root#0#0     static-text  (no label/value)        order 0
  anon:anon:root#0#1     static-text  (no label/value)        order 1
  anon:anon:root#0#2     button       label 'Press me'  actions [activate]   order 2
  anon:anon:root#0#3     text-field   label 'Edit' value ''  actions [set-value]   order 3
  anon:anon:root#0#4     static-text  (no label/value)        order 4
type_a: Edit gains TextPattern ['ValuePattern','TextPattern','LegacyIAccessiblePattern'], value 'a'
```
The first live TextPattern evidence on Windows (CONTRACT §8 open item): selection and caret rect are readable once the edit node has text runs.

### Comparator: expected passes

```
$ UIACompare fixtures/bridgesmoke-expected.json out/trace-r1.json
fixture BridgeSmoke: accepted=windows candidate=windows
note: platform differs (not compared): accepted ... "hand-written" candidate ... "10.0.26300" ...
PASS: 0 diffs                                  exit=0
```
Same PASS for r2 and r3 on the Mac exe, and r2 on the Windows exe (`compare-win.sh`).

### Comparator: one expectation flipped (typed value 'a' to 'b', selection 1 to 2, in `bridgesmoke-expected-FLIPPED.json`)

```
FAIL: 3 diff(s)
  step=type_a  path=model[node/edit]
    expected: b
    actual:   a
  step=type_a  path=selection
    expected: location=2 length=0
    actual:   location=1 length=0
  step=type_a  path=axNodes.value[anon:anon:root#0#3]
    expected: b
    actual:   a                                exit=1
```
Also confirmed on the Windows exe against trace-r3.

### Comparator: bridge intent versus UIA reality (`bridgesmoke-expected-INTENT.json`)

The hand-written expected labels the bridge commits for the two fixed static texts (`main.swift:99-115`). Result: `FAIL: 6 diff(s)`, all `axNodes.label[anon:anon:root#0#0|#1]` expected the text, actual `<nil>`, at steps initial, invoke_press, type_a. This is a real gap (below), not a recorder defect: UIA exposes empty Name and no ValuePattern for these Text nodes.

### Stimulus paths beyond the main run (`bridgesmoke-ops-steps.json`, out/run-ops.log)

Target-side event log proves each native route reached the bridge:
```
event: key a typed=a / key b typed=b          type 'ab' by VK            ops ok
event: AX action=4 node=3                     TextPattern.Select (set selection)   op ok
event: key a typed= mods=1                    Ctrl-A (mods=1 = ctrl)     op ok
event: AX action=3 node=3                     ValuePattern.SetValue      op ok
event: AX action=2 node=2 / AX invoke         InvokePattern              op ok
SMOKE PASS (18/18)
```
BridgeSmoke itself does not act on setSelection, setValue or Ctrl-A (selection stayed 2+0, value stayed 'ab'), so selection/value change read-back is untested; delivery is proven.

### Unit tests (Mac, `swift test`)

```
Test run with 7 tests in 2 suites passed.
```
(stripping/roles, read-surface actions excluded, ids and index map, window chrome subtree dropped, selector resolution, native mapping text, TraceKit decodes the mirror both ways.)

## PASS/FAIL table

| Requirement | Result |
|---|---|
| Swift tool attaching by PID, UIA RawView walk | PASS (via C shim for COM, see justification) |
| Canonical nodes: AutomationId, ControlType, Name, Value, patterns to actions, BoundingRectangle px, parent, order | PASS (bounds in sidecar, schema has no frames) |
| Focus by selector (UIA SetFocus) | PASS (HasKeyboardFocus verified) |
| Type via virtual-key SendInput, no Unicode packets | PASS ('a' reached store: `key a typed=a`) |
| Invoke | PASS (`AX invoke node=2`) |
| SetValue / TextPattern select / Ctrl-A / key chords | delivered PASS, outcome not testable on BridgeSmoke (it ignores them) |
| Read Value, TextPattern selection (UTF-16), caret rect | PASS (Value 'a', selection 1+0, caret [1018,1053,0,60]) |
| Emits TraceKit v0 trace | PASS (decoded by TraceKit; UIACompare loads it) |
| Normalizer extension (copy under uia-recorder/, comparator untouched) | PASS (3 deltas) |
| CLI comparing a Windows trace with a Mac/accepted trace | PASS (`UIACompare`, builds Mac and Windows; no real Mac trace exists for BridgeSmoke, so the cross-OS case is only exercised by schema/platform note) |
| Hand-written expected passes | PASS, 3/3 runs |
| Flipped expectation fails with precise diff | PASS, 3 diffs with step, path, expected, actual |
| Repeatability | 3 clean runs; not 20 |
| Static-text labels exposed | FAIL (empty Name, no value) |
| Interactive task cleaned up | PASS (0 tasks left) |

Fix iterations used: 5 of 6 (C-module include error x2 leading to the C-shim pivot, enum `rawValue`, missing public inits, drop-TitleBar). Codex was not consulted (no stall after one failed attempt that the pivot did not resolve).

## Gaps for replaying F1 to F9

1. **No AutomationId from the bridge.** BridgeSmoke nodes have empty AutomationId (AccessKit `author_id` is unset; ABI `NodeUpsert` has numeric ids only), so ids are `anon:parent#order`. Fixtures need `row/<uuid>/field` and `toolbar/insert`; ABI/renderer must carry a string author id into the UIA tree before F1 to F9 selectors and `focusedNodeId` can match the Mac oracle.
2. **Static text has no Name/Value in UIA** (3 nodes empty). Text content is needed for F1-style row text and the Mac `AXValue` parity. Bridge label to AccessKit label for `staticText` role needs checking.
3. **TextPattern only exists when the edit has text runs.** Empty edit returns no TextPattern, so selection is nil where Mac returns 0+0. Replay must tolerate or the bridge must emit runs for empty text.
4. **Mac normalizer parity.** Mac tree root is `AXApplication` with menu bar and window chrome (`AXCloseButton`, `AXFullScreenButton`, `AXToolbar`); the Windows normalizer drops `TitleBar` and roots at the window. A shared drop list or adaptation is needed before a real Mac F1 trace compares cleanly. `Text`/static-text value (Mac `AXValue`) versus Windows Name, and `set-value` action (Windows only) need declared adaptations.
5. **List/ListItem unproven.** BridgeSmoke has no list. `List`, `ListItem` mapping exists but the AccessKit control types, `SelectionItem` actions, container stripping (`Pane`/`Group`/`Custom`) and accessibility order (F2, F8) must be observed on a real list.
6. **Lifecycle, model rows, effects** are recorder-empty. Add a merge of the fixture's in-process JSONL events (as the Mac `fixture-events-*.jsonl`) into `Observation.lifecycle/effects/model`; F3, F4, F9 depend on it.
7. **Stimuli not implemented:** fake-engine release and fixture clock (needs a fixture-owned control channel), window resize (F5: `SetWindowPos` or TransformPattern), window close (F9: WindowPattern.Close/WM_CLOSE), reduced-motion toggle (F6), row move (F2), delete/insert via fixture buttons (works through `invoke` once ids exist).
8. **IME (F7):** VK typing is IME-compatible but composition needs the Microsoft Japanese IME active on the layout; there is no UIA marked-text route (CONTRACT §5: runtime-owned buffer), so composition/commit must be asserted through the model text and bridge IME log. Untested.
9. **UTF-16 mapping:** `selectRange` and caret probes use `TextUnit_Character` (grapheme-like), which equals UTF-16 units only for BMP text. Astral and combining-mark text need a per-unit check.
10. **Foreground/focus fragility:** keys are refused when the target is not foreground, so it needs an unlocked interactive desktop (RDP disconnect or lock screen fails). The signed recorder identity and any UIPI/elevation concerns are not addressed.
11. **Observation timing:** fixed `settleMs` (default 300 ms) is not the settlement condition of architecture §11. Replace with declared settlement checks (poll a node value or event) before the 20-run seeds.
12. **Repeatability:** only 3 BridgeSmoke runs; the 20-run protocol and `sr0o-trace repeat` integration are not wired.
13. **Hand-written expected** is derived from the bridge's semantics and the observed tree, not from a Mac oracle; BridgeSmoke has no Mac counterpart.
