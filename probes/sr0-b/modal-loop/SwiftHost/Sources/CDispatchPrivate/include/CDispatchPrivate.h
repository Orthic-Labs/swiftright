#ifndef CDISPATCH_PRIVATE_H
#define CDISPATCH_PRIVATE_H

/*
 * Private libdispatch SPI, from swift-corelibs-libdispatch private/private.h
 * (lines 204-215) and src/queue.c (_dispatch_get_main_queue_handle_4CF,
 * _dispatch_main_queue_callback_4CF). On _WIN32, dispatch_runloop_handle_t is
 * `void *`: a Win32 auto-reset event HANDLE created with CreateEventW.
 * Exported by dispatch.dll as ordinals 16, 17, 23 (see RESULT.md).
 */

/* Returns the main queue's wake HANDLE (creates the event on first call). */
void *_dispatch_get_main_queue_handle_4CF(void);

/* Same as above; _dispatch_get_main_queue_port_4CF forwards to the handle getter. */
void *_dispatch_get_main_queue_port_4CF(void);

/* Drains the main queue. Must run on the initial (bound) thread. msg is ignored. */
void _dispatch_main_queue_callback_4CF(void *msg);

#endif
