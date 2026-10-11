# swiftright-03: open IME candidate list follows the composing field (HELD, UNBUILT, UNTESTED)

Patch: swiftright-03-ime-candidate-follow.patch (render/swiftright-render/src/view.rs only; `git apply --check` passes).

## Finding
- The renderer never handles WM_IME_REQUEST. IMR_QUERYCHARPOSITION falls to DefSubclassProc, so a TSF-based IME on this IMM32 window gets no live caret from us (grep: no IMR_/0x0288 anywhere in render/).
- Layout move re-places via ImmSetCompositionWindow / ImmSetCandidateWindow(index 0, CFS_EXCLUDE) only (ime_replace_on_layout -> place_ime_windows).
- Harness evidence: the open-time candidate is an explorer-hosted ApplicationFrameWindow (modern TSF candidate UI, not an IMM "Candidate" class window). After the move the harness found NO candidate (`candidate 400 ms after the move=none`), so the list may have been hidden/re-created rather than merely left in place. Measured by EnumWindows/UIA rect in drive-ime.ps1 (visible rect, per-axis tolerance 12*scale, anchored to new caret).

## Change
1. Answer WM_IME_REQUEST / IMR_QUERYCHARPOSITION with live geometry: fills IMECHARPOSITION pt (screen px of char at dwCharPos from composition start), cLineHeight, rcDocument (client rect in screen px); returns 1. Falls through to default if host busy/size too small. Logs `ime_query_charpos`.
2. ime_caret_rect_at(hwnd, off) added (ime_caret_rect = off 0).
3. place_ime_windows also sets candidate forms for list indices 1-3 (same CFS_EXCLUDE rect).

## Claims
- Documented (Microsoft Learn, "WM_IME_REQUEST message", "IMECHARPOSITION structure", "CANDIDATEFORM"): IMR_QUERYCHARPOSITION asks the app for screen position of a composition character; app fills IMECHARPOSITION and returns nonzero; candidate form is per index 0-3; CFS_EXCLUDE keeps list off the rect.
- Documented: ImmSetCandidateWindow/CompositionWindow set forms the IME reads; no documented "reposition open list" notification.
- UNVERIFIED: that the Windows 11 Microsoft IME re-queries IMR_QUERYCHARPOSITION (or re-reads forms) while a list is open, or on any trigger we can fire; that rcDocument = client rect is acceptable; that indices 1-3 matter.
- UNVERIFIED whether GPUI 0.2.2 (not vendored) already handles WM_IME_REQUEST before our subclass: our subclass runs first (outermost), so ours wins.

Confidence the patch alone makes the open list follow: low (~25%). It removes a certain gap (stale/absent answer) but supplies no trigger forcing the IME to re-query. Check first in a desktop run: does `ime_query_charpos` ever fire after `ime_replace reason=layout`? If no, the IME never asks and IMM32 cannot fix it.

## If insufficient: TSF design outline (b)
- Implement ITextStoreACP (+ITfContextOwnerCompositionSink, ITfTextEditSink as needed) per composing field; create ITfThreadMgr/ITfDocumentMgr/ITfContext via ITfThreadMgr::CreateDocumentMgr, AssociateFocus on the HWND (disables CUAS bridge for that window; ImmAssociateContext(NULL) to avoid double input paths).
- Store: AdviseSink(ITextStoreACPSink), GetSelection/GetText/SetText/InsertTextAtSelection/GetTextExt (screen-px rect of acp range from ime_caret_bounds), GetScreenExt, GetActiveView, RequestLock (async lock grant on UI thread), composition via ITfContextOwnerCompositionSink.
- On layout move: call sink->OnLayoutChange(TS_LC_CHANGE, viewCookie) (and OnUpdateWindow semantics), then IME re-calls GetTextExt: this is the documented TSF mechanism for "layout moved" (Microsoft Learn "Text Services Framework", ITextStoreACPSink::OnLayoutChange).
- Reimplementing all of marked text / commit over TSF replaces the current ime_* InputHandler path: large, needs its own risk review (Sonnet/Terra tier at minimum).

## Contract
An open candidate list follows the composing field when layout moves it (candidate rect translates by the caret delta within 12*scale per axis and stays anchored to the new caret).

## Tuple members reopened
Renderer DLL (swiftright-render) and everything bound to it: new renderer hash, FreshOnBridge/bridge tuple binding, fixtures built against it, SR0 native-interaction ime-f7/f7live/f8 results (re-run on Windows 11 desktop lane). Mac renderer unaffected (Windows-only code).
