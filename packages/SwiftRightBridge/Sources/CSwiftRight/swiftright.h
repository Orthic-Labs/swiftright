/*
 * swiftright.h - SwiftRight renderer bridge, C ABI v0 (revision 0.6).
 *
 * Status: ABI v0 candidate consolidated from the SR0-B/SR0-D probes
 * (gpui-drain 0.1, frame-clock 0.2, bridge-faults, text-geometry, ime-text-node).
 * Not frozen: freezing needs the SR0-C contract freeze. Exact compatibility is
 * required (major AND minor must match; every struct size below must match).
 * Revision 0.4: swr_semantic gains an optional stable identifier (identifier,
 * identifier_len), exposed to Windows UI Automation as AutomationId. Appended at the
 * end of swr_semantic, so every earlier field keeps its offset; the struct grows
 * from 72 to 88 bytes and swr_node from 128 to 144 bytes.
 * Revision 0.5: (a) swr_stats gains live_nodes (gauge), post_close_drains and
 * post_close_timeouts, appended at the end; swr_bootstrap_info.reserved becomes
 * stats_size so the host checks sizeof(swr_stats) too. (b) POST-CLOSE PUMP: after
 * window_closed the renderer keeps draining the host's main queue until the host calls
 * swr_shutdown_complete() or SWR_POST_CLOSE_TIMEOUT_MS elapses; commits, measurements
 * and modal requests stay rejected (SWR_E_SHUTDOWN). swr_api gains shutdown_complete at
 * the end (14 functions). (c) SWR_PRIM_UNDERLINE, a solid bar for IME marked text.
 * Revision 0.6 (APPEND-ONLY after the SR0 freeze; no existing field, constant or offset
 * moved): (a) roles CHECKBOX, SWITCH, IMAGE, MENU, MENU_ITEM, ALERT, DIALOG; (b) semantic
 * state: swr_semantic.toggled (the former `reserved` slot) maps to AccessKit Toggled (UIA
 * TogglePattern), SWR_SEM_SELECTABLE / SWR_SEM_SELECTED to AccessKit selected (UIA
 * SelectionItemPattern), and SWR_SEM_DISABLED is now honoured (UIA IsEnabled, pointer and
 * focus routing); (c) images: swr_image handles, swr_image_register / swr_image_release
 * appended to swr_api (16 functions), swr_primitive.image (the former `reserved[2]`)
 * and SWR_PRIM_IMAGE drawing it scaled into rect; (d) modal kinds SWR_MODAL_MENU and
 * SWR_MODAL_DIALOG: swr_modal_request grows a tail (48 -> 80 bytes) with swr_modal_item
 * entries; (e) multi-paragraph text: '\n' is accepted in swr_measure_text, see
 * swr_measure_request. The bootstrap minor is 0.6, so a 0.5 host or renderer is rejected.
 * Revision 0.7 (ADDITIVE, bundled fonts): see "REVISION 0.7" at the end of this header. The
 * 0.6 exports, layouts, constants and behaviour above are unchanged; `swr_bootstrap_query`
 * and `swr_get_api` still describe 0.6 (88 / 136 bytes), so a 0.6 host runs unchanged on a
 * 0.7 renderer. A 0.7 renderer adds two NEW exports, swr_bootstrap_query_v07 and
 * swr_get_api_v07, that a 0.7 host resolves; a 0.6 renderer lacks them.
 *
 * The header is plain C99 with fixed-width types only, so the layout is the same
 * for the Rust renderer, the MSVC ABI and the Swift clang importer. No Swift
 * closure, Rust closure or C++ object ever crosses this boundary: callbacks are
 * plain function pointers plus an opaque `ctx`.
 *
 * ===========================================================================
 * LOADING
 *   The host loads the renderer EXPLICITLY (LoadLibraryW + GetProcAddress); the
 *   renderer is never bound through an import table. Then:
 *     1. resolve `swr_bootstrap_query`, call it with a caller-sized struct;
 *     2. validate abi major/minor, arch, pointer width and EVERY *_size field
 *        against the host's own sizeof() values; reject (typed diagnostic) on any
 *        mismatch BEFORE touching anything else;
 *     3. only then resolve `swr_get_api` and fetch the function table.
 *   `swr_bootstrap_query` and `swr_get_api` never allocate, never start threads,
 *   never call back and are safe to call from any thread.
 *
 * THREADING (the rules the renderer enforces)
 *   - "UI thread" = the thread that calls swr_run (the process' initial thread).
 *     swr_run blocks on it and runs the Windows message loop. Swift's MainActor
 *     runs on that same thread through the host's executor integration.
 *   - Thread-safe entry points (any thread): swr_bootstrap_query, swr_get_api,
 *     swr_request_quit, swr_window_request_close, swr_get_stats.
 *     They only set flags / enqueue and wake the UI loop; they never call the host.
 *   - Every other entry point is UI-thread only and returns SWR_E_WRONG_THREAD
 *     elsewhere.
 *   - All host callbacks run on the UI thread. loop_ready, drain, events_available,
 *     tick and window_closed run OUTSIDE every renderer/GPUI borrow and lock; they
 *     may call any UI-thread entry point except swr_run.
 *   - POST-CLOSE PUMP (rev 0.5): after window_closed, drain (and events_available if
 *     events are queued) keep running on wake until swr_shutdown_complete() or
 *     SWR_POST_CLOSE_TIMEOUT_MS. In this phase swr_commit and swr_measure_text return
 *     SWR_E_SHUTDOWN; swr_request_ticks and swr_request_modal return SWR_E_STALE_HANDLE
 *     (the window is gone); no window or ime_* callback runs. A host job that finishes
 *     late must be rejected by its own check on these statuses.
 *   - The ime_* callbacks run INSIDE native input handling (WM_CHAR /
 *     WM_IME_COMPOSITION) while the renderer holds GPUI borrows. In an ime_*
 *     callback the host may only read/edit its own text store, call
 *     swr_measure_text / swr_text_run_cells / swr_text_run_release, call swr_commit
 *     (the transaction is validated and stored at once but PRESENTED only after the
 *     native callback has unwound) and call swr_event_pop. It must not pump
 *     messages, run its executor, or open a modal.
 *   - Callbacks are NON-REENTRANT: while any host callback is running, no other
 *     host callback is started. A callback that would have nested is refused
 *     (drain/tick/events are re-signalled and run later; an ime_* call returns
 *     failure to the native input path) and counted in swr_stats.
 *   - Rust panics never unwind into the host: every entry point catches them and
 *     returns SWR_E_PANIC. A panic inside the renderer's own host-callback
 *     invocation is also caught and counted.
 *   - Measurement and commit never call back into the host.
 *
 * OWNERSHIP
 *   - Pointers inside request structs (swr_transaction, swr_measure_request,
 *     swr_run_options, swr_modal_request) are BORROWED for the duration of the call
 *     only; the renderer copies what it keeps. The host frees its own memory.
 *   - Buffers the host passes for output (lines_out, cells, event text) are filled
 *     by the renderer and never retained.
 *   - Pointers handed to host callbacks (UTF-16 text in ime_replace*) are valid
 *     only during that callback.
 *   - Handles (swr_window, swr_text_run, swr_image) are opaque 64-bit values: low 32 bits slot,
 *     high 32 bits generation. 0 is never valid. A handle is valid from the call
 *     that returned it until it is explicitly released (swr_text_run_release) or its
 *     owner dies (window closed). A stale handle fails with SWR_E_STALE_HANDLE and
 *     never touches a reused slot. swr_text_run handles are RETAINED by the caller
 *     until swr_text_run_release (owner frees). swr_image handles (rev 0.6) follow the
 *     same rules: retained until swr_image_release or window close; the renderer copies
 *     the pixels at registration, so the host's buffer is borrowed for the call only.
 *   - swr_node_id is host-owned and opaque to the renderer (non-zero, unique within
 *     a window generation). A host must mint a NEW id when a node is removed and a
 *     logically-same node is reinserted; the renderer rejects events for ids that
 *     are not in the live tree, and the host rejects events for ids it no longer
 *     knows.
 *
 * UNITS
 *   All geometry in swr_transaction / swr_event is PHYSICAL pixels, origin at the window
 *   client top-left. Font size and line height in swr_measure_request are DIPs
 *   (1 DIP = 1/96 inch); the request carries the DPI scale (dpi/96) so results come
 *   back in physical pixels. Text offsets are UTF-8 bytes unless a field says UTF-16.
 * ===========================================================================
 */
#ifndef SWIFTRIGHT_H
#define SWIFTRIGHT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef SWR_BUILD
#  define SWR_API __declspec(dllexport)
#else
#  define SWR_API
#endif

#define SWR_ABI_MAJOR 0
#define SWR_ABI_MINOR 6

/* Longest accepted swr_semantic.identifier, in UTF-8 bytes. Longer -> SWR_E_TOO_LARGE. */
#define SWR_IDENTIFIER_MAX 256

/* Post-close pump bound (rev 0.5): after window_closed the renderer drains for at most
 * this long unless swr_shutdown_complete() ends the phase first. */
#define SWR_POST_CLOSE_TIMEOUT_MS 5000

/* Image limits (rev 0.6). Larger -> SWR_E_TOO_LARGE. */
#define SWR_IMAGE_MAX_DIM    8192u      /* width and height, pixels */
#define SWR_IMAGE_MAX_BYTES  (64u * 1024u * 1024u)  /* width * height * 4 */
#define SWR_IMAGE_MAX_LIVE   4096u      /* registered, unreleased images */

/* ------------------------------------------------------------------ status */

typedef int32_t swr_status;

#define SWR_EMPTY              1    /* success: nothing to deliver (swr_event_pop) */
#define SWR_OK                 0
#define SWR_E_BAD_ARG         (-1)  /* null/invalid argument, inconsistent request */
#define SWR_E_PANIC           (-2)  /* a Rust panic was contained at the boundary */
#define SWR_E_NOT_READY       (-3)  /* called before loop_ready / before swr_run */
#define SWR_E_STATE           (-4)  /* wrong state: already running, shut down */
#define SWR_E_PLATFORM        (-5)  /* OS / GPUI / AccessKit failure */
#define SWR_E_STALE_HANDLE    (-6)  /* handle or window generation is no longer live */
#define SWR_E_QUEUE_FULL      (-7)  /* bounded queue overflow */
#define SWR_E_TOO_LARGE       (-8)  /* a count/size exceeds a documented limit */
#define SWR_E_BUSY            (-9)  /* call not permitted now (re-entrancy, borrow) */
#define SWR_E_WRONG_THREAD   (-10)  /* UI-thread-only entry point on another thread */
#define SWR_E_STALE_VERSION  (-11)  /* commit version not newer than the last one */
#define SWR_E_NOT_FOUND      (-12)  /* node / parent / run id not in the tree */
#define SWR_E_SHUTDOWN       (-13)  /* shutdown has begun; new work is rejected */
#define SWR_E_ABI            (-14)  /* struct_size / abi mismatch */
#define SWR_E_UNSUPPORTED    (-15)  /* declared in v0, implemented later */

/* ----------------------------------------------------------------- handles */

typedef uint64_t swr_window;    /* generation-tagged; 0 invalid */
typedef uint64_t swr_text_run;  /* generation-tagged, retained shaped text; 0 invalid */
typedef uint64_t swr_image;     /* rev 0.6: generation-tagged, retained RGBA8 image; 0 invalid */
typedef uint64_t swr_node_id;   /* host-owned, non-zero; 0 = the window root */

typedef struct swr_api swr_api;  /* function table, defined below */

typedef struct swr_rect {
    float x, y, w, h;           /* physical px, window client coordinates */
} swr_rect;

typedef struct swr_utf16_range {
    uint32_t start;             /* UTF-16 code units */
    uint32_t end;
} swr_utf16_range;

typedef struct swr_utf16_selection {
    swr_utf16_range range;
    uint32_t        reversed;   /* 1 = caret at range.start */
    uint32_t        reserved;
} swr_utf16_selection;

/* ---------------------------------------------------------------- bootstrap */

/* Filled by swr_bootstrap_query. Only the first min(caller_size, sizeof) bytes are
 * considered; a caller smaller than the fields it must read gets SWR_E_BAD_ARG and
 * nothing is written. */
typedef struct swr_bootstrap_info {
    uint32_t struct_size;            /* bytes written by the renderer */
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;          /* 32 or 64 */
    char     arch[16];               /* "x86_64", NUL padded */
    uint32_t host_callbacks_size;    /* sizeof(swr_host_callbacks) as the renderer was built */
    uint32_t api_table_size;         /* sizeof(swr_api) */
    uint32_t transaction_size;       /* sizeof(swr_transaction) */
    uint32_t node_size;              /* sizeof(swr_node) */
    uint32_t primitive_size;         /* sizeof(swr_primitive) */
    uint32_t semantic_size;          /* sizeof(swr_semantic) */
    uint32_t ax_text_run_size;       /* sizeof(swr_ax_text_run) */
    uint32_t event_size;             /* sizeof(swr_event) */
    uint32_t measure_request_size;
    uint32_t measure_result_size;
    uint32_t line_info_size;
    uint32_t char_cell_size;
    uint32_t fn_count;               /* number of function pointers in swr_api */
    uint32_t stats_size;             /* sizeof(swr_stats) as the renderer was built (rev 0.5) */
} swr_bootstrap_info;

SWR_API swr_status swr_bootstrap_query(swr_bootstrap_info *out, uint32_t caller_size);

/* ---------------------------------------------------------------- callbacks */

/* Host callback table. All members optional except `drain`. Plain function
 * pointers + one opaque ctx. Install by passing it to swr_run (copied). */
typedef struct swr_host_callbacks {
    uint32_t struct_size;      /* sizeof(swr_host_callbacks) as the host built it */
    uint32_t reserved;
    void    *ctx;

    /* Once, after the window exists. UI thread, outside every borrow. */
    void (*loop_ready)(void *ctx, swr_window window);

    /* Run the host's own main-queue/executor jobs (Swift: the main dispatch queue).
     * Called whenever the host wake handle fired. Non-reentrant. */
    void (*drain)(void *ctx);

    /* One or more events are queued; call swr_event_pop until it returns SWR_EMPTY.
     * Covers input, focus, IME notices, AX actions, modal results, window metrics. */
    void (*events_available)(void *ctx);

    /* Coalesced display tick while swr_request_ticks(on) is active.
     * timestamp_ns is the monotonic (QPC) time of the presented frame that asked. */
    void (*tick)(void *ctx, swr_window window, uint64_t timestamp_ns);

    /* Once, after the window closed. Teardown happens here: release your text runs and
     * drop your node state (commits are already rejected with SWR_E_SHUTDOWN). After this
     * returns the renderer frees its tree and text runs (live_nodes -> 0) and enters the
     * POST-CLOSE PUMP: drain keeps being called on the UI thread, for late main-queue work,
     * until swr_shutdown_complete() or SWR_POST_CLOSE_TIMEOUT_MS. swr_shutdown_complete may
     * be called from this callback. Then swr_run returns. */
    void (*window_closed)(void *ctx, swr_window window);

    /* ---- IME text store (SR0-D ime-text-node mapping). All ranges UTF-16; the host
     * owns buffer, selection, undo and composition state. `node` is the focused
     * editable node (swr_transaction.focus). Return SWR_OK or a negative status. They
     * run inside native input handling: see THREADING. ---- */

    /* selected_text_range */
    swr_status (*ime_get_selection)(void *ctx, swr_window window, swr_node_id node,
                                    swr_utf16_selection *out);
    /* marked_text_range: *has_marked = 0 when no composition */
    swr_status (*ime_get_marked)(void *ctx, swr_window window, swr_node_id node,
                                 swr_utf16_range *out, int32_t *has_marked);
    /* text_for_range: copies up to `cap` UTF-16 units, sets *len and *adjusted */
    swr_status (*ime_copy_text)(void *ctx, swr_window window, swr_node_id node,
                                swr_utf16_range range, uint16_t *buf, uint32_t cap,
                                uint32_t *len, swr_utf16_range *adjusted);
    /* replace_text_in_range: range NULL = replace the marked range, else the selection.
     * Clears the marked range and puts the caret after the inserted text. */
    swr_status (*ime_replace)(void *ctx, swr_window window, swr_node_id node,
                              const swr_utf16_range *range, const uint16_t *text,
                              uint32_t len);
    /* replace_and_mark_text_in_range: new_sel (relative to the inserted text) may be NULL */
    swr_status (*ime_replace_and_mark)(void *ctx, swr_window window, swr_node_id node,
                                       const swr_utf16_range *range, const uint16_t *text,
                                       uint32_t len, const swr_utf16_range *new_sel);
    /* unmark_text */
    swr_status (*ime_unmark)(void *ctx, swr_window window, swr_node_id node);
    /* bounds_for_range: physical client px of the glyph range (caret-anchored candidate
     * window). The host computes it from its committed text-run geometry. */
    swr_status (*ime_caret_bounds)(void *ctx, swr_window window, swr_node_id node,
                                   swr_utf16_range range, swr_rect *out_px);
} swr_host_callbacks;

/* -------------------------------------------------------------------- run */

typedef struct swr_run_options {
    uint32_t    struct_size;
    uint32_t    flags;              /* reserved, 0 */
    const char *title;              /* UTF-8, borrowed */
    void       *host_wake_handle;   /* Windows auto-reset event HANDLE signalled by the
                                       host executor when it has work (Swift: the
                                       main dispatch queue handle). Required. */
    uint32_t    title_len;
    uint32_t    width_dip;          /* initial client size, DIPs; v0 opens ONE window */
    uint32_t    height_dip;
    uint32_t    reserved;
} swr_run_options;

typedef struct swr_window_metrics {
    uint32_t struct_size;
    uint32_t width_px;              /* client size, physical px */
    uint32_t height_px;
    float    scale;                 /* dpi / 96 */
    uint32_t active;                /* window is the active window */
    uint32_t reserved;
} swr_window_metrics;

/* ---------------------------------------------------------------- commit */

#define SWR_NODE_HIT_TARGET  0x1u   /* pointer events report this node when hit */
#define SWR_NODE_FOCUSABLE   0x2u
#define SWR_NODE_EDITABLE    0x4u   /* may be the IME target (swr_transaction.focus) */

#define SWR_PRIM_RECT            1  /* fill rect (+ optional radius / border) */
#define SWR_PRIM_TEXT_RUN        2  /* paint a retained shaped run at rect.x/rect.y */
#define SWR_PRIM_IMAGE           3  /* rev 0.6: swr_primitive.image drawn scaled to fill
                                       rect (corner radius honoured; color, border ignored).
                                       A stale handle fails the commit with
                                       SWR_E_STALE_HANDLE; width/height of rect may be 0. */
#define SWR_PRIM_PATH            4  /* declared; SWR_E_UNSUPPORTED in v0 */
#define SWR_PRIM_CLIP_PUSH       5  /* clip following primitives of this node to rect */
#define SWR_PRIM_CLIP_POP        6
#define SWR_PRIM_TRANSFORM_PUSH  7  /* m = [a b c d tx ty]; v0: translation only */
#define SWR_PRIM_TRANSFORM_POP   8
#define SWR_PRIM_UNDERLINE       9  /* rev 0.5: solid bar, rect.x/y origin, rect.w length,
                                       rect.h thickness (px, > 0), color; border, radius,
                                       image_id, text_run and m are ignored. For IME marked
                                       text. Painted as a solid bar in rev 0.5. */

typedef struct swr_primitive {
    uint32_t     kind;              /* SWR_PRIM_* */
    uint32_t     color;             /* 0xRRGGBBAA fill colour */
    swr_rect     rect;              /* RECT/CLIP: box. TEXT_RUN: x,y = origin. */
    uint32_t     border_color;      /* 0xRRGGBBAA */
    float        border_width;      /* px */
    float        radius;            /* px */
    uint32_t     image_id;          /* IMAGE: unused (reserved, 0) */
    swr_text_run text_run;          /* TEXT_RUN: handle from swr_measure_text */
    float        m[6];              /* TRANSFORM_PUSH */
    swr_image    image;             /* rev 0.6, IMAGE: handle from swr_image_register. This
                                       is the former `reserved[2]` (same offset and size,
                                       80 bytes): old hosts zeroed it. */
} swr_primitive;

#define SWR_ROLE_NONE       0
#define SWR_ROLE_WINDOW     1
#define SWR_ROLE_BUTTON     2
#define SWR_ROLE_STATIC_TEXT 3
#define SWR_ROLE_TEXT_FIELD 4
#define SWR_ROLE_LIST       5
#define SWR_ROLE_LIST_ITEM  6
#define SWR_ROLE_GROUP      7
/* rev 0.6. AccessKit 0.25.1 Role / Windows UIA control type (accesskit_windows 0.35.1 node.rs):
 *   CHECKBOX  -> Role::CheckBox   / UIA CheckBox   (TogglePattern when `toggled` is set)
 *   SWITCH    -> Role::Switch     / UIA Button     (TogglePattern when `toggled` is set)
 *   IMAGE     -> Role::Image      / UIA Image
 *   MENU      -> Role::Menu       / UIA Menu
 *   MENU_ITEM -> Role::MenuItem   / UIA MenuItem
 *   ALERT     -> Role::AlertDialog / UIA Window    (an alert dialog; Role::Alert would map
 *                                   to a UIA Text live region, which is not what an alert
 *                                   surface is)
 *   DIALOG    -> Role::Dialog     / UIA Window */
#define SWR_ROLE_CHECKBOX   8
#define SWR_ROLE_SWITCH     9
#define SWR_ROLE_IMAGE      10
#define SWR_ROLE_MENU       11
#define SWR_ROLE_MENU_ITEM  12
#define SWR_ROLE_ALERT      13
#define SWR_ROLE_DIALOG     14
/* rev 0.9: SLIDER -> Role::Slider / UIA Slider. With a swr_range_entry in the same transaction it also
 * publishes the UIA RangeValuePattern (Value, Minimum, Maximum, SmallChange, LargeChange). Without one it is
 * a bare slider (no range). A 0.8 renderer does not know this role (a generic container). */
#define SWR_ROLE_SLIDER     15

#define SWR_ACT_INVOKE         0x1u
#define SWR_ACT_FOCUS          0x2u
#define SWR_ACT_SET_VALUE      0x4u
#define SWR_ACT_SET_SELECTION  0x8u

#define SWR_SEM_HAS_SELECTION  0x1u
#define SWR_SEM_MULTILINE      0x2u
#define SWR_SEM_DISABLED       0x4u   /* rev 0.6: honoured. AccessKit disabled (UIA IsEnabled
                                         = false; UIA Invoke/Toggle/Select are refused) for
                                         this node and its semantic descendants; a pointer
                                         press whose topmost hit target is a disabled node
                                         is reported with node 0 (swallowed, not passed
                                         through); a disabled node is never the key-event or
                                         IME target (events carry node 0). */
#define SWR_SEM_SELECTABLE     0x8u   /* rev 0.6: publish AccessKit `selected` (UIA
                                         SelectionItemPattern; list items, menu items). */
#define SWR_SEM_SELECTED       0x10u  /* rev 0.6: with SELECTABLE, selected = true. */

/* swr_semantic.toggled (rev 0.6): checked/pressed/on state, AccessKit Toggled
 * (False/True/Mixed), UIA TogglePattern ToggleState Off/On/Indeterminate. */
#define SWR_TOGGLED_NONE   0u         /* not a toggle (no TogglePattern) */
#define SWR_TOGGLED_OFF    1u
#define SWR_TOGGLED_ON     2u
#define SWR_TOGGLED_MIXED  3u

/* One visual line of a text node, published as an AccessKit TextRun child. All
 * per-character arrays have char_count entries; positions/widths are run-local
 * physical px. word_starts are character indices (< 256) inside this run. */
typedef struct swr_ax_text_run {
    swr_node_id    id;              /* host-owned id of the run node (distinct from node ids) */
    const char    *text;            /* UTF-8 of this visual line */
    const uint8_t *char_lengths;    /* UTF-8 byte length of each character */
    const float   *char_positions;
    const float   *char_widths;
    const uint8_t *word_starts;
    swr_rect       bounds;          /* physical px, window coordinates */
    uint32_t       text_len;
    uint32_t       char_count;
    uint32_t       word_start_count;
    uint32_t       reserved;
} swr_ax_text_run;

typedef struct swr_semantic {
    const char            *label;       /* UTF-8, borrowed */
    const char            *value;
    const swr_ax_text_run *runs;
    swr_node_id            sel_anchor_run;   /* with SWR_SEM_HAS_SELECTION */
    swr_node_id            sel_focus_run;
    uint32_t               role;        /* SWR_ROLE_* */
    uint32_t               actions;     /* SWR_ACT_* bitset */
    uint32_t               flags;       /* SWR_SEM_* */
    uint32_t               label_len;
    uint32_t               value_len;
    uint32_t               run_count;
    uint32_t               sel_anchor_char;  /* character index inside the anchor run */
    uint32_t               sel_focus_char;
    /* Optional stable identifier (rev 0.4), UTF-8, borrowed, at most
     * SWR_IDENTIFIER_MAX bytes; NULL/0 = none. Host-owned: it names the node for
     * automation (Windows UIA AutomationId; the Mac counterpart is AXIdentifier, e.g.
     * "row/<uuid>/field" or "toolbar/insert"). It is not a handle and not parsed by
     * the renderer. Among siblings it should be unique: AutomationId lookups by value
     * are ambiguous otherwise. The renderer does not check uniqueness. */
    const char            *identifier;
    uint32_t               identifier_len;
    uint32_t               toggled;     /* rev 0.6: SWR_TOGGLED_*; the former `reserved` slot
                                           (same offset and size; old hosts zeroed it = NONE).
                                           Values > SWR_TOGGLED_MIXED -> SWR_E_BAD_ARG. */
} swr_semantic;

typedef struct swr_node {
    swr_node_id  id;            /* host-owned, non-zero */
    swr_node_id  parent;        /* 0 = window root; must exist (earlier in tree or this commit) */
    swr_rect     bounds;        /* physical px; used for hit-testing and AX bounds */
    uint32_t     order;         /* sibling order, ascending; ties broken by id */
    uint32_t     flags;         /* SWR_NODE_* */
    uint32_t     prim_offset;   /* slice of swr_transaction.primitives owned by this node */
    uint32_t     prim_count;
    uint32_t     has_semantic;  /* 1 = `semantic` is valid */
    uint32_t     reserved;
    swr_semantic semantic;
} swr_node;

/* One versioned transaction. Removes are applied first (a removed node takes its
 * descendants with it), then upserts. An upsert REPLACES the node's geometry,
 * primitive list and semantics. Validation is all-or-nothing: on any error nothing
 * is applied. Painting, hit-testing and the AccessKit tree all read the snapshot
 * produced by the latest accepted commit. */
typedef struct swr_transaction {
    uint32_t              struct_size;
    uint32_t              flags;          /* reserved, 0 */
    swr_window            window;
    uint64_t              version;        /* must exceed the window's last version */
    swr_node_id           focus;          /* focus target node, 0 = window */
    const swr_node       *upserts;
    const swr_node_id    *removes;
    const swr_primitive  *primitives;     /* shared pool addressed by swr_node.prim_* */
    uint32_t              upsert_count;   /* limit 4096 */
    uint32_t              remove_count;   /* limit 4096 */
    uint32_t              primitive_count;/* limit 65536 */
    uint32_t              reserved;
} swr_transaction;

/* ------------------------------------------------------------ measurement */

#define SWR_DIR_LTR 0               /* RTL/bidi: SWR_E_UNSUPPORTED in v0 */

typedef struct swr_line_info {      /* one visual (wrapped) line */
    uint32_t utf8_start;
    uint32_t utf8_len;
    float    width;                 /* physical px, ink-advance width of the line */
    float    top;                   /* physical px, run-local */
    float    baseline;              /* physical px, run-local, from the run top */
    float    reserved;
} swr_line_info;

typedef struct swr_measure_request {
    uint32_t       struct_size;
    uint32_t       flags;           /* reserved, 0 */
    const char    *text;            /* UTF-8. rev 0.6: '\n' separates paragraphs. Each is
                                       shaped and wrapped on its own and stacked; the '\n'
                                       is a zero-width char cell (SWR_CELL_LINE_BREAK) at the
                                       end of the visual line it terminates, and belongs to
                                       that line's swr_line_info (utf8_len includes it), so
                                       lines partition the text. A trailing '\n' yields a final
                                       empty line. '\r' is still SWR_E_UNSUPPORTED. */
    const char    *font_family;     /* UTF-8 */
    const char    *locale;          /* UTF-8, e.g. "en-US" (part of the cache key) */
    swr_line_info *lines_out;       /* optional caller buffer for line breaks */
    uint32_t       text_len;
    uint32_t       font_family_len;
    uint32_t       locale_len;
    uint32_t       font_weight;     /* 100..900, 400 regular */
    uint32_t       direction;       /* SWR_DIR_* */
    uint32_t       color;           /* 0xRRGGBBAA baked into the shaped run (GPUI bakes
                                       colour into shaping; part of the cache key) */
    float          font_size;       /* DIPs */
    float          line_height;     /* DIPs */
    float          scale;           /* dpi / 96 */
    float          max_width;       /* physical px; <= 0 = unbounded */
    uint32_t       lines_cap;       /* entries available in lines_out */
    uint32_t       reserved;
} swr_measure_request;

typedef struct swr_measure_result {
    uint32_t     struct_size;
    uint32_t     cache_hit;         /* 1 when the shaped run came from the cache */
    swr_text_run run;               /* RETAINED: release with swr_text_run_release */
    float        width;             /* physical px */
    float        height;            /* physical px = line_count * line_height * scale */
    float        first_baseline;    /* physical px from the run top */
    float        last_baseline;
    uint32_t     line_count;
    uint32_t     lines_written;     /* min(line_count, lines_cap) */
    uint32_t     char_count;        /* Unicode scalar values */
    uint32_t     reserved;
    uint64_t     cache_key;         /* hash of (text, font+weight+size, width, locale,
                                       direction, DPI scale, colour) */
} swr_measure_result;

typedef struct swr_char_cell {      /* per-character geometry of a shaped run */
    uint32_t utf8_offset;
    uint32_t utf8_len;
    uint32_t line;                  /* visual line index */
    uint32_t flags;                 /* bit 0: word start */
    float    x0;                    /* physical px, relative to the start of its line */
    float    x1;
} swr_char_cell;

#define SWR_CELL_WORD_START 0x1u
#define SWR_CELL_LINE_BREAK 0x2u        /* rev 0.6: the '\n' character; x0 == x1 == the end of
                                       its line's ink. A caret after it belongs on the
                                       next line at x = 0. */

/* ----------------------------------------------------------------- events */

#define SWR_EV_KEY             1    /* action: SWR_KEY_DOWN / SWR_KEY_UP */
#define SWR_EV_POINTER         2    /* action: SWR_PTR_*; node = hit node (0 = none) */
#define SWR_EV_FOCUS           3    /* window focus: i0 = 1 gained / 0 lost */
#define SWR_EV_IME             4    /* action: SWR_IME_*; node = IME target */
#define SWR_EV_AX_ACTION       5    /* action: SWR_AX_*; node = target node */
#define SWR_EV_MODAL_RESULT    6    /* arg = request id, i0 = SWR_MODAL_RESULT_* */
#define SWR_EV_WINDOW_METRICS  7    /* i0 = width px, i1 = height px, x = scale */

#define SWR_KEY_DOWN 1
#define SWR_KEY_UP   2
#define SWR_PTR_DOWN 1
#define SWR_PTR_UP   2
#define SWR_PTR_MOVE 3
#define SWR_IME_MARK    1           /* composition text updated */
#define SWR_IME_COMMIT  2           /* text committed */
#define SWR_IME_UNMARK  3
#define SWR_AX_INVOKE        1
#define SWR_AX_FOCUS         2
#define SWR_AX_SET_VALUE     3      /* text = new value (truncated to 63 bytes; i0 = 1 if so) */
#define SWR_AX_SET_SELECTION 4      /* i0/i1 = anchor/focus character index within `node`'s value */

#define SWR_MOD_CTRL     0x1u
#define SWR_MOD_ALT      0x2u
#define SWR_MOD_SHIFT    0x4u
#define SWR_MOD_PLATFORM 0x8u

#define SWR_EVENT_TEXT_CAP 64

/* Every event is tagged with the window generation and the snapshot version it
 * refers to. Hosts MUST discard events whose `window` is not their live window or
 * whose `node` they no longer know; the renderer additionally drops events for a
 * dead window at pop time. KEY: text = key name immediately followed by the typed
 * character (if any); i1 = key-name byte length, i0 = typed-char byte length. */
typedef struct swr_event {
    uint32_t    kind;
    uint32_t    action;
    swr_window  window;
    swr_node_id node;
    uint64_t    snapshot;
    uint64_t    seq;                /* unique, increasing, assigned at enqueue */
    uint64_t    arg;                /* MODAL_RESULT: request id */
    float       x, y;               /* POINTER: physical px; WINDOW_METRICS: x = scale */
    int32_t     i0, i1;
    uint32_t    modifiers;          /* SWR_MOD_* */
    uint32_t    text_len;           /* bytes used in text */
    char        text[SWR_EVENT_TEXT_CAP];
} swr_event;

/* ----------------------------------------------------------------- modal */

#define SWR_MODAL_MESSAGE 1         /* MessageBox: opened AFTER the current drain/borrows
                                       unwind, result reported as SWR_EV_MODAL_RESULT */
#define SWR_MODAL_MENU    2         /* rev 0.6: TrackPopupMenu at (x, y), items = swr_modal_item.
                                       Same policy as MESSAGE: opened only after drains and
                                       borrows unwind. Result event: i0 = chosen item id,
                                       i1 = chosen item index, or i0 = 0 / i1 = -1 when the
                                       menu was dismissed (i1 = -2: it could not be shown).
                                       action = SWR_MODAL_MENU. */
#define SWR_MODAL_DIALOG  3         /* rev 0.6: TaskDialogIndirect with custom buttons (items),
                                       title = window title, message = content. Result as
                                       MENU; closing the dialog (Esc, the close box) reports
                                       i0 = 0 / i1 = -1; i1 = -2: the dialog could not be
                                       shown. action = SWR_MODAL_DIALOG. */
#define SWR_MODAL_BUTTONS_OK        1
#define SWR_MODAL_BUTTONS_OK_CANCEL 2
#define SWR_MODAL_BUTTONS_YES_NO    3
#define SWR_MODAL_RESULT_OK     1
#define SWR_MODAL_RESULT_CANCEL 2
#define SWR_MODAL_RESULT_YES    6
#define SWR_MODAL_RESULT_NO     7

/* rev 0.6: item flags. */
#define SWR_MODAL_ITEM_DISABLED   0x1u  /* MENU: greyed, not selectable */
#define SWR_MODAL_ITEM_SEPARATOR  0x2u  /* MENU: a separator line (text and id ignored) */
#define SWR_MODAL_ITEM_CHECKED    0x4u  /* MENU: check mark */
#define SWR_MODAL_ITEMS_MAX_MENU   64u  /* more -> SWR_E_TOO_LARGE */
#define SWR_MODAL_ITEMS_MAX_DIALOG 8u   /* 1..8 buttons */

typedef struct swr_modal_item {
    const char *text;               /* UTF-8, borrowed. DIALOG: the button label. */
    uint32_t    text_len;
    uint32_t    id;                 /* host-chosen, non-zero, unique within the request
                                       (ignored for separators) */
    uint32_t    flags;              /* SWR_MODAL_ITEM_* (DIALOG: none defined, 0) */
    uint32_t    reserved;
} swr_modal_item;

/* The first 48 bytes are the 0.5 layout; the tail is appended (rev 0.6). Every kind needs
 * struct_size >= sizeof(swr_modal_request) (80), else SWR_E_ABI. MESSAGE ignores the tail. */
typedef struct swr_modal_request {
    uint32_t    struct_size;
    uint32_t    kind;               /* SWR_MODAL_* */
    uint64_t    request_id;         /* echoed in the result event */
    const char *title;              /* UTF-8, borrowed */
    const char *message;
    uint32_t    title_len;
    uint32_t    message_len;
    uint32_t    buttons;            /* SWR_MODAL_BUTTONS_* (MESSAGE only) */
    uint32_t    reserved;
    /* ---- rev 0.6 tail ---- */
    const swr_modal_item *items;    /* MENU / DIALOG: item_count entries, borrowed */
    float       x, y;               /* MENU: anchor, physical px, window client coordinates.
                                       Negative x AND y: anchor at the pointer position. */
    uint32_t    item_count;
    uint32_t    flags;              /* reserved, 0 */
    uint32_t    default_item;       /* DIALOG: index of the default button */
    uint32_t    tail_reserved;
} swr_modal_request;

/* ------------------------------------------------------------------ stats */

typedef struct swr_stats {
    uint32_t struct_size;
    uint32_t reserved;
    uint64_t drain_calls;
    uint64_t reentry_refused;       /* nested host callbacks refused */
    uint64_t thread_violations;     /* host callback attempted off the UI thread */
    uint64_t host_panics;           /* panics contained inside host callbacks */
    uint64_t wake_signals;
    uint64_t ticks_requested;
    uint64_t ticks_delivered;
    uint64_t paints;
    uint64_t commits_accepted;
    uint64_t commits_rejected;
    uint64_t commits_deferred;      /* accepted while inside an ime_* callback */
    uint64_t measure_calls;
    uint64_t measure_cache_hits;
    uint64_t events_pushed;
    uint64_t events_dropped_full;
    uint64_t events_dropped_stale;
    uint64_t ax_actions_enqueued;
    uint64_t ax_actions_rejected;
    uint64_t ime_calls;
    uint64_t ime_busy_rejected;
    uint64_t selftest_reentry_detected;
    /* rev 0.5. live_nodes is a GAUGE, not a counter: swr_node entries retained by the
     * committed tree plus live (unreleased) swr_text_run handles and (rev 0.6) images that
     * are alive: still held by the host OR referenced by a committed node (counted until freed).
     * Zero after teardown.
     * Readable from any thread (it is an atomic mirror). */
    uint64_t live_nodes;
    uint64_t post_close_drains;     /* drain calls during the post-close pump */
    uint64_t post_close_timeouts;   /* post-close phases ended by the timeout */
} swr_stats;

/* -------------------------------------------------------------- functions */

SWR_API swr_status swr_get_api(swr_api *out, uint32_t caller_size);

/* Blocks on the calling thread: opens the window, runs the loop, and returns after the
 * post-close pump ends (swr_shutdown_complete or the timeout). One run per process in v0. */
SWR_API swr_status swr_run(const swr_run_options *opts, const swr_host_callbacks *cb);
/* Thread-safe. Closes the window and ends swr_run (window_closed still fires). */
SWR_API swr_status swr_request_quit(void);
/* Thread-safe. Close one window (handle validated on the UI thread). */
SWR_API swr_status swr_window_request_close(swr_window window);
SWR_API swr_status swr_window_get_metrics(swr_window window, swr_window_metrics *out);

SWR_API swr_status swr_commit(const swr_transaction *c);

SWR_API swr_status swr_measure_text(const swr_measure_request *req, swr_measure_result *out);
/* cells: char_count entries; *count always set to the total, `cap` entries written. */
SWR_API swr_status swr_text_run_cells(swr_text_run run, swr_char_cell *cells, uint32_t cap,
                                      uint32_t *count);
SWR_API swr_status swr_text_run_release(swr_text_run run);

/* SWR_OK = *out written, SWR_EMPTY = queue empty. Bounded queue (256); overflow drops
 * the NEW event and counts it in swr_stats.events_dropped_full. */
SWR_API swr_status swr_event_pop(swr_event *out);

/* Display ticks: while on, every presented frame requests one coalesced tick(). Stops
 * by itself when off, when idle and when the window closes. */
SWR_API swr_status swr_request_ticks(swr_window window, int32_t on);

/* Opens asynchronously; never nests inside the caller. */
SWR_API swr_status swr_request_modal(swr_window window, const swr_modal_request *req);

/* rev 0.6. UI thread only. Copies width * height RGBA8 pixels (straight, non-premultiplied
 * alpha; byte order R, G, B, A; row stride `stride` bytes, 0 = width * 4) and returns a
 * RETAINED handle in *out. Release with swr_image_release (owner frees); every live handle
 * is also dropped when the window closes. width/height 0 or > SWR_IMAGE_MAX_DIM,
 * a stride below width * 4 or a null buffer -> SWR_E_BAD_ARG (dimensions over the limit,
 * or more than SWR_IMAGE_MAX_BYTES / SWR_IMAGE_MAX_LIVE -> SWR_E_TOO_LARGE).
 * SWR_E_SHUTDOWN after shutdown has begun. swr_stats.live_nodes counts an image until it is freed:
 * after swr_image_release it stays counted while a committed node still references it. */
SWR_API swr_status swr_image_register(const uint8_t *rgba, uint32_t width, uint32_t height,
                                      uint32_t stride, swr_image *out);
/* A stale or already released handle fails with SWR_E_STALE_HANDLE. */
SWR_API swr_status swr_image_release(swr_image image);

/* Inside a drain callback only: returns 1 when the renderer refuses a nested drain,
 * 0 when it did not, -1 outside a drain. For fault tests. */
SWR_API swr_status swr_selftest_reentry(void);

SWR_API swr_status swr_get_stats(swr_stats *out);

/* UI thread only (E_WRONG_THREAD elsewhere). Valid after window_closed has been entered
 * (SWR_E_STATE before that). Ends the post-close pump; the renderer then returns from
 * swr_run. Idempotent. */
SWR_API swr_status swr_shutdown_complete(void);

struct swr_api {
    uint32_t struct_size;
    uint32_t reserved;
    swr_status (*run)(const swr_run_options *, const swr_host_callbacks *);
    swr_status (*request_quit)(void);
    swr_status (*window_request_close)(swr_window);
    swr_status (*window_get_metrics)(swr_window, swr_window_metrics *);
    swr_status (*commit)(const swr_transaction *);
    swr_status (*measure_text)(const swr_measure_request *, swr_measure_result *);
    swr_status (*text_run_cells)(swr_text_run, swr_char_cell *, uint32_t, uint32_t *);
    swr_status (*text_run_release)(swr_text_run);
    swr_status (*event_pop)(swr_event *);
    swr_status (*request_ticks)(swr_window, int32_t);
    swr_status (*request_modal)(swr_window, const swr_modal_request *);
    swr_status (*selftest_reentry)(void);
    swr_status (*get_stats)(swr_stats *);
    swr_status (*shutdown_complete)(void);   /* rev 0.5, appended */
    swr_status (*image_register)(const uint8_t *, uint32_t, uint32_t, uint32_t, swr_image *); /* rev 0.6 */
    swr_status (*image_release)(swr_image);  /* rev 0.6 */
};

#define SWR_API_FN_COUNT 16

/* ===========================================================================
 * REVISION 0.7 (additive): bundled-font registration.
 *
 * NEGOTIATION. Nothing above changes. swr_bootstrap_query keeps returning 88 bytes with
 * abi_minor 6 and swr_get_api keeps the 136-byte, 16-pointer table, so a 0.6 host runs
 * unchanged on a 0.7 renderer. A 0.7 host first looks for swr_bootstrap_query_v07 (and
 * swr_get_api_v07). Present: validate the 0.7 view (abi_minor 7, every size) and use the
 * 0.7 table. Absent: the renderer is 0.6; the host either falls back to the 0.6 view with
 * font registration reported as unavailable, or refuses, as its own policy says. The two
 * views are selected only by symbol name; there is no global mode. Both discovery calls
 * stay allocation-, thread- and callback-free.
 *
 * FONTS. swr_font_register hands the renderer the bytes of one TrueType/OpenType font
 * (TTF/OTF; a TrueType collection registers every face) for THIS process only. The bytes
 * are BORROWED for the call; the renderer copies them and keeps the copy for the life of
 * the process: GPUI 0.2.2's DirectWrite text system has no way to remove a registered
 * font, so there is no unregister entry and no resource release. Registering the same
 * bytes again returns the same handle with SWR_FONT_DUPLICATE. After a successful call
 * a measurement or primitive whose font family equals info.family (case-insensitive)
 * is shaped with those bytes instead of a system face. Register before the first
 * measurement of that family: GPUI caches the family resolution, and a family that was
 * already measured reports SWR_FONT_LATE (measure results already retained are
 * unaffected; the renderer drops its own text cache).
 * UI thread only (SWR_E_WRONG_THREAD), only once the window exists (call it from `ready`;
 * SWR_E_NOT_READY before), SWR_E_SHUTDOWN after shutdown has begun. Bad font bytes ->
 * SWR_E_BAD_ARG; more than SWR_FONT_MAX_BYTES -> SWR_E_TOO_LARGE; family longer than
 * SWR_FONT_FAMILY_MAX -> SWR_E_TOO_LARGE; platform refusal -> SWR_E_PLATFORM. The caller
 * sets info->struct_size to sizeof(swr_font_info) (smaller -> SWR_E_ABI, nothing written).
 *
 * swr_font_resolve reports where a family name will be shaped from, without shaping:
 * bundled bytes (with their handle and SHA-256), a system/GPUI-listed family, or the
 * fallback. It is the negative control: an unregistered family reports FALLBACK, never a
 * bundled result. */
#define SWR_ABI_MINOR_V07 7
#define SWR_API_V07_FN_COUNT 18
#define SWR_FONT_MAX_BYTES (32u * 1024u * 1024u)
#define SWR_FONT_FAMILY_MAX 64

/* swr_font_info.flags */
#define SWR_FONT_NEW           0x1u  /* first registration of these bytes */
#define SWR_FONT_DUPLICATE     0x2u  /* same bytes registered before; handle unchanged */
#define SWR_FONT_SYSTEM_FAMILY 0x4u  /* the family name was already listed by the text system */
#define SWR_FONT_LATE          0x8u  /* the family had already been measured: GPUI may keep a cached resolution */

/* swr_font_resolution.source */
#define SWR_FONT_SRC_FALLBACK 0u  /* not bundled and not listed: shaped with the fallback face */
#define SWR_FONT_SRC_BUNDLED  1u  /* shaped from registered bytes (font + sha256 identify them) */
#define SWR_FONT_SRC_SYSTEM   2u  /* listed by the text system (installed family) */

typedef uint64_t swr_font; /* opaque, 0 never valid; process lifetime */

typedef struct swr_font_info {
    uint32_t struct_size;   /* IN: sizeof(swr_font_info) */
    uint32_t flags;         /* OUT: SWR_FONT_* */
    swr_font font;          /* OUT: handle */
    uint32_t family_len;    /* OUT: bytes in family */
    uint32_t weight;        /* OUT: OS/2 usWeightClass of the first face (400 when absent) */
    uint32_t face_count;    /* OUT: faces in the file */
    uint32_t reserved;      /* OUT: 0 */
    uint8_t  sha256[32];    /* OUT: SHA-256 of the registered bytes */
    char     family[SWR_FONT_FAMILY_MAX]; /* OUT: family name (UTF-8, NUL padded) */
} swr_font_info;

typedef struct swr_font_resolution {
    uint32_t struct_size;   /* IN: sizeof(swr_font_resolution) */
    uint32_t source;        /* OUT: SWR_FONT_SRC_* */
    swr_font font;          /* OUT: handle when BUNDLED, else 0 */
    uint8_t  sha256[32];    /* OUT: bundled bytes' SHA-256, else zeros */
} swr_font_resolution;

/* 0.7 view of swr_bootstrap_info: the 88 bytes above, identical offsets (abi_minor 7,
 * api_table_size sizeof(swr_api_v07), fn_count 18), plus the two size words. Requires
 * caller_size >= sizeof(swr_bootstrap_info_v07) else SWR_E_BAD_ARG, nothing written. */
typedef struct swr_bootstrap_info_v07 {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char     arch[16];
    uint32_t host_callbacks_size;
    uint32_t api_table_size;
    uint32_t transaction_size;
    uint32_t node_size;
    uint32_t primitive_size;
    uint32_t semantic_size;
    uint32_t ax_text_run_size;
    uint32_t event_size;
    uint32_t measure_request_size;
    uint32_t measure_result_size;
    uint32_t line_info_size;
    uint32_t char_cell_size;
    uint32_t fn_count;
    uint32_t stats_size;
    uint32_t font_info_size;        /* sizeof(swr_font_info) = 128 */
    uint32_t font_resolution_size;  /* sizeof(swr_font_resolution) = 48 */
} swr_bootstrap_info_v07;

SWR_API swr_status swr_bootstrap_query_v07(swr_bootstrap_info_v07 *out, uint32_t caller_size);

SWR_API swr_status swr_font_register(const uint8_t *bytes, uint64_t len, swr_font_info *out);
SWR_API swr_status swr_font_resolve(const uint8_t *family, uint32_t family_len,
                                    swr_font_resolution *out);

/* The 0.7 function table: the 16 pointers of swr_api at unchanged offsets, then the two
 * font entries. struct_size/reserved as in swr_api. Requires caller_size >=
 * sizeof(swr_api_v07) else SWR_E_ABI, nothing written. Future revisions append here. */
struct swr_api_v07 {
    uint32_t struct_size;
    uint32_t reserved;
    swr_status (*run)(const swr_run_options *, const swr_host_callbacks *);
    swr_status (*request_quit)(void);
    swr_status (*window_request_close)(swr_window);
    swr_status (*window_get_metrics)(swr_window, swr_window_metrics *);
    swr_status (*commit)(const swr_transaction *);
    swr_status (*measure_text)(const swr_measure_request *, swr_measure_result *);
    swr_status (*text_run_cells)(swr_text_run, swr_char_cell *, uint32_t, uint32_t *);
    swr_status (*text_run_release)(swr_text_run);
    swr_status (*event_pop)(swr_event *);
    swr_status (*request_ticks)(swr_window, int32_t);
    swr_status (*request_modal)(swr_window, const swr_modal_request *);
    swr_status (*selftest_reentry)(void);
    swr_status (*get_stats)(swr_stats *);
    swr_status (*shutdown_complete)(void);
    swr_status (*image_register)(const uint8_t *, uint32_t, uint32_t, uint32_t, swr_image *);
    swr_status (*image_release)(swr_image);
    swr_status (*font_register)(const uint8_t *, uint64_t, swr_font_info *);              /* rev 0.7 */
    swr_status (*font_resolve)(const uint8_t *, uint32_t, swr_font_resolution *);          /* rev 0.7 */
};
typedef struct swr_api_v07 swr_api_v07;

SWR_API swr_status swr_get_api_v07(swr_api_v07 *out, uint32_t caller_size);

/* ===========================================================================
 * REVISION 0.8 (additive): text extension, MINIMAL FORM (decision G60..G69).
 *
 * NEGOTIATION. Nothing above changes: swr_bootstrap_query / swr_get_api still describe 0.6
 * (88 / 136 bytes), the _v07 exports still describe 0.7 (96 / 152 bytes, 18 functions), so a
 * 0.6 or 0.7 host runs unchanged on a 0.8 renderer. A 0.8 renderer adds two NEW exports,
 * swr_bootstrap_query_v08 and swr_get_api_v08. A 0.8 host resolves them; a 0.7 renderer lacks
 * both, and the host then either falls back to the 0.7 view with the text extension reported as
 * unavailable (extension requests are REFUSED with SWR_E_UNSUPPORTED by the bridge, never
 * silently dropped) or refuses the renderer, as its own policy says. Exactly one of the two
 * exports present is a half-exported renderer and is refused. The views are selected only by
 * symbol name; there is no global mode.
 *
 * The 0.8 table is the 18 pointers of swr_api_v07 at unchanged offsets, then the four 0.8
 * entries. The held frame/readback entries of the 0.7 proposal come AFTER these (their order is
 * unchanged; they are not part of 0.8).
 *
 * MINIMAL FORM. Everything here is reachable through gpui 0.2.2 + a DirectWrite face resolver
 * inside the renderer (F0 facts, decisions G10-G19). What gpui cannot do is NOT faked:
 *   - width_axis (wdth), opsz and slant are accepted so the struct is final, but are IGNORED and
 *     reported in swr_measure_result_v08.ignored (gpui snaps to named instances; no continuous
 *     axes, no automatic optical size; pick the family: "Segoe UI Variable Text|Display|Small").
 *   - weight_f snaps to the nearest named instance of the family (ties go heavier, as
 *     DirectWrite does: 500 -> 600); the instance used is reported in resolved_weight and an
 *     inexact request sets SWR_M08_IGN_WEIGHT_SNAPPED.
 *   - fallback_families are SYSTEM families only. A family that is not in the system font set
 *     (a bundled one) is reported in SWR_M08_IGN_FALLBACK_PRIVATE and has no effect (gpui looks
 *     fallbacks up in the system collection only; private fallback is block F3b).
 *   - tracking_dip and kerning_dip are added after every glyph cluster (kerning_dip is additive
 *     like tracking: pair kerning itself is the OpenType `kern` feature). Wrapping (max_width)
 *     is decided on the UNTRACKED advances.
 *   - gpui does not kern by default: the host sends the feature (SWR_TAG('k','e','r','n'), 1) on
 *     every Windows run; the renderer passes the list to the shaper unchanged.
 */
#define SWR_ABI_MINOR_V08 8
#define SWR_API_V08_FN_COUNT 22
#define SWR_FEATURES_MAX   16
#define SWR_FALLBACKS_MAX  8
#define SWR_FACE_AXES_MAX  8
#define SWR_NAME_MAX       64
#define SWR_VERSION_MAX    32
#define SWR_SYSFONT_ENTRIES 8
#define SWR_SYSFONT_NAME_MAX 48

/* OpenType tag as four ASCII bytes, first character in the high byte. */
#define SWR_TAG(a, b, c, d) \
    (((uint32_t)(uint8_t)(a) << 24) | ((uint32_t)(uint8_t)(b) << 16) | \
     ((uint32_t)(uint8_t)(c) << 8) | (uint32_t)(uint8_t)(d))

typedef struct swr_feature {
    uint32_t tag;           /* SWR_TAG(...) */
    uint32_t value;         /* 0 = off, 1 = on, n = alternate n */
} swr_feature;

typedef struct swr_str {
    const char *ptr;        /* UTF-8, not NUL terminated */
    uint32_t    len;
    uint32_t    reserved;
} swr_str;

/* swr_measure_request_v08.flags */
#define SWR_M08_BASELINE_OFFSET 0x1u  /* baseline_offset_dip is valid (0 is a legal offset) */

/* swr_measure_request_v08.simulations: FORBID bits, so a zeroed field keeps the 0.6 behaviour
 * (DirectWrite may simulate). A forbidden simulation draws the nearest REAL face instead (the
 * Mac does not synthesise, G27) and is reported. */
#define SWR_SIM_FORBID_BOLD    0x1u
#define SWR_SIM_FORBID_OBLIQUE 0x2u

/* swr_measure_result_v08.applied */
#define SWR_M08_APPLIED_FEATURES   0x01u
#define SWR_M08_APPLIED_TRACKING   0x02u
#define SWR_M08_APPLIED_BASELINE   0x04u
#define SWR_M08_APPLIED_FALLBACKS  0x08u  /* at least one system fallback family was passed to the shaper */
#define SWR_M08_APPLIED_WEIGHT     0x10u  /* weight_f (or font_weight) mapped to a named instance */
#define SWR_M08_APPLIED_ITALIC     0x20u

/* swr_measure_result_v08.ignored: requested but NOT done. Never silent. */
#define SWR_M08_IGN_WEIGHT_SNAPPED   0x01u /* exact weight is not a named instance; resolved_weight used */
#define SWR_M08_IGN_WIDTH_AXIS       0x02u
#define SWR_M08_IGN_OPSZ             0x04u
#define SWR_M08_IGN_SLANT            0x08u
#define SWR_M08_IGN_FALLBACK_PRIVATE 0x10u /* a fallback family is not a system family */
#define SWR_M08_IGN_SIM_BOLD_DROPPED 0x20u /* bold simulation forbidden: a real lighter face was used */
#define SWR_M08_IGN_SIM_OBLIQUE_DROPPED 0x40u /* oblique forbidden and no real italic: upright drawn */

/* simulation flags (result.simulations, swr_face_metrics.simulations, swr_run_face.flags) */
#define SWR_SIMFLAG_BOLD    0x1u
#define SWR_SIMFLAG_OBLIQUE 0x2u

typedef struct swr_measure_request_v08 {
    uint32_t struct_size;               /* sizeof(swr_measure_request_v08) = 160 */
    uint32_t flags;                     /* SWR_M08_* */
    swr_measure_request base;           /* the whole 0.6 request (its struct_size = 88);
                                           font_weight is used when weight_f == 0 */
    float    weight_f;                  /* wght; 0 = use base.font_weight; 1..1000 */
    float    width_axis;                /* wdth percent; 0 = default. IGNORED if not 0 or 100 */
    float    opsz;                      /* 0 = automatic. IGNORED if not 0 */
    float    slant;                     /* degrees; 0. IGNORED if not 0 */
    float    tracking_dip;              /* added after every glyph cluster */
    float    kerning_dip;               /* additive, like tracking */
    float    baseline_offset_dip;       /* with SWR_M08_BASELINE_OFFSET: the face's baseline lies this
                                           far below the top of the line box (line_height) */
    uint32_t italic;                    /* 0 / 1 */
    uint32_t simulations;               /* SWR_SIM_FORBID_* */
    uint32_t feature_count;             /* <= SWR_FEATURES_MAX else SWR_E_TOO_LARGE */
    const swr_feature *features;
    const swr_str *fallbacks;           /* system families, first = highest priority */
    uint32_t fallback_count;            /* <= SWR_FALLBACKS_MAX else SWR_E_TOO_LARGE */
    uint32_t reserved;
} swr_measure_request_v08;

typedef struct swr_measure_result_v08 {
    uint32_t struct_size;               /* sizeof(swr_measure_result_v08) = 88 */
    uint32_t reserved0;
    swr_measure_result base;
    uint32_t applied;                   /* SWR_M08_APPLIED_* */
    uint32_t ignored;                   /* SWR_M08_IGN_* */
    float    resolved_weight;           /* the named instance drawn (0 when the family is unknown) */
    uint32_t resolved_italic;           /* 1 when an italic face (real or simulated) is drawn */
    uint32_t simulations;               /* SWR_SIMFLAG_*: simulation the shaper will apply */
    uint32_t reserved;
} swr_measure_result_v08;

/* swr_run_face.flags */
#define SWR_RUNFACE_PRIMARY    0x01u  /* the requested family/weight/style face */
#define SWR_RUNFACE_BUNDLED    0x02u  /* registered bytes: sha256 is their SHA-256 */
#define SWR_RUNFACE_SYSTEM     0x04u  /* installed face (primary): file_name and version set */
#define SWR_RUNFACE_FALLBACK   0x08u  /* a different face than the primary (system fallback) */
#define SWR_RUNFACE_UNRESOLVED 0x10u  /* the renderer could not name this face (family empty) */
#define SWR_RUNFACE_COLOR      0x20u  /* the run holds colour glyphs (emoji) */
#define SWR_RUNFACE_SIM_BOLD   0x40u
#define SWR_RUNFACE_SIM_OBLIQUE 0x80u

typedef struct swr_run_face {           /* one shaped sub-run (same face), 296 bytes */
    uint32_t utf8_start;                /* run-text byte range the sub-run covers */
    uint32_t utf8_len;
    uint32_t glyph_count;
    uint32_t notdef_count;              /* glyphs with id 0 (.notdef) */
    uint32_t flags;                     /* SWR_RUNFACE_* */
    uint32_t weight;                    /* weight of the face drawn (0 unknown) */
    float    ascent;                    /* physical px */
    float    descent;
    float    advance;                   /* physical px, sum of glyph advances before tracking */
    uint32_t reserved;
    uint8_t  sha256[32];                /* bundled: SHA-256 of the registered bytes, else zeros */
    char     family[SWR_NAME_MAX];      /* UTF-8, NUL padded */
    char     ps_name[SWR_NAME_MAX];     /* PostScript name */
    char     version[SWR_VERSION_MAX];  /* system faces: version string */
    char     file_name[SWR_NAME_MAX];   /* system faces: font file name (no directory) */
} swr_run_face;

typedef struct swr_axis_range {
    uint32_t tag;                       /* SWR_TAG */
    float    min_value;
    float    max_value;
    float    default_value;
} swr_axis_range;

/* swr_face_metrics.flags */
#define SWR_FACE_FOUND     0x1u
#define SWR_FACE_VARIABLE  0x2u
#define SWR_FACE_BUNDLED   0x4u

#define SWR_STYLE_NORMAL  0u
#define SWR_STYLE_OBLIQUE 1u
#define SWR_STYLE_ITALIC  2u

typedef struct swr_face_metrics {       /* 456 bytes */
    uint32_t struct_size;               /* IN: sizeof(swr_face_metrics) */
    uint32_t flags;                     /* OUT: SWR_FACE_*; 0 when the family is unknown */
    uint32_t weight;                    /* OUT: weight of the face the request resolves to */
    uint32_t style;                     /* OUT: SWR_STYLE_* of that face */
    uint32_t simulations;               /* OUT: SWR_SIMFLAG_* DirectWrite would apply to the request */
    uint32_t source;                    /* OUT: SWR_FONT_SRC_* */
    int32_t  units_per_em;
    int32_t  hhea_ascent;               /* font units, descent negative as in the table */
    int32_t  hhea_descent;
    int32_t  hhea_line_gap;
    int32_t  typo_ascent;               /* OS/2 sTypo* (0 when the table is absent) */
    int32_t  typo_descent;
    int32_t  typo_line_gap;
    int32_t  win_ascent;                /* OS/2 usWin* */
    int32_t  win_descent;
    int32_t  cap_height;                /* 0 when unknown */
    int32_t  x_height;
    uint32_t axis_count;                /* <= SWR_FACE_AXES_MAX */
    swr_axis_range axes[SWR_FACE_AXES_MAX];
    uint8_t  sha256[32];                /* bundled: SHA-256, else zeros */
    char     family[SWR_NAME_MAX];
    char     ps_name[SWR_NAME_MAX];
    char     version[SWR_VERSION_MAX];
    char     file_name[SWR_NAME_MAX];
} swr_face_metrics;

/* swr_system_fonts.flags: presence of the families the host's font mapping asks about. */
#define SWR_SYSFONT_SEGOE_UI          0x01u
#define SWR_SYSFONT_SEGOE_VARIABLE    0x02u  /* Text, Display and Small all present */
#define SWR_SYSFONT_CASCADIA_MONO     0x04u
#define SWR_SYSFONT_SITKA             0x08u
#define SWR_SYSFONT_SEGOE_EMOJI       0x10u
#define SWR_SYSFONT_SEGOE_FLUENT_ICONS 0x20u

typedef struct swr_system_font_entry {  /* 88 bytes */
    char     name[SWR_SYSFONT_NAME_MAX];/* the family looked up, fixed order below */
    char     version[SWR_VERSION_MAX];  /* version string of its Regular face, "" when absent */
    uint32_t present;
    uint32_t face_count;                /* real faces in the family */
} swr_system_font_entry;

/* entries, in this order: "Segoe UI", "Segoe UI Variable Text", "Segoe UI Variable Display",
 * "Segoe UI Variable Small", "Cascadia Mono", "Sitka Text", "Segoe UI Emoji", "Segoe Fluent Icons". */
typedef struct swr_system_fonts {       /* 720 bytes */
    uint32_t struct_size;               /* IN: sizeof(swr_system_fonts) */
    uint32_t flags;                     /* OUT: SWR_SYSFONT_* */
    uint32_t family_count;              /* OUT: families in the system font set */
    uint32_t reserved;
    swr_system_font_entry entries[SWR_SYSFONT_ENTRIES];
} swr_system_fonts;

/* 0.8 view of swr_bootstrap_info: the 96 bytes of the 0.7 view at identical offsets (abi_minor 8,
 * api_table_size sizeof(swr_api_v08) = 184, fn_count 22), plus the 0.8 size words (120 bytes). */
typedef struct swr_bootstrap_info_v08 {
    swr_bootstrap_info_v07 v07;
    uint32_t measure_request_v08_size;  /* 160 */
    uint32_t measure_result_v08_size;   /* 88 */
    uint32_t run_face_size;             /* 296 */
    uint32_t face_metrics_size;         /* 456 */
    uint32_t system_fonts_size;         /* 720 */
    uint32_t reserved;
} swr_bootstrap_info_v08;

SWR_API swr_status swr_bootstrap_query_v08(swr_bootstrap_info_v08 *out, uint32_t caller_size);

/* UI thread only; E_ABI when request/result struct_size are smaller than the 0.8 structs. A
 * request that breaks a limit is rejected whole (SWR_E_TOO_LARGE / SWR_E_BAD_ARG); nothing is
 * applied partially. */
SWR_API swr_status swr_measure_text_v08(const swr_measure_request_v08 *req, swr_measure_result_v08 *out);

/* Per shaped sub-run of a retained run: the face, simulation flags applied, .notdef count. *count
 * is always the total, `cap` entries are written. Primary-face identity is exact: a bundled
 * family reports the registered SHA-256. A system FALLBACK face is named by matching the glyph ids
 * against candidate system families (gpui does not expose it, G18); when no candidate matches the
 * entry is SWR_RUNFACE_UNRESOLVED with an empty family. UI thread. */
SWR_API swr_status swr_text_run_faces(swr_text_run run, swr_run_face *faces, uint32_t cap, uint32_t *count);

/* Face the request would resolve to (weight snapped to a named instance). width_pct is accepted
 * for the final signature and IGNORED (the normal-width face answers: gpui has no width axis).
 * Bundled families answer from the registered bytes, installed ones from DirectWrite. Does not
 * need a window and may run on any thread (it never touches gpui). An unknown family is SWR_OK
 * with flags 0 (FOUND clear) and source SWR_FONT_SRC_FALLBACK. */
SWR_API swr_status swr_font_face_metrics(const uint8_t *family, uint32_t family_len, uint32_t weight,
                                         uint32_t width_pct, uint32_t italic, swr_face_metrics *out);

/* Same threading as swr_font_face_metrics. */
SWR_API swr_status swr_system_font_info(swr_system_fonts *out);

struct swr_api_v08 {
    uint32_t struct_size;
    uint32_t reserved;
    swr_status (*run)(const swr_run_options *, const swr_host_callbacks *);
    swr_status (*request_quit)(void);
    swr_status (*window_request_close)(swr_window);
    swr_status (*window_get_metrics)(swr_window, swr_window_metrics *);
    swr_status (*commit)(const swr_transaction *);
    swr_status (*measure_text)(const swr_measure_request *, swr_measure_result *);
    swr_status (*text_run_cells)(swr_text_run, swr_char_cell *, uint32_t, uint32_t *);
    swr_status (*text_run_release)(swr_text_run);
    swr_status (*event_pop)(swr_event *);
    swr_status (*request_ticks)(swr_window, int32_t);
    swr_status (*request_modal)(swr_window, const swr_modal_request *);
    swr_status (*selftest_reentry)(void);
    swr_status (*get_stats)(swr_stats *);
    swr_status (*shutdown_complete)(void);
    swr_status (*image_register)(const uint8_t *, uint32_t, uint32_t, uint32_t, swr_image *);
    swr_status (*image_release)(swr_image);
    swr_status (*font_register)(const uint8_t *, uint64_t, swr_font_info *);              /* rev 0.7 */
    swr_status (*font_resolve)(const uint8_t *, uint32_t, swr_font_resolution *);          /* rev 0.7 */
    swr_status (*measure_text_v08)(const swr_measure_request_v08 *, swr_measure_result_v08 *); /* rev 0.8 */
    swr_status (*text_run_faces)(swr_text_run, swr_run_face *, uint32_t, uint32_t *);          /* rev 0.8 */
    swr_status (*font_face_metrics)(const uint8_t *, uint32_t, uint32_t, uint32_t, uint32_t, swr_face_metrics *); /* rev 0.8 */
    swr_status (*system_font_info)(swr_system_fonts *);                                       /* rev 0.8 */
};
typedef struct swr_api_v08 swr_api_v08;

/* Requires caller_size >= sizeof(swr_api_v08) else SWR_E_ABI, nothing written. Future revisions append here. */
SWR_API swr_status swr_get_api_v08(swr_api_v08 *out, uint32_t caller_size);

/* ===========================================================================================
 * REVISION 0.9 (additive): slider role and numeric range (decision H1).
 *
 * Everything above is unchanged. `swr_bootstrap_query`, `_v07` and `_v08` still describe 0.6, 0.7
 * and 0.8, so a 0.6, 0.7 or 0.8 host runs unchanged on a 0.9 renderer. A 0.9 renderer adds two NEW
 * exports, swr_bootstrap_query_v09 and swr_get_api_v09; a 0.8 renderer lacks both, and a 0.9 host
 * then falls back to the 0.8 view with sliders published without a range (typed, never silent).
 *
 * The function table is the 0.8 table (22 functions, 184 bytes): swr_get_api_v09 fills a
 * swr_api_v08. Nothing is added to swr_node or swr_semantic (their sizes are unchanged), because a node array is strided by sizeof(swr_node). The range travels in a TAIL of
 * the transaction instead: a host that sends struct_size >= sizeof(swr_transaction_v09) supplies a
 * table of swr_range_entry, one per slider node upserted by that transaction. A smaller transaction
 * has no table.
 *
 * Rules for the table (all-or-nothing with the rest of the commit, SWR_E_BAD_ARG on a breach): each
 * entry names a node upserted in the same transaction with role SWR_ROLE_SLIDER and has_semantic = 1; at most one
 * entry per node; value, min, max, step, jump finite; min <= max; value within [min, max];
 * step >= 0; jump >= 0; flags == 0. An upsert replaces the node's semantics, so a later transaction
 * that upserts the slider without an entry removes its range.
 *
 * Mapping (accesskit 0.25.1 -> accesskit_windows 0.35.1): value -> numeric_value (UIA RangeValue.Value),
 * min -> min_numeric_value (Minimum), max -> max_numeric_value (Maximum), step -> numeric_value_step
 * (SmallChange), jump -> numeric_value_jump (LargeChange). The Mac counterpart is NSSlider's
 * accessibility value/min/max. UIA SetValue and Increment/Decrement on a slider are NOT routed to
 * the host in 0.9.
 * ===========================================================================================*/
#define SWR_ABI_MINOR_V09 9

typedef struct swr_range_entry {
    swr_node_id id;      /* the slider node, upserted by the same transaction */
    double      value;
    double      min;
    double      max;
    double      step;    /* UIA SmallChange */
    double      jump;    /* UIA LargeChange */
    uint32_t    flags;   /* reserved, 0 */
    uint32_t    reserved;
} swr_range_entry;        /* 56 bytes */

typedef struct swr_transaction_v09 {
    swr_transaction       base;      /* 72 bytes, identical offsets; base.struct_size = sizeof(swr_transaction_v09) */
    const swr_range_entry *ranges;
    uint32_t              range_count;   /* at most upsert_count */
    uint32_t              reserved;
} swr_transaction_v09;               /* 88 bytes */

/* 0.9 view of swr_bootstrap_info: the 120 bytes of the 0.8 view at identical offsets (abi_minor 9,
 * api_table_size sizeof(swr_api_v08) = 184, fn_count 22), plus two size words (128 bytes). */
typedef struct swr_bootstrap_info_v09 {
    swr_bootstrap_info_v08 v08;
    uint32_t range_entry_size;           /* 56 */
    uint32_t transaction_v09_size;       /* 88 */
} swr_bootstrap_info_v09;

SWR_API swr_status swr_bootstrap_query_v09(swr_bootstrap_info_v09 *out, uint32_t caller_size);
/* The 0.8 table (SWR_E_ABI when caller_size < sizeof(swr_api_v08)). */
SWR_API swr_status swr_get_api_v09(swr_api_v08 *out, uint32_t caller_size);

#ifdef __cplusplus
}
#endif

#endif /* SWIFTRIGHT_H */
