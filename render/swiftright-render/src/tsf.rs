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
use std::sync::atomic::{AtomicU32, Ordering::SeqCst};

use windows::core::{implement, Interface, Ref, BOOL, GUID, HRESULT, IUnknown, PCWSTR, PWSTR};
use windows::Win32::Foundation::{E_FAIL, E_INVALIDARG, E_NOTIMPL, E_UNEXPECTED, HWND, RECT, S_FALSE, S_OK};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, IDataObject, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED,
};
use windows::Win32::UI::TextServices::{
    CLSID_TF_ThreadMgr, ITextStoreACP, ITextStoreACPSink, ITextStoreACP_Impl, ITfCompositionView, ITfContext,
    ITfContextOwnerCompositionServices, ITfContextOwnerCompositionSink, ITfContextOwnerCompositionSink_Impl,
    ITfDocumentMgr, ITfRange, ITfThreadMgr, TEXT_STORE_LOCK_FLAGS, TEXT_STORE_TEXT_CHANGE_FLAGS, TS_ATTRVAL, TS_LC_CHANGE, TS_RUNINFO, TS_RT_PLAIN,
    TS_SELECTIONSTYLE, TS_SELECTION_ACP, TS_STATUS, TS_TEXTCHANGE, TS_AE_END, TS_AE_START,
};

use crate::rt::*;
use crate::view;

/// WM_APP + 0x5A3 (pace WM_SWR_PAINT is + 0x5A1, view WM_SWR_MODAL + 0x5A2): a queued async TSF lock request is ready to grant.
pub const WM_SWR_TSF: u32 = 0x8000 + 0x5A3;

// ---- constants spelled out (msctf.h) so the code does not depend on how the crate types them
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
}

thread_local! {
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
        Ok((tm, dm, ctx)) => Ok(Tsf { tm: Some(tm), dm: Some(dm), ctx: Some(ctx), st, hwnd, com_balance }),
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
    if hwnd.is_null() || !on_ui_thread() || FAILED.with(|f| f.get()) {
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
    state().map_or(false, |s| s.associated.get())
}

/// True between ITfContextOwnerCompositionSink::OnStartComposition and OnEndComposition.
pub fn composing() -> bool {
    state().map_or(false, |s| s.composing.get())
}

/// The composing field moved (ime_replace_on_layout): the IME re-calls GetTextExt and moves its candidate list.
pub fn layout_changed() {
    let Some(st) = state() else { return };
    if !st.associated.get() || st.mask.get() & TS_AS_LAYOUT_CHANGE == 0 {
        return;
    }
    let Some(sink) = st.sink() else { return };
    let r = unsafe { sink.OnLayoutChange(TS_LC_CHANGE, VIEW_COOKIE) };
    tsf_log!("tsf_layout_change view={VIEW_COOKIE} hr=0x{:08X}", hr_of(&r));
}

/// WM_SWR_TSF handler (UI thread, window subclass): grants a queued async lock request.
pub fn on_lock_message() {
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
