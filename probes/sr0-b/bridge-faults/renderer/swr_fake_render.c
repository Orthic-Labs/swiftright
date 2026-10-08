/* SR0-B fake renderer (C stand-in for the Rust renderer). Built as swr_fake_render.dll (MSVC x64).
 * Variant knobs (compile-time, for mismatch tests):
 *   /DSWR_REPORT_MAJOR=1        reports abi major 1 (major mismatch variant)
 *   /DSWR_EXTRA_CB_SLOT         header adds a callback slot -> cb table size mismatch variant
 */
#include "swr_fake_render.h"
#include <windows.h>
#include <string.h>

#ifndef SWR_REPORT_MAJOR
#define SWR_REPORT_MAJOR 0
#endif
#ifndef SWR_REPORT_MINOR
#define SWR_REPORT_MINOR 1
#endif

#define NODE_SLOTS 64

typedef struct node_slot {
    uint32_t gen;
    int      used;
    uint64_t win_gen;
    uint32_t len;
    char     text[SWR_TEXT_CAPACITY];
} node_slot;

/* One lock guards every table, the queue and the counters. Post holds it only to enqueue. */
static SRWLOCK     g_lock = SRWLOCK_INIT;
static HANDLE      g_wake = NULL;
static uint64_t    g_gen_counter = 0;   /* monotonic window generation source */
static uint64_t    g_live = 0;          /* live window generation, 0 = none */
static node_slot   g_nodes[NODE_SLOTS];
static swr_event   g_q[SWR_QUEUE_CAPACITY];
static uint32_t    g_head = 0;
static uint32_t    g_count = 0;
static uint64_t    g_seq = 0;
static swr_stats   g_stats;

static uint64_t make_handle(uint32_t idx, uint32_t gen) {
    return ((uint64_t)gen << 32) | (uint64_t)idx;
}

/* Caller holds g_lock. */
static int node_valid_locked(uint64_t h) {
    uint32_t idx = (uint32_t)(h & 0xFFFFFFFFu);
    uint32_t gen = (uint32_t)(h >> 32);
    node_slot *n;
    if (h == 0 || idx >= NODE_SLOTS) {
        return 0;
    }
    n = &g_nodes[idx];
    if (!n->used || n->gen != gen) {
        return 0;
    }
    return g_live != 0 && n->win_gen == g_live;
}

SWR_API int32_t swr_bootstrap_query(swr_bootstrap_info *out, uint32_t caller_size) {
    static const char arch_name[] =
#if defined(_M_ARM64)
        "arm64";
#else
        "x86_64";
#endif
    if (out == NULL || caller_size < (uint32_t)sizeof(swr_bootstrap_info)) {
        return SWR_E_BAD_ARG;
    }
    out->struct_size = (uint32_t)sizeof(swr_bootstrap_info);
    out->abi_major = SWR_REPORT_MAJOR;
    out->abi_minor = SWR_REPORT_MINOR;
    out->pointer_width = (uint32_t)(sizeof(void *) * 8u);
    memset(out->arch, 0, sizeof out->arch);
    memcpy(out->arch, arch_name, sizeof arch_name);
    out->cb_table_size = (uint32_t)sizeof(swr_cb_table);
    return SWR_OK;
}

SWR_API uint64_t swr_window_open(void) {
    uint64_t r = 0;
    AcquireSRWLockExclusive(&g_lock);
    if (g_live == 0) {
        g_gen_counter++;
        g_live = g_gen_counter;
        r = g_live;
    }
    if (g_wake == NULL) {
        g_wake = CreateEventW(NULL, FALSE, FALSE, NULL);
    }
    ReleaseSRWLockExclusive(&g_lock);
    return r;
}

SWR_API int32_t swr_window_close(uint64_t win_gen) {
    int32_t rc = SWR_OK;
    uint32_t i;
    AcquireSRWLockExclusive(&g_lock);
    if (win_gen == 0 || win_gen != g_live) {
        rc = SWR_E_STALE_HANDLE;
    } else {
        /* Release every node of the closing window: its slots are reused under a new generation. */
        for (i = 0; i < NODE_SLOTS; i++) {
            if (g_nodes[i].used && g_nodes[i].win_gen == g_live) {
                g_nodes[i].used = 0;
                g_nodes[i].gen++;
            }
        }
        g_live = 0;
        g_gen_counter++;   /* generation bump: nothing minted for the old window stays valid */
    }
    ReleaseSRWLockExclusive(&g_lock);
    return rc;
}

SWR_API uint64_t swr_node_create(uint64_t win_gen) {
    uint64_t h = 0;
    uint32_t i;
    AcquireSRWLockExclusive(&g_lock);
    if (win_gen != 0 && win_gen == g_live) {
        for (i = 0; i < NODE_SLOTS; i++) {
            node_slot *n = &g_nodes[i];
            if (!n->used) {
                if (n->gen == 0) {
                    n->gen = 1;
                }
                n->used = 1;
                n->win_gen = win_gen;
                n->len = 0;
                n->text[0] = '\0';
                h = make_handle(i, n->gen);
                break;
            }
        }
    }
    ReleaseSRWLockExclusive(&g_lock);
    return h;
}

SWR_API int32_t swr_node_release(uint64_t h) {
    int32_t rc;
    uint32_t idx = (uint32_t)(h & 0xFFFFFFFFu);
    if (h == 0) {
        return SWR_E_BAD_ARG;
    }
    AcquireSRWLockExclusive(&g_lock);
    if (!node_valid_locked(h)) {
        rc = SWR_E_STALE_HANDLE;
    } else {
        g_nodes[idx].used = 0;
        g_nodes[idx].gen++;
        rc = SWR_OK;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return rc;
}

SWR_API int32_t swr_node_check(uint64_t h) {
    int32_t rc;
    if (h == 0) {
        return SWR_E_BAD_ARG;
    }
    AcquireSRWLockExclusive(&g_lock);
    rc = node_valid_locked(h) ? SWR_OK : SWR_E_STALE_HANDLE;
    ReleaseSRWLockExclusive(&g_lock);
    return rc;
}

SWR_API int32_t swr_node_set_text(uint64_t h, const char *utf8, uint32_t len) {
    int32_t rc;
    uint32_t idx = (uint32_t)(h & 0xFFFFFFFFu);
    if (utf8 == NULL && len != 0) {
        return SWR_E_BAD_ARG;
    }
    if (len >= SWR_TEXT_CAPACITY) {
        return SWR_E_TOO_LARGE;
    }
    AcquireSRWLockExclusive(&g_lock);
    if (!node_valid_locked(h)) {
        rc = SWR_E_STALE_HANDLE;
    } else {
        if (len > 0) {
            memcpy(g_nodes[idx].text, utf8, len);
        }
        g_nodes[idx].text[len] = '\0';
        g_nodes[idx].len = len;
        rc = SWR_OK;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return rc;
}

SWR_API int32_t swr_node_get_text(uint64_t h, char *out, uint32_t cap, uint32_t *len_out) {
    int32_t rc;
    uint32_t idx = (uint32_t)(h & 0xFFFFFFFFu);
    if (out == NULL || len_out == NULL) {
        return SWR_E_BAD_ARG;
    }
    AcquireSRWLockExclusive(&g_lock);
    if (!node_valid_locked(h)) {
        rc = SWR_E_STALE_HANDLE;
    } else if (cap < g_nodes[idx].len + 1u) {
        rc = SWR_E_TOO_LARGE;
    } else {
        memcpy(out, g_nodes[idx].text, g_nodes[idx].len + 1u);
        *len_out = g_nodes[idx].len;
        rc = SWR_OK;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return rc;
}

/* Callable from any thread. Never calls Swift: it only enqueues and signals the wake event. */
SWR_API int32_t swr_post_ax_action(uint64_t win_gen, uint64_t node, uint64_t snapshot_version, uint32_t action) {
    int32_t rc;
    int signal = 0;
    uint32_t slot;
    (void)snapshot_version;   /* snapshot checks are Swift-owned; the record carries the tag */
    AcquireSRWLockExclusive(&g_lock);
    g_stats.attempts++;
    if (action != SWR_AX_FOCUS && action != SWR_AX_ACTIVATE) {
        rc = SWR_E_BAD_ARG;
        g_stats.posted_bad++;
    } else if (win_gen == 0 || win_gen != g_live || !node_valid_locked(node)) {
        rc = SWR_E_STALE_HANDLE;
        g_stats.posted_stale++;
    } else if (g_count >= SWR_QUEUE_CAPACITY) {
        rc = SWR_E_QUEUE_FULL;
        g_stats.posted_full++;
    } else {
        slot = (g_head + g_count) % SWR_QUEUE_CAPACITY;
        g_q[slot].kind = SWR_EVENT_AX_ACTION;
        g_q[slot].action = action;
        g_q[slot].window_gen = win_gen;
        g_q[slot].node_handle = node;
        g_q[slot].snapshot_version = snapshot_version;
        g_q[slot].seq = ++g_seq;
        g_count++;
        if (g_count > g_stats.max_depth) {
            g_stats.max_depth = g_count;
        }
        g_stats.posted_ok++;
        rc = SWR_OK;
        signal = 1;
    }
    ReleaseSRWLockExclusive(&g_lock);
    if (signal && g_wake != NULL) {
        SetEvent(g_wake);
    }
    return rc;
}

/* Main (UI) thread only. Records are copied out under the lock and delivered with the lock released,
 * so a Swift callback may call back into the bridge (node_check, get_text) without deadlock. */
SWR_API int32_t swr_drain_events(const swr_cb_table *cb, uint32_t max_records) {
    swr_event batch[64];
    uint32_t want, n = 0, i;
    if (cb == NULL || cb->on_ax_action == NULL || max_records == 0) {
        return SWR_E_BAD_ARG;
    }
    want = max_records < 64u ? max_records : 64u;
    AcquireSRWLockExclusive(&g_lock);
    while (n < want && g_count > 0) {
        batch[n++] = g_q[g_head];
        g_head = (g_head + 1) % SWR_QUEUE_CAPACITY;
        g_count--;
    }
    g_stats.drained += n;
    ReleaseSRWLockExclusive(&g_lock);
    for (i = 0; i < n; i++) {
        cb->on_ax_action(cb->ctx, &batch[i]);
    }
    return (int32_t)n;
}

SWR_API int32_t swr_wait_wake(uint32_t timeout_ms) {
    HANDLE h;
    DWORD r;
    AcquireSRWLockExclusive(&g_lock);
    h = g_wake;
    ReleaseSRWLockExclusive(&g_lock);
    if (h == NULL) {
        return SWR_E_BAD_ARG;
    }
    r = WaitForSingleObject(h, (DWORD)timeout_ms);
    if (r == WAIT_OBJECT_0) {
        return SWR_OK;
    }
    if (r == WAIT_TIMEOUT) {
        return SWR_E_TIMEOUT;
    }
    return SWR_E_BAD_ARG;
}

SWR_API void swr_get_stats(swr_stats *out) {
    if (out == NULL) {
        return;
    }
    AcquireSRWLockExclusive(&g_lock);
    *out = g_stats;
    ReleaseSRWLockExclusive(&g_lock);
}
