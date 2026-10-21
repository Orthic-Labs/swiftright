# swiftright-03 Stage 2: a TSF text store that owns composition (#33)

## Why Stage 2
Stage 1 (diagnostic renderer, Dell desktop, Microsoft Japanese IME, F7live; issue #33 comment of 21 October) proved that no IMM32 or bridge trigger moves an **open** modern candidate list after a layout move:
- (a) answering IMR_QUERYCHARPOSITION;
- (b) `ITfContextOwnerServices::OnLayoutChange` on the bridge context, all S_OK;
- (c) `ImmNotifyIME` close/open, which finds no IMM candidate list.

The list stays visible at its old rect. Two side findings:
- Setting IMM candidate forms for indices 1-3 hides the modern list.
- The native probe parses `ime_*` stderr lines by their trailing fields, so never append to them.

The documented TSF mechanism is a text store of our own, `ITextStoreACP`, whose `ITextStoreACPSink::OnLayoutChange(TS_LC_CHANGE, view)` makes the IME re-call `GetTextExt` and move its UI. A position-only store cannot coexist with the current IMM32 path: `AssociateFocus` routes the IME to our store and the WM_IME_* messages GPUI relies on stop. So the renderer owns composition over TSF.

## Components (render/swiftright-render/src/tsf.rs, wired from view.rs; Windows only)
- **COM objects** (windows crate `=0.61.3` `implement` macro; features Win32_System_Com, Win32_UI_TextServices, Win32_UI_Input_Ime):
  - `TextStore`, implementing `ITextStoreACP` and `ITfContextOwnerCompositionSink`;
  - the thread manager `ITfThreadMgr` (Activate gives a client id);
  - `ITfDocumentMgr` from `CreateDocumentMgr`;
  - `ITfContext` from `CreateContext` (store as the punk), then `Push`.
- **Window association:** `ITfThreadMgr::AssociateFocus(hwnd, doc_mgr)` when a text field takes focus (host focus events), `AssociateFocus(hwnd, None)` when it loses focus. `ImmAssociateContextEx(hwnd, NULL, 0)` while the store is associated, so GPUI's IMM handlers go quiet. Restore the IMM context when no field is focused (IACE_DEFAULT).
- **Store to host mapping** (existing host callbacks in view.rs; no GPUI InputHandler):

| TSF call | Host callback |
|---|---|
| `GetText` | `ime_copy_text` |
| `GetSelection` | `ime_get_selection` |
| `SetText` / `InsertTextAtSelection` during a composition | `ime_replace_and_mark` |
| Commit | `ime_replace` |
| Composition end | `ime_unmark` |
| `GetTextExt(view, acpStart, acpEnd)` | `ime_caret_bounds` per offset (`ime_caret_rect_at`), client to screen |
| `GetScreenExt` | client rect in screen px |
| `GetActiveView` | 1 |
| `GetWnd` | hwnd |

  `SetSelection` with a non-collapsed range has no host callback today. Collapse it to the end and log `tsf_set_selection_collapsed`; an additive ABI entry is a later step only if a check needs it.
- **Locks:**
  - `RequestLock(flags)`: when no lock is held and the host text bridge is not busy (`S_IME_BUSY` false), grant synchronously by calling `OnLockGranted` on the sink and return its result.
  - Otherwise, if `TS_LF_SYNC` is set, return `TS_E_SYNCHRONOUS`. If not, queue it (`TS_S_ASYNC`) and grant from a posted window message (`WM_APP + n`) on the UI thread.
  - Never call the host while it is inside the text bridge.
- **Notifications:**
  - After a layout move (`ime_replace_on_layout`): `sink.OnLayoutChange(TS_LC_CHANGE, 1)`.
  - When the host changes text or selection outside a TSF lock: `OnTextChange` and `OnSelectionChange`.
- **Threading:** everything on the UI thread (STA). Initialise COM there if GPUI has not (balance S_OK/S_FALSE).
- **Logging:** new `tsf_*` stderr lines only. Leave the existing `ime_*` lines byte-identical; the probe parses them.

## Main risks
- **Leaks:** COM reference leaks against the R10 leak gate (keep it under 5.0 MB/min).
- **Other IMEs:** Chinese and Korean IMEs, the emoji panel and the touch keyboard (manual smoke).
- **Focus changes:** the context must be reset when focus moves to another field.
- **GPUI internals:** GPUI 0.2.2 is not vendored.

**No-go:** needing a GPUI fork, or R10 above 5 MB/min. Either way #33 stays an accepted SR1 limit.

## Acceptance and re-runs
- **Acceptance:** after a layout move, the open candidate list translates by the caret delta within 12×scale px per axis and stays anchored to the new caret (drive-ime.ps1 `IME_CANDIDATE_AFTER_MOVE state=followed`). F7live passes without the follows-layout-move allowance.
- **Re-runs for the new pin:**
  - ime-f7 ×20, ime-f7live and ime-f8;
  - native F1 smoke 17/17;
  - R10 leak.
- **Pins:** SR0 tuple 13 stays frozen (#33 is an accepted SR0 limit). The new renderer is an SR1 pin.
