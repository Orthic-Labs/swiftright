//! `#[repr(C)]` mirrors of render/swiftright-abi/include/swiftright.h (ABI 0.6, 0.7, 0.8, 0.9 and 0.10).
//! Compile-time size asserts use the sizes measured with clang on the header.

use std::ffi::{c_char, c_void};

pub const ABI_MAJOR: u32 = 0;
pub const ABI_MINOR: u32 = 6;
pub const API_FN_COUNT: u32 = 16;
/// Rev 0.7 (additive): minor/function count reported ONLY by the `_v07` discovery exports.
pub const ABI_MINOR_V07: u32 = 7;
pub const API_V07_FN_COUNT: u32 = 18;
/// Rev 0.8 (additive): minor/function count reported ONLY by the `_v08` discovery exports.
pub const ABI_MINOR_V08: u32 = 8;
pub const API_V08_FN_COUNT: u32 = 22;
/// Rev 0.9 (additive): minor reported ONLY by the `_v09` discovery exports (the 0.8 function table is unchanged: 22 functions).
pub const ABI_MINOR_V09: u32 = 9;
/// Rev 0.10 (additive): minor reported ONLY by the `_v10` discovery exports (the 0.8 function table is unchanged: 22 functions).
pub const ABI_MINOR_V10: u32 = 10;
/// Rev 0.11 (additive): minor reported ONLY by the `_v11` discovery exports (the 0.8 function table is unchanged: 22 functions).
pub const ABI_MINOR_V11: u32 = 11;
/// Rev 0.12 (additive): minor reported ONLY by the `_v12` discovery exports (the 0.8 function table is unchanged: 22 functions).
pub const ABI_MINOR_V12: u32 = 12;
/// Rev 0.13 (additive): minor reported ONLY by the `_v13` discovery exports (the 0.8 function table is unchanged: 22 functions).
pub const ABI_MINOR_V13: u32 = 13;
/// Rev 0.14 (additive): minor reported ONLY by the `_v14` discovery exports (the 0.8 table + one function: 23 functions, 192 bytes).
pub const ABI_MINOR_V14: u32 = 14;
pub const API_V14_FN_COUNT: u32 = 23;
/// Rev 0.9: AccessKit Role::Slider (UIA Slider; RangeValuePattern when a range entry is sent).
pub const ROLE_SLIDER: u32 = 15;
/// Rev 0.11: AccessKit Role::ScrollBar (UIA ScrollBar; RangeValuePattern from a range entry, value 0..1).
pub const ROLE_SCROLL_BAR: u32 = 16;
/// Additive (#74): a link (UIA Hyperlink), e.g. a link run inside a Text.
pub const ROLE_LINK: u32 = 17;
pub const FEATURES_MAX: usize = 16;
pub const FALLBACKS_MAX: usize = 8;
pub const FACE_AXES_MAX: usize = 8;
pub const NAME_MAX: usize = 64;
pub const VERSION_MAX: usize = 32;
pub const SYSFONT_ENTRIES: usize = 8;
pub const SYSFONT_NAME_MAX: usize = 48;
pub const M08_BASELINE_OFFSET: u32 = 0x1;
/// Rev 0.12 (additive, same struct size): `swr_measure_request_v08.flags` bit 1; `reserved` then holds the maximum visual line
/// count (>= 1). Text past it ends in an ellipsis. A host that never sets the bit sees exactly the earlier behaviour.
pub const M08_MAX_LINES: u32 = 0x2;
pub const M08_APPLIED_MAX_LINES: u32 = 0x40;
pub const MAX_LINES_LIMIT: u32 = 1000;
pub const SIM_FORBID_BOLD: u32 = 0x1;
pub const SIM_FORBID_OBLIQUE: u32 = 0x2;
pub const M08_APPLIED_FEATURES: u32 = 0x01;
pub const M08_APPLIED_TRACKING: u32 = 0x02;
pub const M08_APPLIED_BASELINE: u32 = 0x04;
pub const M08_APPLIED_FALLBACKS: u32 = 0x08;
pub const M08_APPLIED_WEIGHT: u32 = 0x10;
pub const M08_APPLIED_ITALIC: u32 = 0x20;
pub const M08_IGN_WEIGHT_SNAPPED: u32 = 0x01;
pub const M08_IGN_WIDTH_AXIS: u32 = 0x02;
pub const M08_IGN_OPSZ: u32 = 0x04;
pub const M08_IGN_SLANT: u32 = 0x08;
pub const M08_IGN_FALLBACK_PRIVATE: u32 = 0x10;
pub const M08_IGN_SIM_BOLD_DROPPED: u32 = 0x20;
pub const M08_IGN_SIM_OBLIQUE_DROPPED: u32 = 0x40;
pub const SIMFLAG_BOLD: u32 = 0x1;
pub const SIMFLAG_OBLIQUE: u32 = 0x2;
pub const RUNFACE_PRIMARY: u32 = 0x01;
pub const RUNFACE_BUNDLED: u32 = 0x02;
pub const RUNFACE_SYSTEM: u32 = 0x04;
pub const RUNFACE_FALLBACK: u32 = 0x08;
pub const RUNFACE_UNRESOLVED: u32 = 0x10;
pub const RUNFACE_COLOR: u32 = 0x20;
pub const RUNFACE_SIM_BOLD: u32 = 0x40;
pub const RUNFACE_SIM_OBLIQUE: u32 = 0x80;
pub const FACE_FOUND: u32 = 0x1;
pub const FACE_VARIABLE: u32 = 0x2;
pub const FACE_BUNDLED: u32 = 0x4;
pub const STYLE_NORMAL: u32 = 0;
pub const STYLE_OBLIQUE: u32 = 1;
pub const STYLE_ITALIC: u32 = 2;
pub const SYSFONT_SEGOE_UI: u32 = 0x01;
pub const SYSFONT_SEGOE_VARIABLE: u32 = 0x02;
pub const SYSFONT_CASCADIA_MONO: u32 = 0x04;
pub const SYSFONT_SITKA: u32 = 0x08;
pub const SYSFONT_SEGOE_EMOJI: u32 = 0x10;
pub const SYSFONT_SEGOE_FLUENT_ICONS: u32 = 0x20;
pub const FONT_MAX_BYTES: u64 = 32 * 1024 * 1024;
pub const FONT_FAMILY_MAX: usize = 64;
pub const FONT_NEW: u32 = 0x1;
pub const FONT_DUPLICATE: u32 = 0x2;
pub const FONT_SYSTEM_FAMILY: u32 = 0x4;
pub const FONT_LATE: u32 = 0x8;
pub const FONT_SRC_FALLBACK: u32 = 0;
pub const FONT_SRC_BUNDLED: u32 = 1;
pub const FONT_SRC_SYSTEM: u32 = 2;

pub type Status = i32;
pub const SWR_EMPTY: Status = 1;
pub const SWR_OK: Status = 0;
pub const E_BAD_ARG: Status = -1;
pub const E_PANIC: Status = -2;
pub const E_NOT_READY: Status = -3;
pub const E_STATE: Status = -4;
pub const E_PLATFORM: Status = -5;
pub const E_STALE_HANDLE: Status = -6;
pub const E_QUEUE_FULL: Status = -7;
pub const E_TOO_LARGE: Status = -8;
pub const E_BUSY: Status = -9;
pub const E_WRONG_THREAD: Status = -10;
pub const E_STALE_VERSION: Status = -11;
pub const E_NOT_FOUND: Status = -12;
pub const E_SHUTDOWN: Status = -13;
pub const E_ABI: Status = -14;
pub const E_UNSUPPORTED: Status = -15;

pub const NODE_HIT_TARGET: u32 = 0x1;
pub const NODE_FOCUSABLE: u32 = 0x2;
pub const NODE_EDITABLE: u32 = 0x4;

pub const PRIM_RECT: u32 = 1;
pub const PRIM_TEXT_RUN: u32 = 2;
pub const PRIM_IMAGE: u32 = 3;
pub const PRIM_PATH: u32 = 4;
pub const PRIM_CLIP_PUSH: u32 = 5;
pub const PRIM_CLIP_POP: u32 = 6;
pub const PRIM_TRANSFORM_PUSH: u32 = 7;
pub const PRIM_TRANSFORM_POP: u32 = 8;
pub const PRIM_UNDERLINE: u32 = 9;

pub const ROLE_NONE: u32 = 0;
pub const ROLE_WINDOW: u32 = 1;
pub const ROLE_BUTTON: u32 = 2;
pub const ROLE_STATIC_TEXT: u32 = 3;
pub const ROLE_TEXT_FIELD: u32 = 4;
pub const ROLE_LIST: u32 = 5;
pub const ROLE_LIST_ITEM: u32 = 6;
pub const ROLE_GROUP: u32 = 7;
// Rev 0.6.
pub const ROLE_CHECKBOX: u32 = 8;
pub const ROLE_SWITCH: u32 = 9;
pub const ROLE_IMAGE: u32 = 10;
pub const ROLE_MENU: u32 = 11;
pub const ROLE_MENU_ITEM: u32 = 12;
pub const ROLE_ALERT: u32 = 13;
pub const ROLE_DIALOG: u32 = 14;

pub const ACT_INVOKE: u32 = 0x1;
pub const ACT_FOCUS: u32 = 0x2;
pub const ACT_SET_VALUE: u32 = 0x4;
pub const ACT_SET_SELECTION: u32 = 0x8;

pub const SEM_HAS_SELECTION: u32 = 0x1;
pub const SEM_MULTILINE: u32 = 0x2;
pub const SEM_DISABLED: u32 = 0x4;
// Rev 0.6.
pub const SEM_SELECTABLE: u32 = 0x8;
pub const SEM_SELECTED: u32 = 0x10;

pub const TOGGLED_NONE: u32 = 0;
pub const TOGGLED_OFF: u32 = 1;
pub const TOGGLED_ON: u32 = 2;
pub const TOGGLED_MIXED: u32 = 3;

pub const IMAGE_MAX_DIM: u32 = 8192;
pub const IMAGE_MAX_BYTES: u64 = 64 * 1024 * 1024;
pub const IMAGE_MAX_LIVE: usize = 4096;

pub const EV_KEY: u32 = 1;
pub const EV_POINTER: u32 = 2;
pub const EV_FOCUS: u32 = 3;
pub const EV_IME: u32 = 4;
pub const EV_AX_ACTION: u32 = 5;
pub const EV_MODAL_RESULT: u32 = 6;
pub const EV_WINDOW_METRICS: u32 = 7;

pub const KEY_DOWN: u32 = 1;
pub const KEY_UP: u32 = 2;
pub const PTR_DOWN: u32 = 1;
pub const PTR_UP: u32 = 2;
pub const PTR_MOVE: u32 = 3;
/// Rev 0.11 (issue #31): a wheel notch or precision-touchpad delta. Emitted only to a host that set `RUN_POINTER_WHEEL`.
pub const PTR_WHEEL: u32 = 4;
/// Rev 0.11: `swr_run_options.flags` bit 1. Only a host that sets it receives SWR_PTR_WHEEL events (and the renderer consumes
/// WM_MOUSEWHEEL / WM_MOUSEHWHEEL only for such a host).
pub const RUN_POINTER_WHEEL: u32 = 0x2;
/// WHEEL_DELTA: units per wheel notch.
pub const WHEEL_DELTA: i32 = 120;
/// Rev 0.9 (decision H3): `swr_run_options.flags` bit 0. Only a host that sets it receives SWR_PTR_MOVE events (hover and drag);
/// every earlier host (flags 0) sees exactly the events it saw before.
pub const RUN_POINTER_MOVES: u32 = 0x1;
/// SWR_PTR_MOVE `i0` bits (rev 0.9): the primary button is down; the pointer left the window (node 0, x = y = -1).
pub const PTR_I0_LEFT_DOWN: i32 = 0x1;
pub const PTR_I0_LEFT_WINDOW: i32 = 0x2;
pub const IME_MARK: u32 = 1;
pub const IME_COMMIT: u32 = 2;
pub const IME_UNMARK: u32 = 3;
pub const AX_INVOKE: u32 = 1;
pub const AX_FOCUS: u32 = 2;
pub const AX_SET_VALUE: u32 = 3;
pub const AX_SET_SELECTION: u32 = 4;

pub const MOD_CTRL: u32 = 0x1;
pub const MOD_ALT: u32 = 0x2;
pub const MOD_SHIFT: u32 = 0x4;
pub const MOD_PLATFORM: u32 = 0x8;
/// Rev 0.11: a wheel delta is not a multiple of WHEEL_DELTA (precision touchpad or high-resolution wheel).
pub const MOD_PRECISE: u32 = 0x100;

pub const EVENT_TEXT_CAP: usize = 64;

pub const IDENTIFIER_MAX: u32 = 256;

/// Post-close pump bound (rev 0.5).
pub const POST_CLOSE_TIMEOUT_MS: u64 = 5000;

pub const MODAL_MESSAGE: u32 = 1;
pub const MODAL_MENU: u32 = 2;
pub const MODAL_DIALOG: u32 = 3;
pub const MODAL_ITEM_DISABLED: u32 = 0x1;
pub const MODAL_ITEM_SEPARATOR: u32 = 0x2;
pub const MODAL_ITEM_CHECKED: u32 = 0x4;
pub const MODAL_ITEMS_MAX_MENU: u32 = 64;
pub const MODAL_ITEMS_MAX_DIALOG: u32 = 8;

pub const CELL_WORD_START: u32 = 0x1;
pub const CELL_LINE_BREAK: u32 = 0x2;

pub const MAX_UPSERTS: u32 = 4096;
pub const MAX_REMOVES: u32 = 4096;
pub const MAX_PRIMITIVES: u32 = 65536;
/// Rev 0.12 path table limits (per transaction). Larger -> E_TOO_LARGE.
pub const MAX_PATHS: u32 = 4096;
pub const MAX_PATH_CMDS: u32 = 1 << 20;
pub const MAX_PATH_PTS: u32 = 1 << 21;
/// Rev 0.12 path commands (one byte each) and PathEntry flags.
pub const PATH_CMD_MOVE: u8 = 0;
pub const PATH_CMD_LINE: u8 = 1;
pub const PATH_CMD_QUAD: u8 = 2;
pub const PATH_CMD_CUBIC: u8 = 3;
pub const PATH_CMD_CLOSE: u8 = 4;
pub const PATH_FLAG_EVEN_ODD: u32 = 0x1;

#[repr(C)]
#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Utf16Range {
    pub start: u32,
    pub end: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Utf16Selection {
    pub range: Utf16Range,
    pub reversed: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfo {
    pub struct_size: u32,
    pub abi_major: u32,
    pub abi_minor: u32,
    pub pointer_width: u32,
    pub arch: [u8; 16],
    pub host_callbacks_size: u32,
    pub api_table_size: u32,
    pub transaction_size: u32,
    pub node_size: u32,
    pub primitive_size: u32,
    pub semantic_size: u32,
    pub ax_text_run_size: u32,
    pub event_size: u32,
    pub measure_request_size: u32,
    pub measure_result_size: u32,
    pub line_info_size: u32,
    pub char_cell_size: u32,
    pub fn_count: u32,
    pub stats_size: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct HostCallbacks {
    pub struct_size: u32,
    pub reserved: u32,
    pub ctx: *mut c_void,
    pub loop_ready: Option<extern "C" fn(*mut c_void, u64)>,
    pub drain: Option<extern "C" fn(*mut c_void)>,
    pub events_available: Option<extern "C" fn(*mut c_void)>,
    pub tick: Option<extern "C" fn(*mut c_void, u64, u64)>,
    pub window_closed: Option<extern "C" fn(*mut c_void, u64)>,
    pub ime_get_selection:
        Option<extern "C" fn(*mut c_void, u64, u64, *mut Utf16Selection) -> Status>,
    pub ime_get_marked:
        Option<extern "C" fn(*mut c_void, u64, u64, *mut Utf16Range, *mut i32) -> Status>,
    pub ime_copy_text: Option<
        extern "C" fn(
            *mut c_void,
            u64,
            u64,
            Utf16Range,
            *mut u16,
            u32,
            *mut u32,
            *mut Utf16Range,
        ) -> Status,
    >,
    pub ime_replace:
        Option<extern "C" fn(*mut c_void, u64, u64, *const Utf16Range, *const u16, u32) -> Status>,
    pub ime_replace_and_mark: Option<
        extern "C" fn(
            *mut c_void,
            u64,
            u64,
            *const Utf16Range,
            *const u16,
            u32,
            *const Utf16Range,
        ) -> Status,
    >,
    pub ime_unmark: Option<extern "C" fn(*mut c_void, u64, u64) -> Status>,
    pub ime_caret_bounds:
        Option<extern "C" fn(*mut c_void, u64, u64, Utf16Range, *mut Rect) -> Status>,
}

#[repr(C)]
pub struct RunOptions {
    pub struct_size: u32,
    pub flags: u32,
    pub title: *const c_char,
    pub host_wake_handle: *mut c_void,
    pub title_len: u32,
    pub width_dip: u32,
    pub height_dip: u32,
    pub reserved: u32,
}

/// Rev 0.10 `swr_run_options_v10` (48 bytes): the 40-byte options at identical offsets + an explicit render scale. A host that
/// sends `struct_size >= 48` supplies it; a smaller struct has no override. `render_scale` 0 = none (the window's DPI decides).
#[repr(C)]
pub struct RunOptionsV10 {
    pub base: RunOptions,
    pub render_scale: f32,
    pub reserved: u32,
}

#[repr(C)]
pub struct WindowMetrics {
    pub struct_size: u32,
    pub width_px: u32,
    pub height_px: u32,
    pub scale: f32,
    pub active: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Primitive {
    pub kind: u32,
    pub color: u32,
    pub rect: Rect,
    pub border_color: u32,
    pub border_width: f32,
    pub radius: f32,
    pub image_id: u32,
    pub text_run: u64,
    pub m: [f32; 6],
    /// Rev 0.6, IMAGE: the former `reserved: [u32; 2]` (offset 72, 8 bytes).
    pub image: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct AxTextRun {
    pub id: u64,
    pub text: *const c_char,
    pub char_lengths: *const u8,
    pub char_positions: *const f32,
    pub char_widths: *const f32,
    pub word_starts: *const u8,
    pub bounds: Rect,
    pub text_len: u32,
    pub char_count: u32,
    pub word_start_count: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Semantic {
    pub label: *const c_char,
    pub value: *const c_char,
    pub runs: *const AxTextRun,
    pub sel_anchor_run: u64,
    pub sel_focus_run: u64,
    pub role: u32,
    pub actions: u32,
    pub flags: u32,
    pub label_len: u32,
    pub value_len: u32,
    pub run_count: u32,
    pub sel_anchor_char: u32,
    pub sel_focus_char: u32,
    pub identifier: *const c_char,
    pub identifier_len: u32,
    /// Rev 0.6: TOGGLED_*; the former `reserved`.
    pub toggled: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Node {
    pub id: u64,
    pub parent: u64,
    pub bounds: Rect,
    pub order: u32,
    pub flags: u32,
    pub prim_offset: u32,
    pub prim_count: u32,
    pub has_semantic: u32,
    pub reserved: u32,
    pub semantic: Semantic,
}

#[repr(C)]
pub struct Transaction {
    pub struct_size: u32,
    pub flags: u32,
    pub window: u64,
    pub version: u64,
    pub focus: u64,
    pub upserts: *const Node,
    pub removes: *const u64,
    pub primitives: *const Primitive,
    pub upsert_count: u32,
    pub remove_count: u32,
    pub primitive_count: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct LineInfo {
    pub utf8_start: u32,
    pub utf8_len: u32,
    pub width: f32,
    pub top: f32,
    pub baseline: f32,
    pub reserved: f32,
}

#[repr(C)]
pub struct MeasureRequest {
    pub struct_size: u32,
    pub flags: u32,
    pub text: *const c_char,
    pub font_family: *const c_char,
    pub locale: *const c_char,
    pub lines_out: *mut LineInfo,
    pub text_len: u32,
    pub font_family_len: u32,
    pub locale_len: u32,
    pub font_weight: u32,
    pub direction: u32,
    pub color: u32,
    pub font_size: f32,
    pub line_height: f32,
    pub scale: f32,
    pub max_width: f32,
    pub lines_cap: u32,
    pub reserved: u32,
}

#[repr(C)]
pub struct MeasureResult {
    pub struct_size: u32,
    pub cache_hit: u32,
    pub run: u64,
    pub width: f32,
    pub height: f32,
    pub first_baseline: f32,
    pub last_baseline: f32,
    pub line_count: u32,
    pub lines_written: u32,
    pub char_count: u32,
    pub reserved: u32,
    pub cache_key: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct CharCell {
    pub utf8_offset: u32,
    pub utf8_len: u32,
    pub line: u32,
    pub flags: u32,
    pub x0: f32,
    pub x1: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Event {
    pub kind: u32,
    pub action: u32,
    pub window: u64,
    pub node: u64,
    pub snapshot: u64,
    pub seq: u64,
    pub arg: u64,
    pub x: f32,
    pub y: f32,
    pub i0: i32,
    pub i1: i32,
    pub modifiers: u32,
    pub text_len: u32,
    pub text: [u8; EVENT_TEXT_CAP],
}

impl Event {
    pub fn new(kind: u32, action: u32) -> Event {
        Event {
            kind,
            action,
            window: 0,
            node: 0,
            snapshot: 0,
            seq: 0,
            arg: 0,
            x: 0.0,
            y: 0.0,
            i0: 0,
            i1: 0,
            modifiers: 0,
            text_len: 0,
            text: [0; EVENT_TEXT_CAP],
        }
    }
}

#[repr(C)]
pub struct ModalRequest {
    pub struct_size: u32,
    pub kind: u32,
    pub request_id: u64,
    pub title: *const c_char,
    pub message: *const c_char,
    pub title_len: u32,
    pub message_len: u32,
    pub buttons: u32,
    pub reserved: u32,
    // ---- rev 0.6 tail ----
    pub items: *const ModalItem,
    pub x: f32,
    pub y: f32,
    pub item_count: u32,
    pub flags: u32,
    pub default_item: u32,
    pub tail_reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ModalItem {
    pub text: *const c_char,
    pub text_len: u32,
    pub id: u32,
    pub flags: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Default)]
pub struct Stats {
    pub struct_size: u32,
    pub reserved: u32,
    pub drain_calls: u64,
    pub reentry_refused: u64,
    pub thread_violations: u64,
    pub host_panics: u64,
    pub wake_signals: u64,
    pub ticks_requested: u64,
    pub ticks_delivered: u64,
    pub paints: u64,
    pub commits_accepted: u64,
    pub commits_rejected: u64,
    pub commits_deferred: u64,
    pub measure_calls: u64,
    pub measure_cache_hits: u64,
    pub events_pushed: u64,
    pub events_dropped_full: u64,
    pub events_dropped_stale: u64,
    pub ax_actions_enqueued: u64,
    pub ax_actions_rejected: u64,
    pub ime_calls: u64,
    pub ime_busy_rejected: u64,
    pub selftest_reentry_detected: u64,
    pub live_nodes: u64,
    pub post_close_drains: u64,
    pub post_close_timeouts: u64,
}

#[repr(C)]
pub struct Api {
    pub struct_size: u32,
    pub reserved: u32,
    pub run: extern "C" fn(*const RunOptions, *const HostCallbacks) -> Status,
    pub request_quit: extern "C" fn() -> Status,
    pub window_request_close: extern "C" fn(u64) -> Status,
    pub window_get_metrics: extern "C" fn(u64, *mut WindowMetrics) -> Status,
    pub commit: extern "C" fn(*const Transaction) -> Status,
    pub measure_text: extern "C" fn(*const MeasureRequest, *mut MeasureResult) -> Status,
    pub text_run_cells: extern "C" fn(u64, *mut CharCell, u32, *mut u32) -> Status,
    pub text_run_release: extern "C" fn(u64) -> Status,
    pub event_pop: extern "C" fn(*mut Event) -> Status,
    pub request_ticks: extern "C" fn(u64, i32) -> Status,
    pub request_modal: extern "C" fn(u64, *const ModalRequest) -> Status,
    pub selftest_reentry: extern "C" fn() -> Status,
    pub get_stats: extern "C" fn(*mut Stats) -> Status,
    pub shutdown_complete: extern "C" fn() -> Status,
    // Rev 0.6, appended.
    pub image_register: extern "C" fn(*const u8, u32, u32, u32, *mut u64) -> Status,
    pub image_release: extern "C" fn(u64) -> Status,
}

/// Rev 0.7 `swr_font_info` (128 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FontInfo {
    pub struct_size: u32,
    pub flags: u32,
    pub font: u64,
    pub family_len: u32,
    pub weight: u32,
    pub face_count: u32,
    pub reserved: u32,
    pub sha256: [u8; 32],
    pub family: [u8; FONT_FAMILY_MAX],
}

/// Rev 0.7 `swr_font_resolution` (48 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FontResolution {
    pub struct_size: u32,
    pub source: u32,
    pub font: u64,
    pub sha256: [u8; 32],
}

/// Rev 0.7 `swr_bootstrap_info_v07` (96 bytes): the 0.6 fields at identical offsets + 2 size words.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV07 {
    pub base: BootstrapInfo,
    pub font_info_size: u32,
    pub font_resolution_size: u32,
}

/// Rev 0.7 `swr_api_v07` (152 bytes): the 16 pointers of `Api` at unchanged offsets + font entries.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ApiV07 {
    pub struct_size: u32,
    pub reserved: u32,
    pub run: extern "C" fn(*const RunOptions, *const HostCallbacks) -> Status,
    pub request_quit: extern "C" fn() -> Status,
    pub window_request_close: extern "C" fn(u64) -> Status,
    pub window_get_metrics: extern "C" fn(u64, *mut WindowMetrics) -> Status,
    pub commit: extern "C" fn(*const Transaction) -> Status,
    pub measure_text: extern "C" fn(*const MeasureRequest, *mut MeasureResult) -> Status,
    pub text_run_cells: extern "C" fn(u64, *mut CharCell, u32, *mut u32) -> Status,
    pub text_run_release: extern "C" fn(u64) -> Status,
    pub event_pop: extern "C" fn(*mut Event) -> Status,
    pub request_ticks: extern "C" fn(u64, i32) -> Status,
    pub request_modal: extern "C" fn(u64, *const ModalRequest) -> Status,
    pub selftest_reentry: extern "C" fn() -> Status,
    pub get_stats: extern "C" fn(*mut Stats) -> Status,
    pub shutdown_complete: extern "C" fn() -> Status,
    pub image_register: extern "C" fn(*const u8, u32, u32, u32, *mut u64) -> Status,
    pub image_release: extern "C" fn(u64) -> Status,
    // Rev 0.7, appended.
    pub font_register: extern "C" fn(*const u8, u64, *mut FontInfo) -> Status,
    pub font_resolve: extern "C" fn(*const u8, u32, *mut FontResolution) -> Status,
}

/// Rev 0.8 `swr_feature` (8 bytes).
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Feature {
    pub tag: u32,
    pub value: u32,
}

/// Rev 0.8 `swr_str` (16 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Str {
    pub ptr: *const c_char,
    pub len: u32,
    pub reserved: u32,
}

/// Rev 0.8 `swr_measure_request_v08` (160 bytes): the whole 0.6 request at offset 8, then the extension.
#[repr(C)]
pub struct MeasureRequestV08 {
    pub struct_size: u32,
    pub flags: u32,
    pub base: MeasureRequest,
    pub weight_f: f32,
    pub width_axis: f32,
    pub opsz: f32,
    pub slant: f32,
    pub tracking_dip: f32,
    pub kerning_dip: f32,
    pub baseline_offset_dip: f32,
    pub italic: u32,
    pub simulations: u32,
    pub feature_count: u32,
    pub features: *const Feature,
    pub fallbacks: *const Str,
    pub fallback_count: u32,
    pub reserved: u32,
}

/// Rev 0.8 `swr_measure_result_v08` (88 bytes).
#[repr(C)]
pub struct MeasureResultV08 {
    pub struct_size: u32,
    pub reserved0: u32,
    pub base: MeasureResult,
    pub applied: u32,
    pub ignored: u32,
    pub resolved_weight: f32,
    pub resolved_italic: u32,
    pub simulations: u32,
    pub reserved: u32,
}

/// Rev 0.8 `swr_run_face` (296 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct RunFace {
    pub utf8_start: u32,
    pub utf8_len: u32,
    pub glyph_count: u32,
    pub notdef_count: u32,
    pub flags: u32,
    pub weight: u32,
    pub ascent: f32,
    pub descent: f32,
    pub advance: f32,
    pub reserved: u32,
    pub sha256: [u8; 32],
    pub family: [u8; NAME_MAX],
    pub ps_name: [u8; NAME_MAX],
    pub version: [u8; VERSION_MAX],
    pub file_name: [u8; NAME_MAX],
}

impl RunFace {
    pub fn zeroed() -> RunFace {
        RunFace {
            utf8_start: 0,
            utf8_len: 0,
            glyph_count: 0,
            notdef_count: 0,
            flags: 0,
            weight: 0,
            ascent: 0.0,
            descent: 0.0,
            advance: 0.0,
            reserved: 0,
            sha256: [0; 32],
            family: [0; NAME_MAX],
            ps_name: [0; NAME_MAX],
            version: [0; VERSION_MAX],
            file_name: [0; NAME_MAX],
        }
    }
}

/// Rev 0.8 `swr_axis_range` (16 bytes).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct AxisRange {
    pub tag: u32,
    pub min_value: f32,
    pub max_value: f32,
    pub default_value: f32,
}

/// Rev 0.8 `swr_face_metrics` (456 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FaceMetrics {
    pub struct_size: u32,
    pub flags: u32,
    pub weight: u32,
    pub style: u32,
    pub simulations: u32,
    pub source: u32,
    pub units_per_em: i32,
    pub hhea_ascent: i32,
    pub hhea_descent: i32,
    pub hhea_line_gap: i32,
    pub typo_ascent: i32,
    pub typo_descent: i32,
    pub typo_line_gap: i32,
    pub win_ascent: i32,
    pub win_descent: i32,
    pub cap_height: i32,
    pub x_height: i32,
    pub axis_count: u32,
    pub axes: [AxisRange; FACE_AXES_MAX],
    pub sha256: [u8; 32],
    pub family: [u8; NAME_MAX],
    pub ps_name: [u8; NAME_MAX],
    pub version: [u8; VERSION_MAX],
    pub file_name: [u8; NAME_MAX],
}

/// Rev 0.8 `swr_system_font_entry` (88 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SystemFontEntry {
    pub name: [u8; SYSFONT_NAME_MAX],
    pub version: [u8; VERSION_MAX],
    pub present: u32,
    pub face_count: u32,
}

/// Rev 0.8 `swr_system_fonts` (720 bytes).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SystemFonts {
    pub struct_size: u32,
    pub flags: u32,
    pub family_count: u32,
    pub reserved: u32,
    pub entries: [SystemFontEntry; SYSFONT_ENTRIES],
}

/// Rev 0.8 `swr_bootstrap_info_v08` (120 bytes): the 0.7 view at identical offsets + 0.8 size words.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV08 {
    pub v07: BootstrapInfoV07,
    pub measure_request_v08_size: u32,
    pub measure_result_v08_size: u32,
    pub run_face_size: u32,
    pub face_metrics_size: u32,
    pub system_fonts_size: u32,
    pub reserved: u32,
}

/// Rev 0.9 `swr_range_entry` (56 bytes): the numeric range of one slider node of the same transaction.
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct RangeEntry {
    pub id: u64,
    pub value: f64,
    pub min: f64,
    pub max: f64,
    /// UIA SmallChange (AccessKit numeric_value_step).
    pub step: f64,
    /// UIA LargeChange (AccessKit numeric_value_jump).
    pub jump: f64,
    pub flags: u32,
    pub reserved: u32,
}

/// Rev 0.9 `swr_transaction_v09` (88 bytes): the 72-byte transaction at identical offsets + the range table. A host that sends
/// `struct_size >= 88` supplies it; a smaller transaction has no ranges.
#[repr(C)]
pub struct TransactionV09 {
    pub base: Transaction,
    pub ranges: *const RangeEntry,
    pub range_count: u32,
    pub reserved: u32,
}

/// Rev 0.9 `swr_bootstrap_info_v09` (128 bytes): the 0.8 view at identical offsets (abi_minor 9) + two size words.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV09 {
    pub v08: BootstrapInfoV08,
    pub range_entry_size: u32,
    pub transaction_v09_size: u32,
}

/// Rev 0.10 `swr_bootstrap_info_v10` (136 bytes): the 0.9 view at identical offsets (abi_minor 10) + the options size word.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV10 {
    pub v09: BootstrapInfoV09,
    pub run_options_v10_size: u32,
    pub reserved: u32,
}

/// Rev 0.11 `swr_bootstrap_info_v11` (144 bytes): the 0.10 view at identical offsets (abi_minor 11) + the wheel delta word.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV11 {
    pub v10: BootstrapInfoV10,
    pub wheel_delta: u32,
    pub reserved: u32,
}

/// Rev 0.12 `swr_bootstrap_info_v12` (152 bytes): the 0.11 view at identical offsets (abi_minor 12) + the path table sizes.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV12 {
    pub v11: BootstrapInfoV11,
    pub path_entry_size: u32,
    pub transaction_v12_size: u32,
}

/// Rev 0.13 `swr_bootstrap_info_v13` (160 bytes): the 0.12 view at identical offsets (abi_minor 13) + the accessibility extras sizes.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV13 {
    pub v12: BootstrapInfoV12,
    pub ax_extra_entry_size: u32,
    pub transaction_v13_size: u32,
}

/// Rev 0.14 `swr_bootstrap_info_v14` (168 bytes): the 0.13 view at identical offsets (abi_minor 14, api_table_size 192, fn_count 23)
/// + the capability word (`CAP_*`).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct BootstrapInfoV14 {
    pub v13: BootstrapInfoV13,
    pub caps: u32,
    pub reserved: u32,
}

/// Rev 0.14 `swr_bootstrap_info_v14.caps`: `swr_text_run_outline` is exported and returns glyph outlines (supportsTextOutlines).
pub const CAP_TEXT_OUTLINE: u32 = 0x1;

/// Rev 0.14 `swr_api_v14` (192 bytes): the 184 bytes of `ApiV08` at unchanged offsets + `text_run_outline`.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ApiV14 {
    pub v08: ApiV08,
    pub text_run_outline: extern "C" fn(u64, *mut u8, u32, *mut f32, u32, *mut u32, *mut u32) -> Status,
}

/// Rev 0.13 limits of the accessibility extras table (per transaction / per string, in bytes). Larger -> E_TOO_LARGE.
pub const MAX_AX_EXTRAS: u32 = 4096;
pub const AX_EXTRA_STR_MAX: u32 = 4096;
/// Rev 0.13 `swr_ax_extra_entry.flags`: SwiftUI `isHeader` (AccessKit Role::Heading) and `isLink` (Role::Link).
pub const AXE_HEADER: u32 = 0x1;
pub const AXE_LINK: u32 = 0x2;
pub const AXE_KNOWN: u32 = AXE_HEADER | AXE_LINK;

/// Rev 0.13 `swr_ax_extra_entry` (64 bytes): accessibility properties of one semantic node upserted by the same transaction.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AxExtraEntry {
    pub id: u64,
    /// SwiftUI accessibilityHint: UIA HelpText (and FullDescription when `description` is empty).
    pub help: Str,
    /// SwiftUI accessibilityValue: UIA Value pattern (a static text cannot carry one: see ax.rs).
    pub value: Str,
    pub description: Str,
    pub flags: u32,
    /// 0 = unset (2 when AXE_HEADER); 1..=6 only with AXE_HEADER.
    pub heading_level: u32,
}

/// Rev 0.13 `swr_transaction_v13` (144 bytes): the 128 bytes of `TransactionV12` + the extras table. `struct_size >= 144` supplies it.
#[repr(C)]
pub struct TransactionV13 {
    pub base: TransactionV12,
    pub extras: *const AxExtraEntry,
    pub extra_count: u32,
    pub reserved: u32,
}

/// Rev 0.12 `swr_path_entry` (32 bytes): one path of the transaction's path table. `cmd_offset`/`cmd_count` index the command byte
/// array, `pt_offset`/`pt_count` index the point array (x, y float pairs, so `pt_offset` counts points, not floats).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct PathEntry {
    pub cmd_offset: u32,
    pub cmd_count: u32,
    pub pt_offset: u32,
    pub pt_count: u32,
    /// PATH_FLAG_*; stroke cap in bits 1..2 (0 butt, 1 round, 2 square), stroke join in bits 3..4 (0 miter, 1 round, 2 bevel).
    pub flags: u32,
    /// Stroke miter limit; 0 = 4.
    pub miter_limit: f32,
    pub reserved: [u32; 2],
}

/// Rev 0.12 `swr_transaction_v12` (128 bytes): the 88 bytes of `TransactionV09` + the path table. `struct_size >= 128` supplies it.
#[repr(C)]
pub struct TransactionV12 {
    pub base: TransactionV09,
    pub paths: *const PathEntry,
    pub path_cmds: *const u8,
    pub path_pts: *const f32,
    pub path_count: u32,
    pub path_cmd_total: u32,
    pub path_pt_total: u32,
    pub reserved: u32,
}

/// Rev 0.8 `swr_api_v08` (184 bytes): the 18 pointers of `ApiV07` at unchanged offsets + the 0.8 entries.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ApiV08 {
    pub struct_size: u32,
    pub reserved: u32,
    pub run: extern "C" fn(*const RunOptions, *const HostCallbacks) -> Status,
    pub request_quit: extern "C" fn() -> Status,
    pub window_request_close: extern "C" fn(u64) -> Status,
    pub window_get_metrics: extern "C" fn(u64, *mut WindowMetrics) -> Status,
    pub commit: extern "C" fn(*const Transaction) -> Status,
    pub measure_text: extern "C" fn(*const MeasureRequest, *mut MeasureResult) -> Status,
    pub text_run_cells: extern "C" fn(u64, *mut CharCell, u32, *mut u32) -> Status,
    pub text_run_release: extern "C" fn(u64) -> Status,
    pub event_pop: extern "C" fn(*mut Event) -> Status,
    pub request_ticks: extern "C" fn(u64, i32) -> Status,
    pub request_modal: extern "C" fn(u64, *const ModalRequest) -> Status,
    pub selftest_reentry: extern "C" fn() -> Status,
    pub get_stats: extern "C" fn(*mut Stats) -> Status,
    pub shutdown_complete: extern "C" fn() -> Status,
    pub image_register: extern "C" fn(*const u8, u32, u32, u32, *mut u64) -> Status,
    pub image_release: extern "C" fn(u64) -> Status,
    pub font_register: extern "C" fn(*const u8, u64, *mut FontInfo) -> Status,
    pub font_resolve: extern "C" fn(*const u8, u32, *mut FontResolution) -> Status,
    // Rev 0.8, appended.
    pub measure_text_v08: extern "C" fn(*const MeasureRequestV08, *mut MeasureResultV08) -> Status,
    pub text_run_faces: extern "C" fn(u64, *mut RunFace, u32, *mut u32) -> Status,
    pub font_face_metrics: extern "C" fn(*const u8, u32, u32, u32, u32, *mut FaceMetrics) -> Status,
    pub system_font_info: extern "C" fn(*mut SystemFonts) -> Status,
}

/// The tag packing used by `swr_feature.tag`, for tests.
pub const fn tag(a: u8, b: u8, c: u8, d: u8) -> u32 {
    ((a as u32) << 24) | ((b as u32) << 16) | ((c as u32) << 8) | d as u32
}

// Sizes measured with clang on swiftright.h (x86_64 / arm64 agree).
// Rev 0.8: the same numbers as factory/abi/abi-0.8-layout-mock.c and the Swift TextExtensionTests.
const _: () = assert!(std::mem::size_of::<Feature>() == 8);
const _: () = assert!(std::mem::size_of::<Str>() == 16);
const _: () = assert!(std::mem::size_of::<MeasureRequestV08>() == 160);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, base) == 8);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, weight_f) == 96);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, width_axis) == 100);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, opsz) == 104);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, slant) == 108);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, tracking_dip) == 112);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, kerning_dip) == 116);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, baseline_offset_dip) == 120);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, italic) == 124);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, simulations) == 128);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, feature_count) == 132);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, features) == 136);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, fallbacks) == 144);
const _: () = assert!(std::mem::offset_of!(MeasureRequestV08, fallback_count) == 152);
const _: () = assert!(std::mem::size_of::<MeasureResultV08>() == 88);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, base) == 8);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, applied) == 64);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, ignored) == 68);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, resolved_weight) == 72);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, resolved_italic) == 76);
const _: () = assert!(std::mem::offset_of!(MeasureResultV08, simulations) == 80);
const _: () = assert!(std::mem::size_of::<RunFace>() == 296);
const _: () = assert!(std::mem::offset_of!(RunFace, glyph_count) == 8);
const _: () = assert!(std::mem::offset_of!(RunFace, notdef_count) == 12);
const _: () = assert!(std::mem::offset_of!(RunFace, flags) == 16);
const _: () = assert!(std::mem::offset_of!(RunFace, weight) == 20);
const _: () = assert!(std::mem::offset_of!(RunFace, ascent) == 24);
const _: () = assert!(std::mem::offset_of!(RunFace, advance) == 32);
const _: () = assert!(std::mem::offset_of!(RunFace, sha256) == 40);
const _: () = assert!(std::mem::offset_of!(RunFace, family) == 72);
const _: () = assert!(std::mem::offset_of!(RunFace, ps_name) == 136);
const _: () = assert!(std::mem::offset_of!(RunFace, version) == 200);
const _: () = assert!(std::mem::offset_of!(RunFace, file_name) == 232);
const _: () = assert!(std::mem::size_of::<AxisRange>() == 16);
const _: () = assert!(std::mem::size_of::<FaceMetrics>() == 456);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, weight) == 8);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, units_per_em) == 24);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, hhea_ascent) == 28);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, cap_height) == 60);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, x_height) == 64);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, axis_count) == 68);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, axes) == 72);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, sha256) == 200);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, family) == 232);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, ps_name) == 296);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, version) == 360);
const _: () = assert!(std::mem::offset_of!(FaceMetrics, file_name) == 392);
const _: () = assert!(std::mem::size_of::<SystemFontEntry>() == 88);
const _: () = assert!(std::mem::offset_of!(SystemFontEntry, version) == 48);
const _: () = assert!(std::mem::offset_of!(SystemFontEntry, present) == 80);
const _: () = assert!(std::mem::offset_of!(SystemFontEntry, face_count) == 84);
const _: () = assert!(std::mem::size_of::<SystemFonts>() == 720);
const _: () = assert!(std::mem::offset_of!(SystemFonts, entries) == 16);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV08>() == 120);
const _: () = assert!(std::mem::size_of::<RangeEntry>() == 56);
const _: () = assert!(std::mem::size_of::<Transaction>() == 72);
const _: () = assert!(std::mem::size_of::<TransactionV09>() == 88);
const _: () = assert!(std::mem::offset_of!(TransactionV09, ranges) == 72);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV09>() == 128);
const _: () = assert!(std::mem::size_of::<RunOptionsV10>() == 48);
const _: () = assert!(std::mem::offset_of!(RunOptionsV10, render_scale) == 40);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV10>() == 136);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV10, run_options_v10_size) == 128);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV09, range_entry_size) == 120);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV11>() == 144);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV12>() == 152);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV12, path_entry_size) == 144);
const _: () = assert!(std::mem::size_of::<PathEntry>() == 32);
const _: () = assert!(std::mem::size_of::<AxExtraEntry>() == 64);
const _: () = assert!(std::mem::offset_of!(AxExtraEntry, flags) == 56);
const _: () = assert!(std::mem::size_of::<TransactionV13>() == 144);
const _: () = assert!(std::mem::offset_of!(TransactionV13, extras) == 128);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV13>() == 160);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV13, ax_extra_entry_size) == 152);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV14>() == 168);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV14, caps) == 160);
const _: () = assert!(std::mem::size_of::<ApiV14>() == 192);
const _: () = assert!(std::mem::offset_of!(ApiV14, text_run_outline) == 184);
const _: () = assert!(std::mem::size_of::<TransactionV12>() == 128);
const _: () = assert!(std::mem::offset_of!(TransactionV12, paths) == 88);
const _: () = assert!(std::mem::offset_of!(TransactionV12, path_count) == 112);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV11, wheel_delta) == 136);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV08, measure_request_v08_size) == 96);
const _: () = assert!(std::mem::offset_of!(BootstrapInfoV08, system_fonts_size) == 112);
const _: () = assert!(std::mem::size_of::<ApiV08>() == 184);
const _: () = assert!(std::mem::offset_of!(ApiV08, image_release) == 128);
const _: () = assert!(std::mem::offset_of!(ApiV08, font_register) == 136);
const _: () = assert!(std::mem::offset_of!(ApiV08, font_resolve) == 144);
const _: () = assert!(std::mem::offset_of!(ApiV08, measure_text_v08) == 152);
const _: () = assert!(std::mem::offset_of!(ApiV08, text_run_faces) == 160);
const _: () = assert!(std::mem::offset_of!(ApiV08, font_face_metrics) == 168);
const _: () = assert!(std::mem::offset_of!(ApiV08, system_font_info) == 176);
const _: () = assert!(std::mem::size_of::<FontInfo>() == 128);
const _: () = assert!(std::mem::size_of::<FontResolution>() == 48);
const _: () = assert!(std::mem::size_of::<BootstrapInfoV07>() == 96);
const _: () = assert!(std::mem::size_of::<ApiV07>() == 152);
const _: () = assert!(std::mem::offset_of!(ApiV07, font_register) == 136);
const _: () = assert!(std::mem::offset_of!(FontInfo, sha256) == 32);
const _: () = assert!(std::mem::offset_of!(FontInfo, family) == 64);
const _: () = assert!(std::mem::size_of::<BootstrapInfo>() == 88);
const _: () = assert!(std::mem::size_of::<HostCallbacks>() == 112);
const _: () = assert!(std::mem::size_of::<Api>() == 136);
const _: () = assert!(std::mem::size_of::<Transaction>() == 72);
const _: () = assert!(std::mem::size_of::<Node>() == 144);
const _: () = assert!(std::mem::size_of::<Primitive>() == 80);
const _: () = assert!(std::mem::size_of::<Semantic>() == 88);
const _: () = assert!(std::mem::size_of::<AxTextRun>() == 80);
const _: () = assert!(std::mem::size_of::<Event>() == 136);
const _: () = assert!(std::mem::size_of::<MeasureRequest>() == 88);
const _: () = assert!(std::mem::size_of::<MeasureResult>() == 56);
const _: () = assert!(std::mem::size_of::<LineInfo>() == 24);
const _: () = assert!(std::mem::size_of::<CharCell>() == 24);
const _: () = assert!(std::mem::size_of::<RunOptions>() == 40);
const _: () = assert!(std::mem::size_of::<WindowMetrics>() == 24);
const _: () = assert!(std::mem::size_of::<ModalRequest>() == 80);
const _: () = assert!(std::mem::size_of::<ModalItem>() == 24);
// Offsets of the rev 0.6 reuses and tails, also clang-measured on swiftright.h.
const _: () = assert!(std::mem::offset_of!(Primitive, image) == 72);
const _: () = assert!(std::mem::offset_of!(Semantic, toggled) == 84);
const _: () = assert!(std::mem::offset_of!(ModalRequest, items) == 48);
const _: () = assert!(std::mem::offset_of!(ModalRequest, x) == 56);
const _: () = assert!(std::mem::offset_of!(ModalRequest, item_count) == 64);
const _: () = assert!(std::mem::offset_of!(ModalRequest, default_item) == 72);
const _: () = assert!(std::mem::offset_of!(ModalItem, id) == 12);
const _: () = assert!(std::mem::size_of::<Stats>() == 200);
