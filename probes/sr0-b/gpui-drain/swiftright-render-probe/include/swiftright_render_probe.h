#ifndef SWIFTRIGHT_RENDER_PROBE_H
#define SWIFTRIGHT_RENDER_PROBE_H

/*
 * SR0-B drain probe, C ABI 0.2 (probe-only, not frozen).
 * Every entry returns SWR_OK (0) or a negative typed error; no Rust panic
 * crosses this boundary. All callbacks are plain C function pointers with an
 * opaque context; no closures cross the ABI.
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
#define SWR_ERR_STALE      -7  /* target generation / node is gone */
#define SWR_ERR_FULL       -8  /* job queue at capacity */

typedef struct {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char arch[16];
    uint32_t fn_table_size;
} swr_bootstrap_info;

typedef void (*swr_callback)(void* ctx);
typedef void (*swr_job_callback)(void* ctx, uint64_t node, uint64_t token);

typedef struct {
    uint32_t struct_size;
    void* ctx;
    swr_callback loop_ready;    /* once, after window exists, outside App borrows */
    swr_callback drain;         /* on UI thread, outside App/Window borrows, non-reentrant */
    swr_callback window_closed; /* once, after the window closed, outside App borrows */
    swr_job_callback job;       /* UI thread; only while the job's generation and node are live */
} swr_host_callbacks;

int32_t swr_bootstrap_query(swr_bootstrap_info* out, uint32_t caller_size);
int32_t swr_set_wake_handle(void* handle);
int32_t swr_run(const swr_host_callbacks* cb);
int32_t swr_request_quit(void);
uint64_t swr_frames_rendered(void);
int32_t swr_selftest_reentry(void);

/* Late-dispatch fault surface. */
typedef struct {
    uint32_t struct_size;
    uint32_t reserved;
    uint64_t window_gen;
    uint64_t posted_ok;
    uint64_t delivered;
    uint64_t dropped_at_close;
    uint64_t dropped_at_deliver;
    uint64_t rejected_closed;
    uint64_t rejected_stale_gen;
    uint64_t rejected_stale_node;
    uint64_t rejected_full;
} swr_late_stats_t;

uint64_t swr_window_generation(void);
int32_t swr_node_set(uint64_t node, int32_t live);
int32_t swr_post_job(uint64_t generation, uint64_t node, uint64_t token);
int32_t swr_late_stats(swr_late_stats_t* out, uint32_t caller_size);

#ifdef __cplusplus
}
#endif

#endif
