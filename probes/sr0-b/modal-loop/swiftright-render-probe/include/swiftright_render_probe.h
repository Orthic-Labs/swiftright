#ifndef SWIFTRIGHT_RENDER_PROBE_H
#define SWIFTRIGHT_RENDER_PROBE_H

/*
 * SR0-B modal-loop probe, C ABI 0.2 (probe-only, not frozen).
 * Every entry returns SWR_OK (0) or a negative typed error; no Rust panic
 * crosses this boundary. Callbacks are plain C function pointers with an
 * opaque context.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SWR_OK              0
#define SWR_ERR_ARGS       -1
#define SWR_ERR_PANIC      -2
#define SWR_ERR_NOT_READY  -3
#define SWR_ERR_RUNNING    -4
#define SWR_ERR_APP        -5
#define SWR_ERR_WAKE       -6

#define SWR_MODAL_TASKDIALOG 1  /* implemented */
#define SWR_MODAL_POPUP      2  /* declared, not implemented: returns SWR_ERR_ARGS */

#define SWR_PHASE_SIZING 1
#define SWR_PHASE_MODAL  2

#define SWR_UI_TAG_AX           1
#define SWR_UI_TAG_MODAL_RESULT 2
#define SWR_ACTION_CLICK        1

typedef struct {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char arch[16];
    uint32_t fn_table_size;
} swr_bootstrap_info;

typedef void (*swr_callback)(void* ctx);

typedef struct {
    uint32_t struct_size;
    void* ctx;
    swr_callback loop_ready;    /* once, after window exists */
    swr_callback drain;         /* guarded, non-reentrant */
    swr_callback tick;          /* 16 ms frame clock, guarded */
    swr_callback window_closed; /* once, after close, guarded */
} swr_host_callbacks;

typedef struct {
    uint32_t tag;          /* SWR_UI_TAG_AX or SWR_UI_TAG_MODAL_RESULT */
    uint32_t action;       /* AX: SWR_ACTION_CLICK or 0; modal: kind */
    int32_t value;         /* modal: dialog button id, -1 on error */
    uint32_t pad;
    uint64_t window_gen;
    uint64_t node_id;
    uint64_t snapshot_version;
} swr_ui_record;

/* Counter indices for swr_stat(). */
enum {
    SWR_STAT_AX_ATTEMPTS = 0,
    SWR_STAT_AX_ENQUEUED = 1,
    SWR_STAT_AX_FULL = 2,
    SWR_STAT_AX_REJECTED_POST = 3,
    SWR_STAT_AX_POPPED_APPLIED = 4,
    SWR_STAT_AX_POPPED_STALE = 5,
    SWR_STAT_AX_ENQ_WHILE_CLOSED = 6,
    SWR_STAT_AX_APPLIED_AFTER_CLOSE = 7,
    SWR_STAT_QUEUE_LEN = 8,
    SWR_STAT_DRAIN_CALLS = 9,
    SWR_STAT_DRAINS_IDLE = 10,
    SWR_STAT_DRAINS_SIZING = 11,
    SWR_STAT_DRAINS_MODAL = 12,
    SWR_STAT_DRAINS_BOTH = 13,
    SWR_STAT_DEFERRED = 14,
    SWR_STAT_NESTED_EXECUTED = 15,
    SWR_STAT_PANICS = 16,
    SWR_STAT_MODAL_REQUESTS = 17,
    SWR_STAT_MODAL_OPENED = 18,
    SWR_STAT_MODAL_RESULTS = 19,
    SWR_STAT_MODAL_ERRORS = 20,
    SWR_STAT_SIZE_ENTER = 21,
    SWR_STAT_SIZE_EXIT = 22,
    SWR_STAT_FRAMES = 23,
    SWR_STAT_TICKS = 24,
    SWR_STAT_WAKE_SIGNALS = 25,
    SWR_STAT_WAKE_WAIT_FAILURES = 26,
    SWR_STAT_SELFTEST_DETECTED = 27,
    SWR_STAT_NC_LBUTTON_DOWN = 28,
    SWR_STAT_NC_LAST_HITTEST = 29
};

int32_t swr_bootstrap_query(swr_bootstrap_info* out, uint32_t caller_size);
int32_t swr_set_wake_handle(void* handle);
int32_t swr_run(const swr_host_callbacks* cb);
int32_t swr_request_quit(void);
int32_t swr_request_modal(uint32_t kind);
int32_t swr_ax_pop(swr_ui_record* out);
uint32_t swr_phase(void);
uint64_t swr_frames_rendered(void);
uint64_t swr_stat(uint32_t index);
int32_t swr_selftest_reentry(void);

#ifdef __cplusplus
}
#endif

#endif
