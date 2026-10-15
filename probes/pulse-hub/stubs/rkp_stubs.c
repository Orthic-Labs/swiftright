// Probe-only link stubs for the rkp_* / rke_* symbols of the Rust staticlib (swift/RightKitHub/native),
// which is NOT built here. The fixtures never call it; these definitions only satisfy the linker.
// Every function returns a nonzero status (-1) and leaves its outputs untouched.
#include "rightkit_engine.h"

int32_t rkp_versions(RkpVersions *out) { (void)out; return -1; }
int32_t rkp_register_snapshot(const uint8_t *snapshot, size_t len, uint64_t generation, RkpError *err) { (void)snapshot; (void)len; (void)generation; (void)err; return -1; }
int32_t rkp_host_start(uint64_t *out_host, RkpError *err) { (void)out_host; (void)err; return -1; }
int32_t rkp_host_snapshot(uint64_t host, uint64_t *out_generation, uint32_t *out_lifecycle, RkpBuf *out_payload, RkpError *err) { (void)host; (void)out_generation; (void)out_lifecycle; (void)out_payload; (void)err; return -1; }
int32_t rkp_host_call(uint64_t host, const uint8_t *method, size_t method_len, const uint8_t *params, size_t params_len, uint32_t resume, uint64_t timeout_ms, RkpEventFn on_event, void *ctx, RkpBuf *out, RkpError *err) { (void)host; (void)method; (void)method_len; (void)params; (void)params_len; (void)resume; (void)timeout_ms; (void)on_event; (void)ctx; (void)out; (void)err; return -1; }
int32_t rkp_host_lifecycle(uint64_t host, int32_t since, uint64_t timeout_ms, int32_t *out_lifecycle, RkpError *err) { (void)host; (void)since; (void)timeout_ms; (void)out_lifecycle; (void)err; return -1; }
int32_t rkp_host_shutdown(uint64_t host, uint64_t budget_ms, uint32_t *out_outcome, uint64_t *out_unreaped, RkpError *err) { (void)host; (void)budget_ms; (void)out_outcome; (void)out_unreaped; (void)err; return -1; }
int32_t rkp_service_connect(uint64_t host, uint64_t timeout_ms, uint64_t *out_conn, RkpError *err) { (void)host; (void)timeout_ms; (void)out_conn; (void)err; return -1; }
int32_t rkp_service_call(uint64_t conn, const uint8_t *method, size_t method_len, const uint8_t *params, size_t params_len, uint64_t timeout_ms, RkpBuf *out, RkpError *err) { (void)conn; (void)method; (void)method_len; (void)params; (void)params_len; (void)timeout_ms; (void)out; (void)err; return -1; }
void rkp_release_host(uint64_t host) { (void)host; }
void rkp_release_connection(uint64_t conn) { (void)conn; }
void rkp_buf_free(RkpBuf *buf) { (void)buf; }
int32_t rke_install_engine(const char *engine_path, const char *const *args, size_t argc, const char *const *env_keys, size_t env_count, const char *snapshot_method, uint32_t start_budget_ms, RkpError *err) { (void)engine_path; (void)args; (void)argc; (void)env_keys; (void)env_count; (void)snapshot_method; (void)start_budget_ms; (void)err; return -1; }
