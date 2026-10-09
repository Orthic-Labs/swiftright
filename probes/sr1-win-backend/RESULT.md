# SR1 Windows gallery on bridge ABI 0.6 (build only)

Status: **BUILD ONLY.** The gallery is moved from the 0.5 workarounds onto ABI 0.6 (bridge commit 4df7e67, renderer DLL
sha256 `C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30`). Nothing was launched on the Windows desktop or on
the Mac. The self-test has not been executed. Desktop behaviour is unverified.

## Mapping (ABI 0.5 workaround -> ABI 0.6)

| Control | 0.5 workaround | 0.6 |
|---|---|---|
| Toggle | button role, value `1`/`0`, check glyph | `checkbox` role, `toggled` on/off (UIA TogglePattern), invoke/focus actions, `disabled` flag. Check glyph kept as drawing. |
| List row | highlight only | `listItem` with `selected` (selectable = flag present); highlight kept as drawing |
| Disabled button / toggle | grey fill, host strips flags and actions, host suppresses invoke | `disabled` flag (`SWR_SEM_DISABLED`). Grey fill is visual only. Renderer refuses invoke and swallows presses; runtime also refuses. Host strip and suppression removed. |
| Image (`star.fill`, `logo`, `tray`) | placeholder rect, group role | `SWR_PRIM_IMAGE` of a generated 32x32 RGBA pattern (gradient for `star.fill`, checker otherwise), `image` role, `registerImage` at ready, released at close. No asset files. |
| Menu / context menu | in-window overlay always | `requestMenu` at the pointer (live runs only). Item id = entry index + 1. Overlay (`menu` container, `menuItem` rows) only when the result is `-2` or without `--live-modal`. |
| Alert | MessageBox YES/NO (2 actions) | `requestDialog`, one custom button per action (item id = index + 1), answer through `performPresentationAction(index: id - 1)`. Live runs only. Role `alert`. |
| Confirmation dialog | unsupported (3 actions) | `requestDialog` with 3 buttons. Role `dialog`. Up to 8 buttons; more is `unsupported-N-actions`. |
| TextEditor | one run per paragraph, no AX runs | one multi-paragraph text node (`\n` kept as line-break cells). One AX text run per visual line; a paragraph's run ends with its `\n`. |
| Presentation | none | `alert` or `dialog` semantic node covering the window, no primitives, no hit target |

Remaining limits, all noted in the code:
- Image opacity is not applied (the primitive has no alpha). The image fills its rect.
- Menu submenus are flattened: shown disabled with `>`, as in the 0.5 overlay.
- Editor run ids use the bridge's 2^16-id block per text node (`axTextRunBlockSize`). A text node over 65536 lines is a typed error (`AXTextRunError.blockExceeded`), recorded in `commitErrors`, not an overlap.
- Every text field and editor publishes at least one AX text run. An empty one gets a zero-length run at the origin and a degenerate selection at (run, 0) (`makeAXTextRunsChecked` with a nil measurement). This was a gap in the 0.5 carry-over; the bridge now has a unit test for it.

## Self-test semantics

The self-test never opens a native popup or task dialog. Without `--live-modal` the modal answers are fed through
`GalleryBackend.modalResult(requestID:kind:itemID:index:)` with the arguments the renderer would send. This checks the item-id
mapping without a person. The display items stay BLOCKED (exit 3), because a person or UIA must see and answer the native
surface. The gallery checks what the backend committed (`CommittedSemantic`: role, toggled, selected, disabled, AX run texts).
The ABI 0.6 uses are logged as `ABI-06 USE ...`.

## Build (done)

Mac (`probes/sr1-win-backend`): `swift build` and `swift build -c release` both complete, with no errors or warnings.

Windows staging: `scripts/sync-to-win.sh` from a dereferenced stage (46 files, no symlinks) into `D:\Claude\sr1-gallery06`.
Nothing under `D:\Claude\sr0b-abi0`, `D:\Claude\sr0s-bridge` or `D:\Claude\sr1-gallery` was touched.

Windows build, run as a file:

```
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr1-gallery06\probes\sr1-win-backend\scripts\build-gallery.ps1"
```

Result: `dll_sha256=C80B9517...FB30` matches, exports `swr_image_register` and `swr_image_release`, `swift build` exit 0, no warnings,
`BUILD OK`. Output is `D:\Claude\sr1-gallery06\scratch\out\Products\Release-windows-x86_64\SR1Gallery.exe` (also in
`D:\Claude\sr1-gallery06\bin-path.txt`).

Manifest, verified with `mt.exe` (read-only):

```
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr1-gallery06\probes\sr1-win-backend\scripts\verify-manifest.ps1"
```

Result: ComCtl v6 dependency and `PerMonitorV2` / `true/pm` present.

## Run (not yet done; each needs the interactive desktop)

Self-test for one screen, in a one-shot interactive task (writes `result-<screen>-<tag>.txt`):

```
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr1-gallery06\probes\sr1-win-backend\scripts\schedule-gallery.ps1 -Screen menu -Tag run1"
```

Screens: `toggle image editor label list-single list-multi list-delete menu alert dialog shortcut disabled`.

Interactive run with native popups and task dialogs (a person answers them):

```
SR1Gallery.exe --screen menu --live-modal
```

Exit codes: 0 PASS, 1 FAIL, 3 BLOCKED, 2 usage, 78 startup diagnostic.
