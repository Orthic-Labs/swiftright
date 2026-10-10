#ifdef _WIN32
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <oleauto.h>
#include <UIAutomationClient.h>
#include <string.h>
#include "CUIA.h"

static IUIAutomation *g_auto = NULL;
static IUIAutomationTreeWalker *g_walker = NULL;

static const int g_patterns[] = {
    UIA_InvokePatternId, UIA_SelectionPatternId, UIA_ValuePatternId, UIA_RangeValuePatternId, UIA_ScrollPatternId,
    UIA_ExpandCollapsePatternId, UIA_WindowPatternId, UIA_SelectionItemPatternId, UIA_TextPatternId,
    UIA_TogglePatternId, UIA_TransformPatternId, UIA_ScrollItemPatternId, UIA_LegacyIAccessiblePatternId,
    UIA_TextEditPatternId,
};
int32_t cuia_pattern_count(void) { return (int32_t)(sizeof(g_patterns) / sizeof(g_patterns[0])); }
int32_t cuia_pattern_id(int32_t i) { return g_patterns[i]; }

int32_t cuia_init(void) {
    if (g_auto) return 0;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);   // RPC_E_CHANGED_MODE is harmless
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HRESULT hr = CoCreateInstance(&CLSID_CUIAutomation, NULL, CLSCTX_INPROC_SERVER, &IID_IUIAutomation, (void **)&g_auto);
    if (FAILED(hr)) return (int32_t)hr;
    hr = IUIAutomation_get_RawViewWalker(g_auto, &g_walker);
    return FAILED(hr) ? (int32_t)hr : 0;
}

typedef struct { DWORD pid; HWND found; long long best; } find_ctx;
static BOOL CALLBACK enum_cb(HWND h, LPARAM lp) {
    find_ctx *c = (find_ctx *)lp;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (pid != c->pid || !IsWindowVisible(h) || GetWindow(h, GW_OWNER) != NULL) return TRUE;
    RECT r; GetWindowRect(h, &r);
    long long area = (long long)(r.right - r.left) * (long long)(r.bottom - r.top);
    if (area >= c->best) { c->best = area; c->found = h; }
    return TRUE;
}
void *cuia_find_window(uint32_t pid) {
    find_ctx c; c.pid = pid; c.found = NULL; c.best = -1;
    EnumWindows(enum_cb, (LPARAM)&c);
    return c.found;
}

uint32_t cuia_foreground_pid(void) {
    DWORD pid = 0;
    HWND f = GetForegroundWindow();
    if (f) GetWindowThreadProcessId(f, &pid);
    return pid;
}

cuia_bool cuia_activate(void *hwnd) {
    HWND h = (HWND)hwnd;
    if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
    SetForegroundWindow(h);
    if (GetForegroundWindow() == h) return 1;
    HWND f = GetForegroundWindow();
    DWORD ft = f ? GetWindowThreadProcessId(f, NULL) : 0;
    DWORD me = GetCurrentThreadId();
    if (ft && ft != me) AttachThreadInput(me, ft, TRUE);
    BringWindowToTop(h);
    SetForegroundWindow(h);
    if (ft && ft != me) AttachThreadInput(me, ft, FALSE);
    return GetForegroundWindow() == h;
}

int32_t cuia_dpi_for_window(void *hwnd) { return (int32_t)GetDpiForWindow((HWND)hwnd); }

int32_t cuia_set_client_dip(void *hwnd, int32_t width_dip, int32_t height_dip) {
    HWND h = (HWND)hwnd;
    double scale = (double)GetDpiForWindow(h) / 96.0;
    RECT wr, cr;
    if (!GetWindowRect(h, &wr) || !GetClientRect(h, &cr)) return 0;
    int frameW = (wr.right - wr.left) - (cr.right - cr.left);
    int frameH = (wr.bottom - wr.top) - (cr.bottom - cr.top);
    int cw = (int)(width_dip * scale + 0.5), ch = (int)(height_dip * scale + 0.5);
    return MoveWindow(h, wr.left, wr.top, cw + frameW, ch + frameH, TRUE) ? 1 : 0;
}

int32_t cuia_close_window(void *hwnd) { return PostMessageW((HWND)hwnd, WM_CLOSE, 0, 0) ? 1 : 0; }

uint32_t cuia_send_vk(uint16_t vk, int32_t key_up, int32_t extended) {
    INPUT in;
    ZeroMemory(&in, sizeof(in));
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.wScan = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    in.ki.dwFlags = (key_up ? KEYEVENTF_KEYUP : 0) | (extended ? KEYEVENTF_EXTENDEDKEY : 0);
    return SendInput(1, &in, sizeof(INPUT));
}

int32_t cuia_vk_for_char(uint16_t unit) {
    SHORT r = VkKeyScanW((WCHAR)unit);
    if (r == -1) return -1;
    return (int32_t)(uint16_t)r;
}

int32_t cuia_post_char(void *hwnd, uint16_t unit) {
    SHORT r = VkKeyScanW((WCHAR)unit);
    WORD scan = r == -1 ? 0 : (WORD)MapVirtualKeyW((UINT)(r & 0xFF), MAPVK_VK_TO_VSC);
    LPARAM down = (LPARAM)(1 | ((LPARAM)scan << 16));
    return PostMessageW((HWND)hwnd, WM_CHAR, (WPARAM)unit, down) ? 1 : 0;
}

int32_t cuia_element_from_window(void *hwnd, cuia_el *out) {
    IUIAutomationElement *e = NULL;
    HRESULT hr = IUIAutomation_ElementFromHandle(g_auto, (UIA_HWND)hwnd, &e);
    *out = e;
    return FAILED(hr) ? (int32_t)hr : 0;
}

cuia_el cuia_first_child(cuia_el el) {
    IUIAutomationElement *c = NULL;
    if (FAILED(IUIAutomationTreeWalker_GetFirstChildElement(g_walker, (IUIAutomationElement *)el, &c))) return NULL;
    return c;
}
cuia_el cuia_next_sibling(cuia_el el) {
    IUIAutomationElement *c = NULL;
    if (FAILED(IUIAutomationTreeWalker_GetNextSiblingElement(g_walker, (IUIAutomationElement *)el, &c))) return NULL;
    return c;
}
void cuia_release(cuia_el el) { if (el) IUIAutomationElement_Release((IUIAutomationElement *)el); }

static int32_t copy_bstr(BSTR b, uint16_t *buf, int32_t cap) {
    int32_t n = b ? (int32_t)SysStringLen(b) : 0;
    int32_t m = n < cap ? n : cap;
    if (m > 0) memcpy(buf, b, (size_t)m * sizeof(uint16_t));
    if (b) SysFreeString(b);
    return n;
}

int32_t cuia_string(cuia_el el, int32_t which, uint16_t *buf, int32_t cap) {
    IUIAutomationElement *e = (IUIAutomationElement *)el;
    BSTR b = NULL;
    HRESULT hr;
    switch (which) {
    case CUIA_AUTOMATION_ID: hr = IUIAutomationElement_get_CurrentAutomationId(e, &b); break;
    case CUIA_NAME: hr = IUIAutomationElement_get_CurrentName(e, &b); break;
    case CUIA_CLASS_NAME: hr = IUIAutomationElement_get_CurrentClassName(e, &b); break;
    case CUIA_VALUE: {
        IUIAutomationValuePattern *vp = NULL;
        hr = IUIAutomationElement_GetCurrentPatternAs(e, UIA_ValuePatternId, &IID_IUIAutomationValuePattern, (void **)&vp);
        if (FAILED(hr) || !vp) return -1;
        hr = IUIAutomationValuePattern_get_CurrentValue(vp, &b);
        IUIAutomationValuePattern_Release(vp);
        break;
    }
    default: return -1;
    }
    if (FAILED(hr)) return -1;
    return copy_bstr(b, buf, cap);
}

int32_t cuia_control_type(cuia_el el) {
    CONTROLTYPEID t = 0;
    IUIAutomationElement_get_CurrentControlType((IUIAutomationElement *)el, &t);
    return (int32_t)t;
}
cuia_bool cuia_has_focus(cuia_el el) {
    BOOL f = FALSE;
    IUIAutomationElement_get_CurrentHasKeyboardFocus((IUIAutomationElement *)el, &f);
    return f ? 1 : 0;
}
int32_t cuia_bounds(cuia_el el, int32_t o[4]) {
    RECT r;
    if (FAILED(IUIAutomationElement_get_CurrentBoundingRectangle((IUIAutomationElement *)el, &r))) return 1;
    o[0] = r.left; o[1] = r.top; o[2] = r.right; o[3] = r.bottom;
    return 0;
}
uint32_t cuia_pattern_mask(cuia_el el) {
    uint32_t m = 0;
    for (int i = 0; i < cuia_pattern_count(); i++) {
        IUnknown *u = NULL;
        if (SUCCEEDED(IUIAutomationElement_GetCurrentPattern((IUIAutomationElement *)el, g_patterns[i], &u)) && u) {
            m |= 1u << i;
            IUnknown_Release(u);
        }
    }
    return m;
}

int32_t cuia_set_focus(cuia_el el) { return (int32_t)IUIAutomationElement_SetFocus((IUIAutomationElement *)el); }

int32_t cuia_invoke(cuia_el el) {
    IUIAutomationInvokePattern *p = NULL;
    HRESULT hr = IUIAutomationElement_GetCurrentPatternAs((IUIAutomationElement *)el, UIA_InvokePatternId, &IID_IUIAutomationInvokePattern, (void **)&p);
    if (FAILED(hr) || !p) return FAILED(hr) ? (int32_t)hr : (int32_t)E_NOINTERFACE;
    hr = IUIAutomationInvokePattern_Invoke(p);
    IUIAutomationInvokePattern_Release(p);
    return (int32_t)hr;
}

int32_t cuia_set_value(cuia_el el, const uint16_t *units, int32_t count) {
    IUIAutomationValuePattern *p = NULL;
    HRESULT hr = IUIAutomationElement_GetCurrentPatternAs((IUIAutomationElement *)el, UIA_ValuePatternId, &IID_IUIAutomationValuePattern, (void **)&p);
    if (FAILED(hr) || !p) return FAILED(hr) ? (int32_t)hr : (int32_t)E_NOINTERFACE;
    BSTR b = SysAllocStringLen((const OLECHAR *)units, (UINT)count);
    hr = IUIAutomationValuePattern_SetValue(p, b);
    SysFreeString(b);
    IUIAutomationValuePattern_Release(p);
    return (int32_t)hr;
}

// ---- TextPattern ----

static int32_t range_text_len(IUIAutomationTextRange *r, uint16_t *buf, int32_t cap) {
    BSTR b = NULL;
    if (FAILED(IUIAutomationTextRange_GetText(r, -1, &b))) return 0;
    return copy_bstr(b, buf, cap);
}

static int range_rects(IUIAutomationTextRange *r, double *out, int cap) {
    SAFEARRAY *sa = NULL;
    if (FAILED(IUIAutomationTextRange_GetBoundingRectangles(r, &sa)) || !sa) return 0;
    LONG lo = 0, hi = -1;
    SafeArrayGetLBound(sa, 1, &lo);
    SafeArrayGetUBound(sa, 1, &hi);
    int n = (int)(hi - lo + 1);
    double *data = NULL;
    if (n > 0 && SUCCEEDED(SafeArrayAccessData(sa, (void **)&data))) {
        if (n > cap) n = cap;
        for (int i = 0; i < n; i++) out[i] = data[i];
        SafeArrayUnaccessData(sa);
    } else n = 0;
    SafeArrayDestroy(sa);
    return n;
}

static IUIAutomationTextPattern *text_pattern(cuia_el el) {
    IUIAutomationTextPattern *tp = NULL;
    if (FAILED(IUIAutomationElement_GetCurrentPatternAs((IUIAutomationElement *)el, UIA_TextPatternId, &IID_IUIAutomationTextPattern, (void **)&tp))) return NULL;
    return tp;
}

int32_t cuia_text_state(cuia_el el, int32_t *location, int32_t *length, uint16_t *sel_text, int32_t sel_cap,
                        int32_t *sel_text_len, double caret[4], int32_t *has_caret) {
    static uint16_t scratch[1 << 16];
    *has_caret = 0;
    IUIAutomationTextPattern *tp = text_pattern(el);
    if (!tp) return 1;
    int32_t rc = 1;
    IUIAutomationTextRangeArray *arr = NULL;
    IUIAutomationTextRange *sel = NULL, *doc = NULL, *pre = NULL, *one = NULL;
    HRESULT hr = IUIAutomationTextPattern_GetSelection(tp, &arr);
    int n = 0;
    if (FAILED(hr) || !arr) goto done;
    IUIAutomationTextRangeArray_get_Length(arr, &n);
    if (n < 1) goto done;
    if (FAILED(hr = IUIAutomationTextRangeArray_GetElement(arr, 0, &sel))) { rc = (int32_t)hr; goto done; }
    if (FAILED(hr = IUIAutomationTextPattern_get_DocumentRange(tp, &doc))) { rc = (int32_t)hr; goto done; }
    if (FAILED(hr = IUIAutomationTextRange_Clone(doc, &pre))) { rc = (int32_t)hr; goto done; }
    if (FAILED(hr = IUIAutomationTextRange_MoveEndpointByRange(pre, TextPatternRangeEndpoint_End, sel, TextPatternRangeEndpoint_Start))) { rc = (int32_t)hr; goto done; }
    *location = range_text_len(pre, scratch, (int32_t)(sizeof(scratch) / sizeof(scratch[0])));
    *sel_text_len = range_text_len(sel, sel_text, sel_cap);
    *length = *sel_text_len;

    if (SUCCEEDED(IUIAutomationTextRange_Clone(sel, &one))) {
        int moved = 0;
        double r[16];
        IUIAutomationTextRange_MoveEndpointByRange(one, TextPatternRangeEndpoint_End, sel, TextPatternRangeEndpoint_Start);   // collapse at start
        IUIAutomationTextRange_MoveEndpointByUnit(one, TextPatternRangeEndpoint_End, TextUnit_Character, 1, &moved);
        if (moved > 0) {
            if (range_rects(one, r, 16) >= 4) { caret[0] = r[0]; caret[1] = r[1]; caret[2] = 0; caret[3] = r[3]; *has_caret = 1; }
        } else {
            IUIAutomationTextRange_MoveEndpointByUnit(one, TextPatternRangeEndpoint_Start, TextUnit_Character, -1, &moved);
            if (moved != 0 && range_rects(one, r, 16) >= 4) { caret[0] = r[0] + r[2]; caret[1] = r[1]; caret[2] = 0; caret[3] = r[3]; *has_caret = 1; }
        }
    }
    rc = 0;
done:
    if (one) IUIAutomationTextRange_Release(one);
    if (pre) IUIAutomationTextRange_Release(pre);
    if (doc) IUIAutomationTextRange_Release(doc);
    if (sel) IUIAutomationTextRange_Release(sel);
    if (arr) IUIAutomationTextRangeArray_Release(arr);
    IUIAutomationTextPattern_Release(tp);
    return rc;
}

int32_t cuia_text_select(cuia_el el, int32_t location, int32_t length) {
    IUIAutomationTextPattern *tp = text_pattern(el);
    if (!tp) return (int32_t)E_NOINTERFACE;
    IUIAutomationTextRange *doc = NULL, *r = NULL;
    HRESULT hr = IUIAutomationTextPattern_get_DocumentRange(tp, &doc);
    if (SUCCEEDED(hr)) hr = IUIAutomationTextRange_Clone(doc, &r);
    int moved = 0;
    if (SUCCEEDED(hr)) hr = IUIAutomationTextRange_MoveEndpointByRange(r, TextPatternRangeEndpoint_End, r, TextPatternRangeEndpoint_Start);
    if (SUCCEEDED(hr) && location > 0) hr = IUIAutomationTextRange_Move(r, TextUnit_Character, location, &moved);
    if (SUCCEEDED(hr) && length > 0) hr = IUIAutomationTextRange_MoveEndpointByUnit(r, TextPatternRangeEndpoint_End, TextUnit_Character, length, &moved);
    if (SUCCEEDED(hr)) hr = IUIAutomationTextRange_Select(r);
    if (r) IUIAutomationTextRange_Release(r);
    if (doc) IUIAutomationTextRange_Release(doc);
    IUIAutomationTextPattern_Release(tp);
    return (int32_t)hr;
}

#endif
