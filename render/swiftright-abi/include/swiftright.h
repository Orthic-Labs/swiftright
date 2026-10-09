/*
 * swiftright.h - SwiftRight renderer bridge, C ABI v0 (revision 0.4).
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
 *   - Handles (swr_window, swr_text_run) are opaque 64-bit values: low 32 bits slot,
 *     high 32 bits generation. 0 is never valid. A handle is valid from the call
 *     that returned it until it is explicitly released (swr_text_run_release) or its
 *     owner dies (window closed). A stale handle fails with SWR_E_STALE_HANDLE and
 *     never touches a reused slot. swr_text_run handles are RETAINED by the caller
 *     until swr_text_run_release (owner frees).
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
#define SWR_ABI_MINOR 5

/* Longest accepted swr_semantic.identifier, in UTF-8 bytes. Longer -> SWR_E_TOO_LARGE. */
#define SWR_IDENTIFIER_MAX 256

/* Post-close pump bound (rev 0.5): after window_closed the renderer drains for at most
 * this long unless swr_shutdown_complete() ends the phase first. */
#define SWR_POST_CLOSE_TIMEOUT_MS 5000

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
#define SWR_PRIM_IMAGE           3  /* declared; SWR_E_UNSUPPORTED in v0 */
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
    uint32_t     image_id;          /* IMAGE: reserved */
    swr_text_run text_run;          /* TEXT_RUN: handle from swr_measure_text */
    float        m[6];              /* TRANSFORM_PUSH */
    uint32_t     reserved[2];
} swr_primitive;

#define SWR_ROLE_NONE       0
#define SWR_ROLE_WINDOW     1
#define SWR_ROLE_BUTTON     2
#define SWR_ROLE_STATIC_TEXT 3
#define SWR_ROLE_TEXT_FIELD 4
#define SWR_ROLE_LIST       5
#define SWR_ROLE_LIST_ITEM  6
#define SWR_ROLE_GROUP      7

#define SWR_ACT_INVOKE         0x1u
#define SWR_ACT_FOCUS          0x2u
#define SWR_ACT_SET_VALUE      0x4u
#define SWR_ACT_SET_SELECTION  0x8u

#define SWR_SEM_HAS_SELECTION  0x1u
#define SWR_SEM_MULTILINE      0x2u
#define SWR_SEM_DISABLED       0x4u

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
    uint32_t               reserved;
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
    const char    *text;            /* UTF-8, single paragraph (no '\n'/'\r' in v0) */
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
#define SWR_MODAL_BUTTONS_OK        1
#define SWR_MODAL_BUTTONS_OK_CANCEL 2
#define SWR_MODAL_BUTTONS_YES_NO    3
#define SWR_MODAL_RESULT_OK     1
#define SWR_MODAL_RESULT_CANCEL 2
#define SWR_MODAL_RESULT_YES    6
#define SWR_MODAL_RESULT_NO     7

typedef struct swr_modal_request {
    uint32_t    struct_size;
    uint32_t    kind;               /* SWR_MODAL_* */
    uint64_t    request_id;         /* echoed in the result event */
    const char *title;              /* UTF-8, borrowed */
    const char *message;
    uint32_t    title_len;
    uint32_t    message_len;
    uint32_t    buttons;            /* SWR_MODAL_BUTTONS_* */
    uint32_t    reserved;
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
     * committed tree plus live (unreleased) swr_text_run handles. Zero after teardown.
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
};

#define SWR_API_FN_COUNT 14

#ifdef __cplusplus
}
#endif

#endif /* SWIFTRIGHT_H */
