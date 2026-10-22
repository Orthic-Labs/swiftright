//! #33 Stage 2: a TSF text store that owns IME composition for the focused editable field, so an open Microsoft Japanese IME
//! candidate list follows the field when layout moves it (design: docs/held-patches/swiftright-03-tsf-design.md).
//!
//! UI thread only (COM apartment = the thread that runs the window). The store reaches the host through the `tsf_host_*`
//! bridge in view.rs (the same ime_* callbacks and non-reentrant guard the GPUI InputHandler path uses). While a text field
//! is focused the window is associated with our document manager (`ITfThreadMgr::AssociateFocus`) and its IMM context is
//! NULL, so GPUI's WM_IME_* handling goes quiet and composition runs over TSF. If anything in initialisation fails the
//! IMM32 path is left exactly as it was (`tsf_init_failed`).
//!
//! Ownership: every COM interface held by `Tsf` is released in `Tsf::shutdown` (window WM_DESTROY, via `teardown`). The only
//! reference cycle (TSF's sink <-> our store) is broken by `UnadviseSink` on Pop and by clearing `State::sink` in shutdown.

use std::cell::{Cell, RefCell};
use std::ffi::c_void;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering::SeqCst};

use windows::core::{implement, Interface, Ref, BOOL, GUID, HRESULT, IUnknown, PCWSTR, PWSTR};
use windows::Win32::Foundation::{E_FAIL, E_INVALIDARG, E_NOTIMPL, E_UNEXPECTED, HWND, RECT, S_FALSE, S_OK};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, IDataObject, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED,
};
use windows::Win32::UI::TextServices::{
    CLSID_TF_InputProcessorProfiles, CLSID_TF_ThreadMgr, GUID_TFCAT_TIP_KEYBOARD, ITextStoreACP, ITextStoreACPSink, ITextStoreACP_Impl, ITfCompositionView, ITfContext,
    ITfContextOwnerCompositionServices, ITfContextOwnerCompositionSink, ITfContextOwnerCompositionSink_Impl,
    ITfCandidateListUIElement, ITfCandidateListUIElementBehavior, ITfDocumentMgr, ITfInputProcessorProfileMgr, ITfIntegratableCandidateListUIElement, ITfRange,
    ITfSource, ITfThreadMgr, ITfUIElementMgr, ITfUIElementSink,
    ITfUIElementSink_Impl, TEXT_STORE_LOCK_FLAGS, TEXT_STORE_TEXT_CHANGE_FLAGS, TS_ATTRVAL, TS_LC_CHANGE, TS_LC_CREATE, TS_LC_DESTROY, TS_RUNINFO, TS_RT_PLAIN,
    TS_SELECTIONSTYLE, TS_SELECTION_ACP, TS_STATUS, TS_TEXTCHANGE, TS_AE_END, TS_AE_START,
};

use crate::cand::CandState;
use crate::rt::*;
use crate::view;

/// WM_APP + 0x5A3 (pace WM_SWR_PAINT is + 0x5A1, view WM_SWR_MODAL + 0x5A2): a queued async TSF lock request is ready to grant.
pub const WM_SWR_TSF: u32 = 0x8000 + 0x5A3;

// ---- constants spelled out (msctf.h) so the code does not depend on how the crate types them
/// #45 step 3 (UI-less own candidate popup, SWIFTRIGHT_IME_UILESS=1): WM_APP + 0x5A5 asks the render window to refresh (show / move /
/// hide) the popup; coalesced through `CAND_PENDING`. WM_APP + 0x5A4 is view.rs WM_SWR_CARET.
pub const WM_SWR_CAND: u32 = 0x8000 + 0x5A5;
/// WM_APP + 0x5A6: the popup's window procedure posts it to the owner on a left click over a row (wparam = row on the page).
pub const WM_SWR_CAND_PICK: u32 = 0x8000 + 0x5A6;
/// WM_APP + 0x5A7: mouse wheel over the popup (lparam = +1 wheel down / next, -1 wheel up / previous).
pub const WM_SWR_CAND_WHEEL: u32 = 0x8000 + 0x5A7;
static CAND_PENDING: AtomicBool = AtomicBool::new(false);
/// SWIFTRIGHT_IME_UILESS_PICK diagnostic: the scheduled pick has been armed (once per process).
static PICK_ARMED: AtomicBool = AtomicBool::new(false);

const TS_LF_SYNC: u32 = 0x1;
const TS_LF_READ: u32 = 0x2;
const TS_LF_READWRITE: u32 = 0x6;
const TS_AS_TEXT_CHANGE: u32 = 0x1;
const TS_AS_SEL_CHANGE: u32 = 0x2;
const TS_AS_LAYOUT_CHANGE: u32 = 0x4;
const TS_IAS_QUERYONLY: u32 = 0x2;
const TS_DEFAULT_SELECTION: u32 = 0xFFFF_FFFF;
const TS_SS_NOHIDDENTEXT: u32 = 0x8;
const TF_POPF_ALL: u32 = 0x1;
const VIEW_COOKIE: u32 = 1;

const TS_E_INVALIDPOS: HRESULT = HRESULT(0x8004_0200u32 as i32);
const TS_E_NOLOCK: HRESULT = HRESULT(0x8004_0201u32 as i32);
const TS_E_NOSELECTION: HRESULT = HRESULT(0x8004_0205u32 as i32);
const TS_E_NOLAYOUT: HRESULT = HRESULT(0x8004_0206u32 as i32);
const TS_E_SYNCHRONOUS: HRESULT = HRESULT(0x8004_0208u32 as i32);
const TS_E_READONLY: HRESULT = HRESULT(0x8004_0209u32 as i32);
const TS_S_ASYNC: HRESULT = HRESULT(0x0004_0300);

#[link(name = "user32")]
extern "system" {
    fn ClientToScreen(hwnd: *mut c_void, pt: *mut [i32; 2]) -> i32;
    fn GetClientRect(hwnd: *mut c_void, rect: *mut [i32; 4]) -> i32;
    fn PostMessageW(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> i32;
}

/// Opt-in gate (issue #45, 22 Oct 2026): the TSF store runs only with SWIFTRIGHT_IME_TSF=1. Read once (view.rs reads it when it
/// installs the window subclass, i.e. at window creation); unset, every entry point below returns at once and the IMM32 path is untouched.
pub fn enabled() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var("SWIFTRIGHT_IME_TSF").map_or(false, |v| v == "1"))
}

/// Second opt-in gate (issue #45 UI-less spike): SWIFTRIGHT_IME_UILESS=1, effective only together with SWIFTRIGHT_IME_TSF=1. When on,
/// the UI element sink hides the system candidate list (pbShow=FALSE) and records its contents for `uiless_candidates`.
pub fn uiless() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| enabled() && std::env::var("SWIFTRIGHT_IME_UILESS").map_or(false, |v| v == "1"))
}

static LOG_BUDGET: AtomicU32 = AtomicU32::new(600);

macro_rules! tsf_log {
    ($($arg:tt)*) => {{
        eprintln!("[swiftright-render] {}", format!($($arg)*));
    }};
}

/// High-frequency lines (locks, extents) stop after a budget so a long session does not flood stderr.
macro_rules! tsf_log_capped {
    ($($arg:tt)*) => {{
        if LOG_BUDGET.fetch_update(SeqCst, SeqCst, |n| n.checked_sub(1)).is_ok() {
            tsf_log!($($arg)*);
        }
    }};
}

fn err<T>(hr: HRESULT) -> windows::core::Result<T> {
    Err(hr.into())
}

fn hr_of(r: &windows::core::Result<()>) -> u32 {
    match r {
        Ok(()) => 0,
        Err(e) => e.code().0 as u32,
    }
}

// ------------------------------------------------------------------------------------------------ shared state

/// What the store last told (or was told by) TSF about the field, to detect host-side changes outside a lock.
#[derive(Clone, Copy, Default, PartialEq)]
struct Known {
    valid: bool,
    sel: (u32, u32, bool),
    len: u32,
    hash: u64,
}

struct State {
    hwnd: Cell<isize>,
    sink: RefCell<Option<ITextStoreACPSink>>,
    mask: Cell<u32>,
    /// Lock currently granted (0 none, TS_LF_READ, TS_LF_READWRITE).
    lock: Cell<u32>,
    /// Merged async lock requests waiting for a grant (0 none).
    pending: Cell<u32>,
    composing: Cell<bool>,
    /// An IME candidate list UI element is open (ITfUIElementSink Begin .. End).
    cand_open: Cell<bool>,
    /// A text field has IME focus and the window is associated with the document manager.
    associated: Cell<bool>,
    node: Cell<u64>,
    last_snap: Cell<u64>,
    known: Cell<Known>,
}

impl State {
    fn new(hwnd: isize) -> State {
        State {
            hwnd: Cell::new(hwnd),
            sink: RefCell::new(None),
            mask: Cell::new(0),
            lock: Cell::new(0),
            pending: Cell::new(0),
            composing: Cell::new(false),
            cand_open: Cell::new(false),
            associated: Cell::new(false),
            node: Cell::new(0),
            last_snap: Cell::new(0),
            known: Cell::new(Known::default()),
        }
    }

    fn sink(&self) -> Option<ITextStoreACPSink> {
        self.sink.borrow().clone()
    }

    fn need_lock(&self, write: bool) -> windows::core::Result<()> {
        let l = self.lock.get();
        if l == 0 || (l & TS_LF_READ) == 0 {
            return err(TS_E_NOLOCK);
        }
        if write && (l & 0x4) == 0 {
            return err(TS_E_READONLY);
        }
        Ok(())
    }

    fn hwnd_ptr(&self) -> *mut c_void {
        self.hwnd.get() as *mut c_void
    }

    /// Selection + length + hash of the host text, or None when the host is busy / has no field.
    fn read_known(&self) -> Option<Known> {
        let sel = view::tsf_host_selection()?;
        let (text, _, _) = view::tsf_host_text(0, u32::MAX)?;
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        for u in &text {
            h = (h ^ *u as u64).wrapping_mul(0x0000_0100_0000_01b3);
        }
        Some(Known { valid: true, sel, len: text.len() as u32, hash: h })
    }

    fn refresh_known(&self) {
        if let Some(k) = self.read_known() {
            self.known.set(k);
        }
    }

    /// Posts the "grant a queued lock" message to the window.
    fn post_grant(&self) {
        let hwnd = self.hwnd_ptr();
        if !hwnd.is_null() {
            unsafe { PostMessageW(hwnd, WM_SWR_TSF, 0, 0) };
        }
    }

    /// Calls OnLockGranted with `flags` held. Never called while the host is inside the text bridge.
    fn grant(&self, sink: &ITextStoreACPSink, flags: u32) -> HRESULT {
        let f = flags & TS_LF_READWRITE;
        self.lock.set(f);
        let r = unsafe { sink.OnLockGranted(TEXT_STORE_LOCK_FLAGS(f)) };
        self.lock.set(0);
        if f == TS_LF_READWRITE {
            self.refresh_known();
        }
        tsf_log_capped!("tsf_lock granted flags=0x{f:X} hr=0x{:08X}", hr_of(&r));
        match r {
            Ok(()) => S_OK,
            Err(e) => e.code(),
        }
    }

    /// Grants queued async requests while no lock is held and the host is free.
    fn flush_pending(&self) {
        for _ in 0..8 {
            if self.lock.get() != 0 {
                return;
            }
            let p = self.pending.get();
            if p == 0 {
                return;
            }
            if host_active() {
                return; // the next paint (sync) or WM_SWR_TSF retries
            }
            let Some(sink) = self.sink() else {
                self.pending.set(0);
                return;
            };
            self.pending.set(0);
            self.grant(&sink, p);
        }
    }

    /// OnTextChange / OnSelectionChange for host-side changes outside a TSF lock.
    fn notify_host_changes(&self) {
        if self.lock.get() != 0 {
            return;
        }
        let Some(sink) = self.sink() else { return };
        let Some(new) = self.read_known() else { return };
        let old = self.known.get();
        if !old.valid {
            self.known.set(new);
            return;
        }
        if new == old {
            return;
        }
        self.known.set(new);
        view::tsf_caret_place(); // #45: the system caret follows a caret/selection change the host made (no-op unless SWIFTRIGHT_IME_SYSTEM_CARET=1)
        let mask = self.mask.get();
        if new.len != old.len || new.hash != old.hash {
            if mask & TS_AS_TEXT_CHANGE != 0 {
                let ch = TS_TEXTCHANGE { acpStart: 0, acpOldEnd: old.len as i32, acpNewEnd: new.len as i32 };
                let r = unsafe { sink.OnTextChange(TEXT_STORE_TEXT_CHANGE_FLAGS(0), &ch) };
                tsf_log_capped!("tsf_text_change old_len={} new_len={} hr=0x{:08X}", old.len, new.len, hr_of(&r));
            }
            if mask & TS_AS_SEL_CHANGE != 0 {
                let r = unsafe { sink.OnSelectionChange() };
                tsf_log_capped!("tsf_selection_change sel={},{} hr=0x{:08X}", new.sel.0, new.sel.1, hr_of(&r));
            }
        } else if mask & TS_AS_SEL_CHANGE != 0 {
            let r = unsafe { sink.OnSelectionChange() };
            tsf_log_capped!("tsf_selection_change sel={},{} hr=0x{:08X}", new.sel.0, new.sel.1, hr_of(&r));
        }
    }
}

// ------------------------------------------------------------------------------------------------ the COM object

#[implement(ITextStoreACP, ITfContextOwnerCompositionSink)]
struct TextStore {
    st: Rc<State>,
}

impl TextStore {
    /// Replaces [start, end) with `text`; marked while a composition is active, committed otherwise.
    /// The host's replace_and_mark marks only the text it inserts and commits the rest of the old composition, while a TSF
    /// composition spans every edit the IME made (Dell F7live ime33-tsf3: "ni" then "h" committed the hiragana). So an edit
    /// that touches the marked range re-marks the merged range: marked text before the edit + `text` + marked text after it.
    fn edit(&self, start: u32, end: u32, text: &[u16]) -> windows::core::Result<TS_TEXTCHANGE> {
        let marked = view::tsf_host_marked();
        let marking = self.st.composing.get() || marked.is_some();
        let n = text.len() as u32;
        let ok = if marking {
            let (ms, me) = match marked {
                Some((ms, me)) if start <= me && end >= ms => (ms.min(start), me.max(end)),
                _ => (start, end),
            };
            let piece = |a: u32, b: u32| if a < b { view::tsf_host_text(a, b).map(|t| t.0) } else { Some(Vec::new()) };
            match (piece(ms, start), piece(end, me)) {
                (Some(pre), Some(post)) => {
                    let mut full = pre;
                    full.extend_from_slice(text);
                    full.extend_from_slice(&post);
                    let caret = (start - ms) + n;
                    tsf_log_capped!("tsf_edit marked range={start},{end} n={n} mark={ms},{me} mark_len={}", full.len());
                    view::tsf_host_replace_and_mark(Some((ms, me)), &full, Some((caret, caret)))
                }
                _ => false,
            }
        } else {
            tsf_log_capped!("tsf_edit commit range={start},{end} n={n}");
            view::tsf_host_replace(Some((start, end)), text)
        };
        if !ok {
            return err(E_FAIL);
        }
        Ok(TS_TEXTCHANGE { acpStart: start as i32, acpOldEnd: end as i32, acpNewEnd: (start + n) as i32 })
    }
}

#[allow(non_snake_case)]
impl ITextStoreACP_Impl for TextStore_Impl {
    fn AdviseSink(&self, riid: *const GUID, punk: Ref<'_, IUnknown>, dwmask: u32) -> windows::core::Result<()> {
        if riid.is_null() || unsafe { *riid } != ITextStoreACPSink::IID {
            return err(E_INVALIDARG);
        }
        let unk = punk.ok()?;
        let sink: ITextStoreACPSink = unk.cast()?;
        *self.st.sink.borrow_mut() = Some(sink);
        self.st.mask.set(dwmask);
        tsf_log!("tsf_advise_sink mask=0x{dwmask:X}");
        Ok(())
    }

    fn UnadviseSink(&self, _punk: Ref<'_, IUnknown>) -> windows::core::Result<()> {
        let old = self.st.sink.borrow_mut().take();
        self.st.mask.set(0);
        self.st.pending.set(0);
        drop(old);
        tsf_log!("tsf_unadvise_sink");
        Ok(())
    }

    fn RequestLock(&self, dwlockflags: u32) -> windows::core::Result<HRESULT> {
        let want = dwlockflags & TS_LF_READWRITE;
        if want != TS_LF_READ && want != TS_LF_READWRITE {
            return err(E_INVALIDARG);
        }
        let sync = dwlockflags & TS_LF_SYNC != 0;
        let st = &self.st;
        let Some(sink) = st.sink() else { return err(E_UNEXPECTED) };
        if st.lock.get() == 0 && !host_active() {
            // Free and the host text bridge is idle: grant now (also for an async request).
            let hr = st.grant(&sink, want);
            st.flush_pending();
            return Ok(hr);
        }
        if sync {
            tsf_log_capped!("tsf_lock sync_denied held=0x{:X} host_busy={}", st.lock.get(), host_active());
            return Ok(TS_E_SYNCHRONOUS);
        }
        let merged = if st.pending.get() == TS_LF_READWRITE || want == TS_LF_READWRITE { TS_LF_READWRITE } else { TS_LF_READ };
        st.pending.set(merged);
        tsf_log_capped!("tsf_lock queued flags=0x{merged:X} held=0x{:X} host_busy={}", st.lock.get(), host_active());
        st.post_grant();
        Ok(TS_S_ASYNC)
    }

    fn GetStatus(&self) -> windows::core::Result<TS_STATUS> {
        Ok(TS_STATUS { dwDynamicFlags: 0, dwStaticFlags: TS_SS_NOHIDDENTEXT })
    }

    fn QueryInsert(
        &self,
        acpteststart: i32,
        acptestend: i32,
        _cch: u32,
        pacpresultstart: *mut i32,
        pacpresultend: *mut i32,
    ) -> windows::core::Result<()> {
        if acpteststart < 0 || acptestend < acpteststart {
            return err(TS_E_INVALIDPOS);
        }
        unsafe {
            if !pacpresultstart.is_null() {
                *pacpresultstart = acpteststart;
            }
            if !pacpresultend.is_null() {
                *pacpresultend = acptestend;
            }
        }
        Ok(())
    }

    fn GetSelection(
        &self,
        ulindex: u32,
        ulcount: u32,
        pselection: *mut TS_SELECTION_ACP,
        pcfetched: *mut u32,
    ) -> windows::core::Result<()> {
        self.st.need_lock(false)?;
        if pcfetched.is_null() || pselection.is_null() {
            return err(E_INVALIDARG);
        }
        unsafe { *pcfetched = 0 };
        if ulcount == 0 {
            return Ok(());
        }
        if ulindex != TS_DEFAULT_SELECTION && ulindex != 0 {
            return err(E_INVALIDARG);
        }
        let Some((s, e, rev)) = view::tsf_host_selection() else { return err(TS_E_NOSELECTION) };
        unsafe {
            *pselection = TS_SELECTION_ACP {
                acpStart: s as i32,
                acpEnd: e as i32,
                style: TS_SELECTIONSTYLE { ase: if rev { TS_AE_START } else { TS_AE_END }, fInterimChar: BOOL(0) },
            };
            *pcfetched = 1;
        }
        Ok(())
    }

    fn SetSelection(&self, ulcount: u32, pselection: *const TS_SELECTION_ACP) -> windows::core::Result<()> {
        self.st.need_lock(true)?;
        if ulcount == 0 {
            return Ok(());
        }
        if pselection.is_null() {
            return err(E_INVALIDARG);
        }
        let sel = unsafe { *pselection };
        let (a, b) = (sel.acpStart, sel.acpEnd);
        if a < 0 || b < a {
            return err(TS_E_INVALIDPOS);
        }
        let pos = b as u32;
        if a != b {
            // No host callback sets a ranged selection today (no ABI change): collapse to the end.
            tsf_log!("tsf_set_selection_collapsed start={a} end={b}");
        }
        if let Some((cs, ce, _)) = view::tsf_host_selection() {
            if cs == pos && ce == pos {
                return Ok(());
            }
        }
        let ok = match view::tsf_host_marked() {
            Some((ms, me)) if ms <= pos && pos <= me => match view::tsf_host_text(ms, me) {
                // Move the caret inside the composition: re-assert the marked text with the new relative selection.
                Some((text, _, _)) => {
                    let rel = pos - ms;
                    view::tsf_host_replace_and_mark(Some((ms, me)), &text, Some((rel, rel)))
                }
                None => false,
            },
            _ => view::tsf_host_replace(Some((pos, pos)), &[]),
        };
        if ok {
            Ok(())
        } else {
            err(E_FAIL)
        }
    }

    fn GetText(
        &self,
        acpstart: i32,
        acpend: i32,
        pchplain: PWSTR,
        cchplainreq: u32,
        pcchplainret: *mut u32,
        prgruninfo: *mut TS_RUNINFO,
        cruninforeq: u32,
        pcruninforet: *mut u32,
        pacpnext: *mut i32,
    ) -> windows::core::Result<()> {
        self.st.need_lock(false)?;
        if acpstart < 0 || (acpend >= 0 && acpend < acpstart) {
            return err(TS_E_INVALIDPOS);
        }
        let end = if acpend < 0 { u32::MAX } else { acpend as u32 };
        let Some((text, _, _)) = view::tsf_host_text(acpstart as u32, end) else { return err(E_FAIL) };
        let n = text.len().min(cchplainreq as usize);
        unsafe {
            if !pchplain.is_null() && n > 0 {
                std::ptr::copy_nonoverlapping(text.as_ptr(), pchplain.0, n);
            }
            if !pcchplainret.is_null() {
                *pcchplainret = n as u32;
            }
            let mut runs = 0u32;
            if !prgruninfo.is_null() && cruninforeq > 0 && n > 0 {
                *prgruninfo = TS_RUNINFO { uCount: n as u32, r#type: TS_RT_PLAIN };
                runs = 1;
            }
            if !pcruninforet.is_null() {
                *pcruninforet = runs;
            }
            if !pacpnext.is_null() {
                *pacpnext = acpstart + n as i32;
            }
        }
        Ok(())
    }

    fn SetText(&self, _dwflags: u32, acpstart: i32, acpend: i32, pchtext: &PCWSTR, cch: u32) -> windows::core::Result<TS_TEXTCHANGE> {
        self.st.need_lock(true)?;
        if acpstart < 0 || acpend < acpstart {
            return err(TS_E_INVALIDPOS);
        }
        let text: &[u16] = if cch == 0 || pchtext.0.is_null() {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(pchtext.0, cch as usize) }
        };
        self.edit(acpstart as u32, acpend as u32, text)
    }

    fn GetFormattedText(&self, _acpstart: i32, _acpend: i32) -> windows::core::Result<IDataObject> {
        err(E_NOTIMPL)
    }

    fn GetEmbedded(&self, _acppos: i32, _rguidservice: *const GUID, _riid: *const GUID) -> windows::core::Result<IUnknown> {
        err(E_NOTIMPL)
    }

    fn QueryInsertEmbedded(
        &self,
        _pguidservice: *const GUID,
        _pformatetc: *const windows::Win32::System::Com::FORMATETC,
    ) -> windows::core::Result<BOOL> {
        Ok(BOOL(0))
    }

    fn InsertEmbedded(
        &self,
        _dwflags: u32,
        _acpstart: i32,
        _acpend: i32,
        _pdataobject: Ref<'_, IDataObject>,
    ) -> windows::core::Result<TS_TEXTCHANGE> {
        err(E_NOTIMPL)
    }

    fn InsertTextAtSelection(
        &self,
        dwflags: u32,
        pchtext: &PCWSTR,
        cch: u32,
        pacpstart: *mut i32,
        pacpend: *mut i32,
        pchange: *mut TS_TEXTCHANGE,
    ) -> windows::core::Result<()> {
        let query = dwflags & TS_IAS_QUERYONLY != 0;
        self.st.need_lock(!query)?;
        let Some((s, e, _)) = view::tsf_host_selection() else { return err(TS_E_NOSELECTION) };
        if query {
            unsafe {
                if !pacpstart.is_null() {
                    *pacpstart = s as i32;
                }
                if !pacpend.is_null() {
                    *pacpend = e as i32;
                }
                if !pchange.is_null() {
                    *pchange = TS_TEXTCHANGE { acpStart: s as i32, acpOldEnd: e as i32, acpNewEnd: e as i32 };
                }
            }
            return Ok(());
        }
        let text: &[u16] = if cch == 0 || pchtext.0.is_null() {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(pchtext.0, cch as usize) }
        };
        let ch = self.edit(s, e, text)?;
        unsafe {
            if !pacpstart.is_null() {
                *pacpstart = ch.acpStart;
            }
            if !pacpend.is_null() {
                *pacpend = ch.acpNewEnd;
            }
            if !pchange.is_null() {
                *pchange = ch;
            }
        }
        Ok(())
    }

    fn InsertEmbeddedAtSelection(
        &self,
        _dwflags: u32,
        _pdataobject: Ref<'_, IDataObject>,
        _pacpstart: *mut i32,
        _pacpend: *mut i32,
        _pchange: *mut TS_TEXTCHANGE,
    ) -> windows::core::Result<()> {
        err(E_NOTIMPL)
    }

    fn RequestSupportedAttrs(&self, _dwflags: u32, _cfilterattrs: u32, _pafilterattrs: *const GUID) -> windows::core::Result<()> {
        Ok(())
    }

    fn RequestAttrsAtPosition(
        &self,
        _acppos: i32,
        _cfilterattrs: u32,
        _pafilterattrs: *const GUID,
        _dwflags: u32,
    ) -> windows::core::Result<()> {
        Ok(())
    }

    fn RequestAttrsTransitioningAtPosition(
        &self,
        _acppos: i32,
        _cfilterattrs: u32,
        _pafilterattrs: *const GUID,
        _dwflags: u32,
    ) -> windows::core::Result<()> {
        Ok(())
    }

    fn FindNextAttrTransition(
        &self,
        _acpstart: i32,
        acphalt: i32,
        _cfilterattrs: u32,
        _pafilterattrs: *const GUID,
        _dwflags: u32,
        pacpnext: *mut i32,
        pffound: *mut BOOL,
        plfoundoffset: *mut i32,
    ) -> windows::core::Result<()> {
        unsafe {
            if !pacpnext.is_null() {
                *pacpnext = acphalt;
            }
            if !pffound.is_null() {
                *pffound = BOOL(0);
            }
            if !plfoundoffset.is_null() {
                *plfoundoffset = 0;
            }
        }
        Ok(())
    }

    fn RetrieveRequestedAttrs(&self, _ulcount: u32, _paattrval: *mut TS_ATTRVAL, pcfetched: *mut u32) -> windows::core::Result<()> {
        if !pcfetched.is_null() {
            unsafe { *pcfetched = 0 };
        }
        Ok(())
    }

    fn GetEndACP(&self) -> windows::core::Result<i32> {
        self.st.need_lock(false)?;
        match view::tsf_host_text(0, u32::MAX) {
            Some((text, _, _)) => Ok(text.len() as i32),
            None => err(E_FAIL),
        }
    }

    fn GetActiveView(&self) -> windows::core::Result<u32> {
        Ok(VIEW_COOKIE)
    }

    fn GetACPFromPoint(&self, _vcview: u32, _ptscreen: *const windows::Win32::Foundation::POINT, _dwflags: u32) -> windows::core::Result<i32> {
        err(E_NOTIMPL)
    }

    fn GetTextExt(
        &self,
        _vcview: u32,
        acpstart: i32,
        acpend: i32,
        prc: *mut RECT,
        pfclipped: *mut BOOL,
    ) -> windows::core::Result<()> {
        self.st.need_lock(false)?;
        if prc.is_null() || pfclipped.is_null() {
            return err(E_INVALIDARG);
        }
        if acpstart < 0 || acpend < acpstart {
            return err(TS_E_INVALIDPOS);
        }
        let Some(r) = view::tsf_host_bounds(acpstart as u32, acpend as u32) else { return err(TS_E_NOLAYOUT) };
        let mut o = [0i32, 0];
        unsafe { ClientToScreen(self.st.hwnd_ptr(), &mut o) };
        let left = o[0] + r.x.floor() as i32;
        let top = o[1] + r.y.floor() as i32;
        let right = (o[0] as f32 + r.x + r.w).ceil() as i32;
        let bottom = (o[1] as f32 + r.y + r.h).ceil() as i32;
        let rc = RECT { left, top, right: right.max(left + 1), bottom: bottom.max(top + 1) };
        unsafe {
            *prc = rc;
            *pfclipped = BOOL(0);
        }
        tsf_log_capped!("tsf_get_text_ext acp={acpstart},{acpend} rect={},{},{},{}", rc.left, rc.top, rc.right, rc.bottom);
        Ok(())
    }

    fn GetScreenExt(&self, _vcview: u32) -> windows::core::Result<RECT> {
        let hwnd = self.st.hwnd_ptr();
        let mut rc = [0i32; 4];
        let mut o = [0i32, 0];
        unsafe {
            GetClientRect(hwnd, &mut rc);
            ClientToScreen(hwnd, &mut o);
        }
        Ok(RECT { left: o[0] + rc[0], top: o[1] + rc[1], right: o[0] + rc[2], bottom: o[1] + rc[3] })
    }

    fn GetWnd(&self, _vcview: u32) -> windows::core::Result<HWND> {
        Ok(HWND(self.st.hwnd_ptr()))
    }
}

#[allow(non_snake_case)]
impl ITfContextOwnerCompositionSink_Impl for TextStore_Impl {
    fn OnStartComposition(&self, _pcomposition: Ref<'_, ITfCompositionView>) -> windows::core::Result<BOOL> {
        self.st.composing.set(true);
        tsf_log!("tsf_composition event=start");
        view::tsf_caret_place();
        Ok(BOOL(1))
    }

    fn OnUpdateComposition(&self, _pcomposition: Ref<'_, ITfCompositionView>, _prangenew: Ref<'_, ITfRange>) -> windows::core::Result<()> {
        Ok(())
    }

    fn OnEndComposition(&self, _pcomposition: Ref<'_, ITfCompositionView>) -> windows::core::Result<()> {
        self.st.composing.set(false);
        // The marked text becomes committed text.
        let ok = view::tsf_host_marked().is_none() || view::tsf_host_unmark();
        if self.st.lock.get() != 0 {
            self.st.refresh_known();
        }
        tsf_log!("tsf_composition event=end unmark_ok={ok}");
        view::tsf_caret_destroy();
        Ok(())
    }
}

// ------------------------------------------------------------------------------------------------ candidate UI evidence

/// Thread-manager UI element sink. Shows every IME UI (pbShow stays TRUE) and, for a candidate list while the store owns the
/// window's input, writes the same `ime_cand` line the IMM path writes at IMN_OPENCANDIDATE / IMN_CHANGECANDIDATE.
#[implement(ITfUIElementSink)]
struct UiSink {
    st: Rc<State>,
}

impl UiSink {
    fn note(&self, id: u32, event: &str) {
        if !self.st.associated.get() {
            return;
        }
        let cand = UIMGR.with(|u| {
            let u = u.borrow();
            let mgr = u.as_ref()?;
            let el = unsafe { mgr.GetUIElement(id).ok()? };
            el.cast::<ITfCandidateListUIElement>().ok().map(|_| ())
        });
        tsf_log_capped!("tsf_ui_element event={event} id={id} candidate_list={}", cand.is_some());
        if cand.is_some() {
            self.st.cand_open.set(true);
        }
        if cand.is_some() {
            view::log_candidate_ui(self.st.hwnd_ptr(), event);
        }
    }
}

thread_local! {
    /// UI-less mode: id of the candidate list element being tracked, and its latest contents.
    static UILESS_ID: Cell<Option<u32>> = const { Cell::new(None) };
    static UILESS_STATE: RefCell<Option<CandState>> = const { RefCell::new(None) };
    /// Element id whose `ITfUIElement::IsShown()` must be re-checked at its first UpdateUIElement (after we answered pbShow=FALSE).
    static UILESS_RECHECK: Cell<Option<u32>> = const { Cell::new(None) };
    /// The re-check found the element still shown (the IME ignored pbShow=FALSE): our popup must not be drawn for it.
    static UILESS_IGNORED: Cell<bool> = const { Cell::new(false) };
    /// The active TIP CLSID has been logged once.
    static TIP_LOGGED: Cell<bool> = const { Cell::new(false) };
}

fn uiless_clear() {
    UILESS_ID.with(|t| t.set(None));
    UILESS_STATE.with(|s| *s.borrow_mut() = None);
    UILESS_RECHECK.with(|t| t.set(None));
    UILESS_IGNORED.with(|t| t.set(false));
}

/// Latest candidate list state captured in UI-less mode: (strings of the current page, capped at 9; selection index relative
/// to the first string of that page; page number). `None` when UI-less is off or no candidate list is open. UI thread only.
#[allow(dead_code)]
pub fn uiless_candidates() -> Option<(Vec<String>, usize, u32)> {
    if !uiless() {
        return None;
    }
    UILESS_STATE.with(|s| {
        s.borrow().as_ref().map(|c| (c.strings.clone(), c.selection.saturating_sub(c.first_on_page()), c.page))
    })
}

/// The latest candidate list state (UI-less mode, list open, not ignored). UI thread only.
#[allow(dead_code)]
pub fn cand_state() -> Option<CandState> {
    if !uiless() || UILESS_IGNORED.with(|t| t.get()) {
        return None;
    }
    UILESS_STATE.with(|s| s.borrow().clone())
}

/// True while a candidate list element is open in UI-less mode and the IME honoured pbShow=FALSE.
#[allow(dead_code)]
pub fn cand_open() -> bool {
    uiless() && !UILESS_IGNORED.with(|t| t.get()) && UILESS_ID.with(|t| t.get()).is_some()
}

/// True when the IME kept its own candidate list visible after we answered pbShow=FALSE (see `recheck_shown`): the popup must
/// not be drawn for that element. Reset when the element ends or a new one begins.
#[allow(dead_code)]
pub fn cand_ignored() -> bool {
    uiless() && UILESS_IGNORED.with(|t| t.get())
}

// ---- #45 step 3: glue between the UI element sink and the popup in view.rs (UI-less mode only)

/// Posts a window message (any thread). False when it could not be posted.
pub fn post_to_window(hwnd: *mut c_void, msg: u32, w: usize, l: isize) -> bool {
    !hwnd.is_null() && unsafe { PostMessageW(hwnd, msg, w, l) } != 0
}

/// Asks the render window to refresh the candidate popup. The sink callbacks run inside TIP calls and must not touch windows,
/// so they only post; one message in flight at a time.
pub fn post_cand_refresh(hwnd: *mut c_void) {
    if !uiless() || hwnd.is_null() {
        return;
    }
    if !CAND_PENDING.swap(true, SeqCst) && !post_to_window(hwnd, WM_SWR_CAND, 0, 0) {
        CAND_PENDING.store(false, SeqCst);
    }
}

/// WM_SWR_CAND handler entry (before the refresh): the next sink event may post again.
pub fn cand_message_taken() {
    CAND_PENDING.store(false, SeqCst);
}

/// SWIFTRIGHT_IME_UILESS_PICK=<row> (diagnostic): 2 s after the first BeginUIElement, once per process, posts a pick of that row.
fn arm_diagnostic_pick(hwnd: *mut c_void) {
    let Some(row) = std::env::var("SWIFTRIGHT_IME_UILESS_PICK").ok().and_then(|v| v.trim().parse::<usize>().ok()) else { return };
    if hwnd.is_null() || PICK_ARMED.swap(true, SeqCst) {
        return;
    }
    tsf_log!("tsf_cand pick_scheduled row={row} delay_ms=2000");
    let h = hwnd as usize;
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(2000));
        let ok = post_to_window(h as *mut c_void, WM_SWR_CAND_PICK, row, 0);
        tsf_log!("tsf_cand pick_posted row={row} ok={ok}");
    });
}

/// The tracked candidate list element as the behaviour interface (SetSelection / Finalize), plus the current state. The COM
/// object is cloned out so no thread-local borrow is held while the TIP runs.
fn cand_behavior() -> Option<(ITfCandidateListUIElementBehavior, CandState)> {
    let id = UILESS_ID.with(|t| t.get())?;
    let st = cand_state()?;
    let el = UIMGR.with(|u| {
        let u = u.borrow();
        let mgr = u.as_ref()?;
        unsafe { mgr.GetUIElement(id).ok() }
    })?;
    let b = el.cast::<ITfCandidateListUIElementBehavior>().ok()?;
    Some((b, st))
}

/// Mouse pick of `row` on the current page (WM_SWR_CAND_PICK, UI thread, top-level message): selects it and finalizes.
pub fn cand_pick(row: usize) {
    if !uiless() {
        return;
    }
    let Some((b, st)) = cand_behavior() else {
        tsf_log!("tsf_cand pick row={row} skipped=no_open_list");
        return;
    };
    if row >= st.rows() {
        tsf_log!("tsf_cand pick row={row} skipped=row_out_of_page rows={}", st.rows());
        return;
    }
    let index = st.first_on_page() + row;
    let set = unsafe { b.SetSelection(index as u32) };
    let set_hr = hr_of(&set);
    // Finalize() returned S_OK but left the Microsoft IME composition marked (Dell run click-a); the selection is set, so Enter commits it.
    let sent = send_enter();
    tsf_log!("tsf_cand pick row={row} index={index} set_hr=0x{set_hr:08X} enter_sent={sent}");
}

/// Wheel over the popup (WM_SWR_CAND_WHEEL): moves the selection by one page of rows (`dir` > 0 forward, < 0 back).
pub fn cand_wheel(dir: isize) {
    if !uiless() {
        return;
    }
    let Some((b, st)) = cand_behavior() else { return };
    let step = st.rows().max(1);
    let last = (st.count as usize).saturating_sub(1);
    let to = if dir > 0 { (st.selection + step).min(last) } else { st.selection.saturating_sub(step) };
    if to == st.selection {
        return;
    }
    let r = unsafe { b.SetSelection(to as u32) };
    tsf_log!("tsf_cand wheel dir={dir} from={} to={to} hr=0x{:08X}", st.selection, hr_of(&r));
}

/// Called from the first UpdateUIElement of an element we answered pbShow=FALSE for: `ITfUIElement::IsShown()` TRUE means the
/// IME ignored the request, so the system list is still visible and ours would double it.
fn recheck_shown(id: u32) {
    if UILESS_RECHECK.with(|t| t.get()) != Some(id) {
        return;
    }
    UILESS_RECHECK.with(|t| t.set(None));
    let el = UIMGR.with(|u| {
        let u = u.borrow();
        let mgr = u.as_ref()?;
        unsafe { mgr.GetUIElement(id).ok() }
    });
    let Some(el) = el else { return };
    match unsafe { el.IsShown() } {
        Ok(b) if b.0 != 0 => {
            tsf_log!("tsf_uiless_ignored id={id}");
            UILESS_IGNORED.with(|t| t.set(true));
        }
        Ok(_) => tsf_log!("tsf_uiless_hidden id={id}"),
        Err(e) => tsf_log!("tsf_uiless_isshown_failed id={id} hr=0x{:08X}", e.code().0 as u32),
    }
}

/// Mirror of TF_INPUTPROCESSORPROFILE (msctf.h). The crate gates the real struct (and GetActiveProfile) behind a feature
/// this crate does not enable, so the call goes through the vtable slot by hand.
#[repr(C)]
struct TipProfile {
    profile_type: u32,
    langid: u16,
    clsid: GUID,
    guid_profile: GUID,
    catid: GUID,
    hkl_substitute: isize,
    caps: u32,
    hkl: isize,
    flags: u32,
}

/// Logs the active keyboard TIP's CLSID once (ITfInputProcessorProfileMgr::GetActiveProfile, GUID_TFCAT_TIP_KEYBOARD).
fn log_active_tip_once() {
    if TIP_LOGGED.with(|t| t.replace(true)) {
        return;
    }
    let mgr: windows::core::Result<ITfInputProcessorProfileMgr> =
        unsafe { CoCreateInstance(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER) };
    let Ok(mgr) = mgr else {
        tsf_log!("tsf_active_tip skipped: profile manager unavailable");
        return;
    };
    type GetActiveProfileFn = unsafe extern "system" fn(*mut c_void, *const GUID, *mut TipProfile) -> HRESULT;
    // ITfInputProcessorProfileMgr vtable: IUnknown (0..=2), ActivateProfile 3, DeactivateProfile 4, GetProfile 5, EnumProfiles 6,
    // ReleaseInputProcessor 7, RegisterProfile 8, UnregisterProfile 9, GetActiveProfile 10.
    let mut prof: TipProfile = unsafe { std::mem::zeroed() };
    let hr = unsafe {
        let raw = Interface::as_raw(&mgr);
        let vtbl = *(raw as *const *const usize);
        let f: GetActiveProfileFn = std::mem::transmute(*vtbl.add(10));
        f(raw, &GUID_TFCAT_TIP_KEYBOARD, &mut prof)
    };
    if hr.is_ok() {
        let c = prof.clsid;
        tsf_log!(
            "tsf_active_tip clsid={{{:08X}-{:04X}-{:04X}-{:02X}{:02X}-{:02X}{:02X}{:02X}{:02X}{:02X}{:02X}}} langid=0x{:04X}",
            c.data1, c.data2, c.data3, c.data4[0], c.data4[1], c.data4[2], c.data4[3], c.data4[4], c.data4[5], c.data4[6],
            c.data4[7], prof.langid
        );
    } else {
        tsf_log!("tsf_active_tip skipped: GetActiveProfile hr=0x{:08X}", hr.0 as u32);
    }
}

/// Reads count / selection / page / the current page's strings (max 9) and logs them under `tsf_uiless <what>`.
fn uiless_read(cand: &ITfCandidateListUIElement, id: u32, what: &str) {
    let count = unsafe { cand.GetCount() }.unwrap_or(0);
    let sel = unsafe { cand.GetSelection() }.unwrap_or(0);
    let page = unsafe { cand.GetCurrentPage() }.unwrap_or(0);
    // Page start indices: first call (NULL, 0) returns the page count, second fills the array. Raw vtable call so the
    // optional-pointer shape of the generated wrapper cannot matter.
    let mut pages = 0u32;
    let hr1 = unsafe { (Interface::vtable(cand).GetPageIndex)(Interface::as_raw(cand), std::ptr::null_mut(), 0, &mut pages) };
    let mut starts: Vec<u32> = vec![0; pages as usize];
    let mut hr2 = HRESULT(0);
    if hr1.is_ok() && pages > 0 {
        hr2 = unsafe { (Interface::vtable(cand).GetPageIndex)(Interface::as_raw(cand), starts.as_mut_ptr(), pages, &mut pages) };
    }
    let (first, end) = if hr2.is_ok() && (page as usize) < starts.len() {
        let f = starts[page as usize];
        let e = starts.get(page as usize + 1).copied().unwrap_or(count);
        (f, e.min(count))
    } else {
        (0, count) // no page table: treat all candidates as one page
    };
    tsf_log!(
        "tsf_uiless {what} id={id} candidate_list=true count={count} selection={sel} page={page} pages={pages} first={first} end={end} page_hr=0x{:08X}/0x{:08X}",
        hr1.0 as u32,
        hr2.0 as u32
    );
    let mut out: Vec<String> = Vec::new();
    for i in first..end.min(first.saturating_add(9)) {
        let text = match unsafe { cand.GetString(i) } {
            Ok(b) => String::from_utf16_lossy(&b),
            Err(e) => format!("<err 0x{:08X}>", e.code().0 as u32),
        };
        tsf_log!("tsf_uiless cand i={i} text={text}");
        out.push(text);
    }
    let show_numbers = cand
        .cast::<ITfIntegratableCandidateListUIElement>()
        .ok()
        .and_then(|i| unsafe { i.ShowCandidateNumbers().ok() })
        .map_or(true, |b| b.0 != 0);
    UILESS_STATE.with(|s| {
        *s.borrow_mut() = Some(CandState {
            strings: out,
            selection: sel as usize,
            page,
            page_starts: if hr2.is_ok() { starts.clone() } else { Vec::new() },
            count,
            show_numbers,
        })
    });
}

impl UiSink {
    /// UI-less spike: `what` is begin / update. Returns true when `id` is a candidate list (and logs it).
    fn uiless_event(&self, id: u32, what: &str) -> bool {
        let el = UIMGR.with(|u| {
            let u = u.borrow();
            let mgr = u.as_ref()?;
            unsafe { mgr.GetUIElement(id).ok() }
        });
        let cand = el.and_then(|e| e.cast::<ITfCandidateListUIElement>().ok());
        match cand {
            Some(c) => {
                if what == "begin" || UILESS_ID.with(|t| t.get()) == Some(id) {
                    UILESS_ID.with(|t| t.set(Some(id)));
                    uiless_read(&c, id, what);
                }
                true
            }
            None => {
                tsf_log!("tsf_uiless {what} id={id} candidate_list=false");
                false
            }
        }
    }
}

#[allow(non_snake_case)]
impl ITfUIElementSink_Impl for UiSink_Impl {
    fn BeginUIElement(&self, dwuielementid: u32, pbshow: *mut BOOL) -> windows::core::Result<()> {
        if !pbshow.is_null() {
            unsafe { *pbshow = BOOL(1) };
        }
        self.note(dwuielementid, "open");
        if uiless() && self.st.associated.get() {
            UILESS_IGNORED.with(|t| t.set(false));
            log_active_tip_once();
            if self.uiless_event(dwuielementid, "begin") && !pbshow.is_null() {
                unsafe { *pbshow = BOOL(0) };
                // The IME may still show its own list: re-check IsShown() at the first UpdateUIElement.
                UILESS_RECHECK.with(|t| t.set(Some(dwuielementid)));
                arm_diagnostic_pick(self.st.hwnd_ptr());
            }
            post_cand_refresh(self.st.hwnd_ptr());
        }
        Ok(())
    }

    fn UpdateUIElement(&self, dwuielementid: u32) -> windows::core::Result<()> {
        self.note(dwuielementid, "change");
        if uiless() && UILESS_ID.with(|t| t.get()) == Some(dwuielementid) {
            recheck_shown(dwuielementid);
            self.uiless_event(dwuielementid, "update");
            post_cand_refresh(self.st.hwnd_ptr());
        }
        Ok(())
    }

    fn EndUIElement(&self, dwuielementid: u32) -> windows::core::Result<()> {
        tsf_log_capped!("tsf_ui_element event=end id={dwuielementid}");
        self.st.cand_open.set(false);
        if uiless() && UILESS_ID.with(|t| t.get()) == Some(dwuielementid) {
            tsf_log!("tsf_uiless end id={dwuielementid}");
            uiless_clear();
            post_cand_refresh(self.st.hwnd_ptr());
        }
        Ok(())
    }
}

// ------------------------------------------------------------------------------------------------ owner (UI thread)

/// The COM handles. Only `sync` and `teardown` touch it; everything the store callbacks need lives in `State`.
struct Tsf {
    tm: Option<ITfThreadMgr>,
    dm: Option<ITfDocumentMgr>,
    ctx: Option<ITfContext>,
    st: Rc<State>,
    hwnd: *mut c_void,
    com_balance: bool,
    /// ITfSource cookie of the UI element sink (candidate list open/update evidence), 0 when not advised.
    ui_cookie: u32,
}

thread_local! {
    /// The thread manager's UI element manager, read by the UI element sink (kept out of the sink to avoid a reference cycle).
    static UIMGR: RefCell<Option<ITfUIElementMgr>> = const { RefCell::new(None) };
    static TSF: RefCell<Option<Tsf>> = const { RefCell::new(None) };
    /// The state of the live store, readable by the notification entry points without touching the `TSF` borrow.
    static CUR: RefCell<Option<Rc<State>>> = const { RefCell::new(None) };
    /// Initialisation failed for this window: the IMM32 path stays as it was and nothing is retried.
    static FAILED: Cell<bool> = const { Cell::new(false) };
}

fn state() -> Option<Rc<State>> {
    CUR.with(|c| c.borrow().clone())
}

fn init(hwnd: *mut c_void) -> Result<Tsf, (&'static str, u32)> {
    let hr = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
    // S_OK / S_FALSE add a reference on this thread that needs a CoUninitialize; RPC_E_CHANGED_MODE adds none.
    let com_balance = hr == S_OK || hr == S_FALSE;
    let mut stage: &'static str = "threadmgr";
    let mut activated: Option<ITfThreadMgr> = None;
    let st = Rc::new(State::new(hwnd as isize));
    let built = (|| -> windows::core::Result<(ITfThreadMgr, ITfDocumentMgr, ITfContext)> {
        let tm: ITfThreadMgr = unsafe { CoCreateInstance(&CLSID_TF_ThreadMgr, None, CLSCTX_INPROC_SERVER)? };
        stage = "activate";
        let client = unsafe { tm.Activate()? };
        activated = Some(tm.clone());
        stage = "documentmgr";
        let dm = unsafe { tm.CreateDocumentMgr()? };
        stage = "context";
        let punk: IUnknown = TextStore { st: st.clone() }.into();
        let mut ctx: Option<ITfContext> = None;
        let mut ec = 0u32;
        unsafe { dm.CreateContext(client, 0, &punk, &mut ctx, &mut ec)? };
        let ctx = ctx.ok_or_else(|| windows::core::Error::from(E_FAIL))?;
        stage = "push";
        unsafe { dm.Push(&ctx)? };
        Ok((tm, dm, ctx))
    })();
    match built {
        Ok((tm, dm, ctx)) => {
            // Candidate list evidence: TSF IMEs report their candidate UI through ITfUIElementSink, not IMN_OPENCANDIDATE.
            let mut ui_cookie = 0u32;
            if let (Ok(src), Ok(mgr)) = (tm.cast::<ITfSource>(), tm.cast::<ITfUIElementMgr>()) {
                let sink: ITfUIElementSink = UiSink { st: st.clone() }.into();
                match unsafe { src.AdviseSink(&ITfUIElementSink::IID, &sink) } {
                    Ok(c) => {
                        ui_cookie = c;
                        UIMGR.with(|u| *u.borrow_mut() = Some(mgr));
                    }
                    Err(e) => tsf_log!("tsf_ui_sink_failed hr=0x{:08X}", e.code().0 as u32),
                }
            }
            Ok(Tsf { tm: Some(tm), dm: Some(dm), ctx: Some(ctx), st, hwnd, com_balance, ui_cookie })
        }
        Err(e) => {
            if let Some(t) = activated.take() {
                let _ = unsafe { t.Deactivate() };
            }
            *st.sink.borrow_mut() = None;
            drop(st);
            if com_balance {
                unsafe { CoUninitialize() };
            }
            Err((stage, e.code().0 as u32))
        }
    }
}

impl Tsf {
    /// Makes the store the window's input owner: TSF focus on our document manager (IMM context kept).
    fn associate(&mut self) {
        let (Some(tm), Some(dm)) = (&self.tm, &self.dm) else { return };
        let r = unsafe { tm.AssociateFocus(HWND(self.hwnd), dm) };
        let hr = match &r {
            Ok(_) => 0u32,
            Err(e) => e.code().0 as u32,
        };
        drop(r); // the previous document manager, Released
        let _ = unsafe { tm.SetFocus(dm) };
        // The IMM context stays: IMM open/conversion status (WM_IME_CONTROL, ImmGetOpenStatus) maps to the thread's TSF
        // compartments, which tools and the probe read. IMM composition messages are dropped in view.rs while associated.
        self.st.associated.set(true);
        tsf_log!("tsf_associate node={} hr=0x{hr:08X}", self.st.node.get());
    }

    fn dissociate(&mut self) {
        self.terminate_composition();
        if let Some(tm) = &self.tm {
            let r = unsafe { tm.AssociateFocus(HWND(self.hwnd), Option::<&ITfDocumentMgr>::None) };
            drop(r);
        }
        self.st.associated.set(false);
        if uiless() {
            uiless_clear();
            view::cand_hide();
        }
        view::tsf_caret_destroy();
        self.st.pending.set(0);
        self.st.known.set(Known::default());
        tsf_log!("tsf_dissociate");
    }

    fn terminate_composition(&mut self) {
        if !self.st.composing.get() {
            return;
        }
        if let Some(ctx) = &self.ctx {
            if let Ok(svc) = ctx.cast::<ITfContextOwnerCompositionServices>() {
                let r = unsafe { svc.TerminateComposition(Option::<&ITfCompositionView>::None) };
                tsf_log!("tsf_terminate_composition hr=0x{:08X}", hr_of(&r));
            }
        }
        self.st.composing.set(false);
        view::tsf_caret_destroy();
    }

    /// Releases every interface and balances COM. Idempotent.
    fn shutdown(&mut self) {
        if self.st.associated.get() {
            self.dissociate();
        }
        self.st.composing.set(false);
        if let Some(dm) = self.dm.take() {
            let _ = unsafe { dm.Pop(TF_POPF_ALL) };
            drop(dm);
        }
        // Pop makes TSF UnadviseSink; clear it ourselves as well so the store can be freed.
        *self.st.sink.borrow_mut() = None;
        self.st.mask.set(0);
        drop(self.ctx.take());
        UIMGR.with(|u| *u.borrow_mut() = None);
        uiless_clear();
        view::cand_hide();
        if self.ui_cookie != 0 {
            if let Some(src) = self.tm.as_ref().and_then(|t| t.cast::<ITfSource>().ok()) {
                let _ = unsafe { src.UnadviseSink(self.ui_cookie) };
            }
            self.ui_cookie = 0;
        }
        if let Some(tm) = self.tm.take() {
            let _ = unsafe { tm.Deactivate() };
            drop(tm);
        }
        if self.com_balance {
            self.com_balance = false;
            unsafe { CoUninitialize() };
        }
        tsf_log!("tsf_teardown");
    }
}

impl Drop for Tsf {
    fn drop(&mut self) {
        self.shutdown();
    }
}

// ------------------------------------------------------------------------------------------------ entry points (view.rs)

/// Paint-time hook (UI thread): follows the focused editable field. `node` is the IME target (0 = none). Creates the
/// thread manager / document manager / context lazily on the first focus, associates / dissociates the window, and tells
/// TSF about host-side text and selection changes made outside a TSF lock.
pub fn sync(hwnd: *mut c_void, node: u64) {
    if !enabled() || hwnd.is_null() || !on_ui_thread() || FAILED.with(|f| f.get()) {
        return;
    }
    let have = TSF.with(|t| t.borrow().is_some());
    if !have {
        if node == 0 {
            return;
        }
        match init(hwnd) {
            Ok(t) => {
                tsf_log!("tsf_ready hwnd=0x{:X}", hwnd as usize);
                CUR.with(|c| *c.borrow_mut() = Some(t.st.clone()));
                TSF.with(|s| *s.borrow_mut() = Some(t));
            }
            Err((stage, hr)) => {
                FAILED.with(|f| f.set(true));
                tsf_log!("tsf_init_failed stage={stage} hr=0x{hr:08X}");
                return;
            }
        }
    }
    TSF.with(|cell| {
        let Ok(mut guard) = cell.try_borrow_mut() else { return };
        let Some(t) = guard.as_mut() else { return };
        let st = t.st.clone();
        t.st.flush_pending();
        let prev = st.node.get();
        if node != prev {
            if prev != 0 && node != 0 {
                // Focus moved to another field: the composition belongs to the old one.
                t.terminate_composition();
            }
            st.node.set(node);
            st.known.set(Known::default());
            st.last_snap.set(0);
            if node == 0 {
                if st.associated.get() {
                    t.dissociate();
                }
            } else if !st.associated.get() {
                t.associate();
            } else {
                tsf_log!("tsf_focus_moved node={node}");
            }
            if node != 0 {
                st.refresh_known();
                if prev != 0 {
                    // The IME re-reads the new field's text, selection and layout.
                    let mask = st.mask.get();
                    if let Some(sink) = st.sink() {
                        if mask & TS_AS_TEXT_CHANGE != 0 {
                            let len = st.known.get().len as i32;
                            let ch = TS_TEXTCHANGE { acpStart: 0, acpOldEnd: len, acpNewEnd: len };
                            let _ = unsafe { sink.OnTextChange(TEXT_STORE_TEXT_CHANGE_FLAGS(0), &ch) };
                        }
                        if mask & TS_AS_SEL_CHANGE != 0 {
                            let _ = unsafe { sink.OnSelectionChange() };
                        }
                        if mask & TS_AS_LAYOUT_CHANGE != 0 {
                            let _ = unsafe { sink.OnLayoutChange(TS_LC_CHANGE, VIEW_COOKIE) };
                        }
                    }
                }
            }
            return;
        }
        if node == 0 || !st.associated.get() {
            return;
        }
        let snap = SNAPSHOT.load(SeqCst);
        if snap != st.last_snap.get() {
            if !host_active() {
                st.last_snap.set(snap);
                st.notify_host_changes();
            }
        }
    });
}

/// True while a text field has IME focus and the window input runs over the TSF store.
pub fn associated() -> bool {
    enabled() && state().map_or(false, |s| s.associated.get())
}

/// True between ITfContextOwnerCompositionSink::OnStartComposition and OnEndComposition.
pub fn composing() -> bool {
    enabled() && state().map_or(false, |s| s.composing.get())
}

/// The composing field moved (ime_replace_on_layout): the IME re-calls GetTextExt and moves its candidate list.
pub fn layout_changed() {
    if !enabled() {
        return;
    }
    let Some(st) = state() else { return };
    if !st.associated.get() || st.mask.get() & TS_AS_LAYOUT_CHANGE == 0 {
        return;
    }
    let Some(sink) = st.sink() else { return };
    // Chromium's order (ui/base/ime/win/tsf_text_store.cc SendOnLayoutChange): while a composition is active the selection change
    // is reported first, then the layout change.
    if st.composing.get() && st.mask.get() & TS_AS_SEL_CHANGE != 0 {
        let sc = unsafe { sink.OnSelectionChange() };
        tsf_log!("tsf_layout_selection_change hr=0x{:08X}", hr_of(&sc));
    }
    let r = unsafe { sink.OnLayoutChange(TS_LC_CHANGE, VIEW_COOKIE) };
    tsf_log!("tsf_layout_change view={VIEW_COOKIE} hr=0x{:08X}", hr_of(&r));
    // #33 experiment (SWIFTRIGHT_IME_FOLLOW_MODE=recreate): the Microsoft IME re-reads GetTextExt after TS_LC_CHANGE but keeps an
    // open candidate list in place (its UI element ends at once, so this keys on the composition); report the view destroyed and recreated so it rebuilds its UI at the new position.
    if st.composing.get() && std::env::var("SWIFTRIGHT_IME_FOLLOW_MODE").map_or(false, |m| m == "recreate") {
        let d = unsafe { sink.OnLayoutChange(TS_LC_DESTROY, VIEW_COOKIE) };
        let c = unsafe { sink.OnLayoutChange(TS_LC_CREATE, VIEW_COOKIE) };
        tsf_log!("tsf_layout_recreate destroy_hr=0x{:08X} create_hr=0x{:08X}", hr_of(&d), hr_of(&c));
    }
}

/// WM_SWR_TSF handler (UI thread, window subclass): grants a queued async lock request.
pub fn on_lock_message() {
    if !enabled() {
        return;
    }
    if let Some(st) = state() {
        st.flush_pending();
    }
}

/// WM_DESTROY (window subclass): dissociates, pops the context and releases every interface.
pub fn teardown(hwnd: *mut c_void) {
    let _ = hwnd;
    CUR.with(|c| *c.borrow_mut() = None);
    let t = TSF.with(|s| s.try_borrow_mut().ok().and_then(|mut g| g.take()));
    drop(t); // Tsf::drop -> shutdown
    FAILED.with(|f| f.set(false));
}

/// Types Enter into the focused window (the IME commits the selected candidate); returns how many events were injected.
fn send_enter() -> u32 {
    use windows::Win32::UI::Input::KeyboardAndMouse::{SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_RETURN};
    let key = |flags| INPUT { r#type: INPUT_KEYBOARD, Anonymous: INPUT_0 { ki: KEYBDINPUT { wVk: VIRTUAL_KEY(VK_RETURN.0), wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 } } };
    let inputs = [key(Default::default()), key(KEYEVENTF_KEYUP)];
    unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) }
}
