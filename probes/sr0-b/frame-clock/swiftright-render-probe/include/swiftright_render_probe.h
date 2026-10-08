#ifndef SWIFTRIGHT_RENDER_PROBE_H
#define SWIFTRIGHT_RENDER_PROBE_H

/*
 * SR0-B frame-clock probe, C ABI 0.2 (probe-only, not frozen).
 * Every entry returns SWR_OK (0) or a negative typed error; no Rust panic
 * crosses this boundary. All callbacks are plain C function pointers with an
 * opaque context; no closures cross the ABI.
 * 0.2 adds the `tick` callback (appended to swr_host_callbacks, guarded by
 * struct_size) and the frame-clock exports below.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SWR_OK              0
#define SWR_ERR_ARGS       -1
#define SWR_ERR_PANIC      -2
#define SWR_ERR_NOT_READY  -3  /* swr_set_wake_handle not called */
#define SWR_ERR_RUNNING    -4  /* loop already running, or handle set after start */
#define SWR_ERR_APP        -5  /* GPUI application or window failed */
#define SWR_ERR_WAKE       -6  /* waiter thread could not start */

typedef struct {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char arch[16];
    uint32_t fn_table_size;
} swr_bootstrap_info;

typedef void (*swr_callback)(void* ctx);
/* Display tick. timestamp_ns is the QPC time (ns) of the presented frame that requested it. */
typedef void (*swr_tick)(void* ctx, uint64_t timestamp_ns);

typedef struct {
    uint32_t struct_size;
    void* ctx;
    swr_callback loop_ready;    /* once, after window exists, outside App borrows */
    swr_callback drain;         /* on UI thread, outside App/Window borrows, non-reentrant */
    swr_callback window_closed; /* once, after the window closed, outside App borrows */
    swr_tick tick;              /* ABI 0.2: on UI thread via the drain path, outside borrows */
} swr_host_callbacks;

int32_t swr_bootstrap_query(swr_bootstrap_info* out, uint32_t caller_size);
int32_t swr_set_wake_handle(void* handle);
int32_t swr_set_timer_resolution(uint32_t ms);   /* timeBeginPeriod; call before swr_run */
int32_t swr_run(const swr_host_callbacks* cb);
int32_t swr_request_quit(void);                  /* thread-safe */
int32_t swr_set_animating(int32_t on);           /* thread-safe; starts/stops the frame chain */
int32_t swr_submit_commit(uint64_t seq);         /* thread-safe; consumed by the next paint */
uint64_t swr_paints(void);                       /* total paints (draws) so far */
uint64_t swr_ticks_requested(void);              /* paints that requested a tick */
int32_t swr_set_dwm_sampler(uint32_t on);        /* 0.2 probe: 1 = DWM sampler on (default), 0 = off; before swr_run */
int32_t swr_selftest_reentry(void);
int32_t swr_dump(const char* dir);               /* writes events.csv and dwm.csv into dir */
int32_t swr_report(const int64_t* enq_qpc, const int64_t* exec_qpc, uint32_t n,
                   const int64_t* windows6);     /* stdout analysis; windows6 = ws,we,ia0,ia1,ib0,ib1 */

#ifdef __cplusplus
}
#endif

#endif
