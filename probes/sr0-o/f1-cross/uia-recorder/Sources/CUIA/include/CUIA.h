#ifndef CUIA_H
#define CUIA_H
// Flat C surface over UI Automation + SendInput. Deliberately includes NO Windows header:
// UIAutomationClient.h cannot be imported through a clang module next to Swift's WinSDK module
// (oleacc.h is non-modular and loses windef.h types), so every COM call lives in cuia.c.
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *cuia_el;          // owned IUIAutomationElement*; release with cuia_release
typedef int32_t cuia_bool;

// Process / window
int32_t cuia_init(void);                                   // CoInitializeEx + DPI per-monitor-v2 + CUIAutomation + RawViewWalker; 0 = ok else HRESULT
void *cuia_find_window(uint32_t pid);                      // largest visible unowned top-level HWND of pid, or NULL
uint32_t cuia_foreground_pid(void);
cuia_bool cuia_activate(void *hwnd);                       // bring to foreground; 1 when foreground afterwards
int32_t cuia_dpi_for_window(void *hwnd);
int32_t cuia_set_client_dip(void *hwnd, int32_t width_dip, int32_t height_dip);  // window-targeted resize (MoveWindow); 1 = ok
int32_t cuia_close_window(void *hwnd);                      // posts WM_CLOSE to that window only; 1 = posted

// Input (virtual keys only; no KEYEVENTF_UNICODE)
uint32_t cuia_send_vk(uint16_t vk, int32_t key_up, int32_t extended);
int32_t cuia_vk_for_char(uint16_t unit);
int32_t cuia_post_char(void *hwnd, uint16_t unit);         // window-targeted: WM_CHAR posted to that HWND only (never global input); 1 = posted                   // vk | shift_state << 8, or -1

// Elements
int32_t cuia_element_from_window(void *hwnd, cuia_el *out);  // 0 = ok else HRESULT
cuia_el cuia_first_child(cuia_el el);                        // RawView; NULL when none
cuia_el cuia_next_sibling(cuia_el el);
void cuia_release(cuia_el el);

// Properties. Strings are UTF-16 code units copied into buf (truncated to cap); return length, or -1 when unavailable.
enum { CUIA_AUTOMATION_ID = 0, CUIA_NAME = 1, CUIA_CLASS_NAME = 2, CUIA_VALUE = 3 };
int32_t cuia_string(cuia_el el, int32_t which, uint16_t *buf, int32_t cap);
int32_t cuia_control_type(cuia_el el);
cuia_bool cuia_has_focus(cuia_el el);
int32_t cuia_bounds(cuia_el el, int32_t out_ltrb[4]);       // physical px; 0 = ok
uint32_t cuia_pattern_mask(cuia_el el);                     // bit i set when pattern cuia_pattern_ids[i] is supported
int32_t cuia_pattern_count(void);
int32_t cuia_pattern_id(int32_t i);

// Actions
int32_t cuia_set_focus(cuia_el el);
int32_t cuia_invoke(cuia_el el);
int32_t cuia_set_value(cuia_el el, const uint16_t *units, int32_t count);

// TextPattern. Selection is UTF-16 location/length from document start; caret rect is
// [x, y, w, h] of the one-character range at the selection start (CONTRACT §5); at end of text it is the
// previous character's trailing edge with w = 0. Returns 0 = ok, 1 = no TextPattern/selection, else HRESULT.
int32_t cuia_text_state(cuia_el el, int32_t *location, int32_t *length, uint16_t *sel_text, int32_t sel_cap,
                        int32_t *sel_text_len, double caret[4], int32_t *has_caret);
int32_t cuia_text_select(cuia_el el, int32_t location, int32_t length);

#ifdef __cplusplus
}
#endif
#endif
