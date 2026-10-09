//! `#[repr(C)]` mirrors of render/swiftright-abi/include/swiftright.h (ABI 0.5).
//! Compile-time size asserts use the sizes measured with clang on the header.

use std::ffi::{c_char, c_void};

pub const ABI_MAJOR: u32 = 0;
pub const ABI_MINOR: u32 = 5;
pub const API_FN_COUNT: u32 = 14;

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

pub const ACT_INVOKE: u32 = 0x1;
pub const ACT_FOCUS: u32 = 0x2;
pub const ACT_SET_VALUE: u32 = 0x4;
pub const ACT_SET_SELECTION: u32 = 0x8;

pub const SEM_HAS_SELECTION: u32 = 0x1;
pub const SEM_MULTILINE: u32 = 0x2;
pub const SEM_DISABLED: u32 = 0x4;

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

pub const EVENT_TEXT_CAP: usize = 64;

pub const IDENTIFIER_MAX: u32 = 256;

/// Post-close pump bound (rev 0.5).
pub const POST_CLOSE_TIMEOUT_MS: u64 = 5000;

pub const MODAL_MESSAGE: u32 = 1;

pub const CELL_WORD_START: u32 = 0x1;

pub const MAX_UPSERTS: u32 = 4096;
pub const MAX_REMOVES: u32 = 4096;
pub const MAX_PRIMITIVES: u32 = 65536;

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
    pub reserved: [u32; 2],
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
    pub reserved: u32,
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
}

// Sizes measured with clang on swiftright.h (x86_64 / arm64 agree).
const _: () = assert!(std::mem::size_of::<BootstrapInfo>() == 88);
const _: () = assert!(std::mem::size_of::<HostCallbacks>() == 112);
const _: () = assert!(std::mem::size_of::<Api>() == 120);
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
const _: () = assert!(std::mem::size_of::<ModalRequest>() == 48);
const _: () = assert!(std::mem::size_of::<Stats>() == 200);
