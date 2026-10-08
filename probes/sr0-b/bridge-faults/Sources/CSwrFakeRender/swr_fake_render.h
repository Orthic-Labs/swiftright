/* SR0-B fake renderer ABI v0 (probe). Shared by the C renderer build and the Swift host.
 * Swift side imports this header through a systemLibrary module with NO link directive:
 * the DLL is loaded explicitly (LoadLibraryW/GetProcAddress), never by the import table. */
#ifndef SWR_FAKE_RENDER_H
#define SWR_FAKE_RENDER_H

#include <stdint.h>

#ifdef SWR_BUILD
#define SWR_API __declspec(dllexport)
#else
#define SWR_API
#endif

/* Error codes (negative = typed failure). */
#define SWR_OK               0
#define SWR_E_BAD_ARG       (-1)
#define SWR_E_STALE_HANDLE  (-2)
#define SWR_E_QUEUE_FULL    (-3)
#define SWR_E_TOO_LARGE     (-4)
#define SWR_E_NO_SLOT       (-5)
#define SWR_E_TIMEOUT       (-6)
#define SWR_E_BUSY          (-7)

#define SWR_EVENT_AX_ACTION 1
#define SWR_AX_FOCUS        1
#define SWR_AX_ACTIVATE     2
#define SWR_QUEUE_CAPACITY  256
#define SWR_TEXT_CAPACITY   128

/* Caller-sized bootstrap identity. Only the first struct_size bytes are written. */
typedef struct swr_bootstrap_info {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char     arch[16];
    uint32_t cb_table_size;   /* sizeof(swr_cb_table) as built */
} swr_bootstrap_info;

/* Event record delivered to Swift by swr_drain_events. */
typedef struct swr_event {
    uint32_t kind;
    uint32_t action;
    uint64_t window_gen;
    uint64_t node_handle;
    uint64_t snapshot_version;
    uint64_t seq;             /* assigned by the producer API, unique per accepted post */
} swr_event;

typedef void (*swr_on_ax_fn)(void *ctx, const swr_event *ev);

/* Plain function pointers + opaque ctx. No closures cross the ABI. */
typedef struct swr_cb_table {
    void       *ctx;
    swr_on_ax_fn on_ax_action;
#ifdef SWR_EXTRA_CB_SLOT   /* only the deliberately mismatched variant is built with this */
    swr_on_ax_fn on_reserved;
#endif
} swr_cb_table;

typedef struct swr_stats {
    uint64_t attempts;       /* every swr_post_ax_action call */
    uint64_t posted_ok;      /* enqueued */
    uint64_t posted_full;    /* rejected SWR_E_QUEUE_FULL */
    uint64_t posted_stale;   /* rejected SWR_E_STALE_HANDLE at post time */
    uint64_t posted_bad;     /* rejected SWR_E_BAD_ARG */
    uint64_t drained;        /* records handed to Swift */
    uint64_t max_depth;      /* high-water mark of the queue */
} swr_stats;

SWR_API int32_t  swr_bootstrap_query(swr_bootstrap_info *out, uint32_t caller_size);

SWR_API uint64_t swr_window_open(void);                       /* 0 = busy (one live window) */
SWR_API int32_t  swr_window_close(uint64_t win_gen);          /* bumps generation */

SWR_API uint64_t swr_node_create(uint64_t win_gen);           /* 0 = failure */
SWR_API int32_t  swr_node_release(uint64_t node);
SWR_API int32_t  swr_node_check(uint64_t node);
SWR_API int32_t  swr_node_set_text(uint64_t node, const char *utf8, uint32_t len);
SWR_API int32_t  swr_node_get_text(uint64_t node, char *out, uint32_t cap, uint32_t *len_out);

/* Thread-safe. Only enqueues and signals the wake event; never calls Swift. */
SWR_API int32_t  swr_post_ax_action(uint64_t win_gen, uint64_t node, uint64_t snapshot_version, uint32_t action);

/* Main (UI) thread only. Delivers up to max_records queued events via cb. */
SWR_API int32_t  swr_drain_events(const swr_cb_table *cb, uint32_t max_records);
SWR_API int32_t  swr_wait_wake(uint32_t timeout_ms);
SWR_API void     swr_get_stats(swr_stats *out);

#endif
