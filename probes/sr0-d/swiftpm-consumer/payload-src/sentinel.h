#ifndef SWIFTRIGHT_SENTINEL_H
#define SWIFTRIGHT_SENTINEL_H

#include <stdint.h>

#if defined(SWR_SENTINEL_BUILD)
#define SWR_API __declspec(dllexport)
#else
#define SWR_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t struct_size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t pointer_width;
    char arch[16];
    uint32_t fn_table_size;
} swr_bootstrap_info;

typedef struct {
    int32_t (*sentinel_add)(int32_t a, int32_t b);
    int32_t (*bootstrap_query)(swr_bootstrap_info* out, uint32_t caller_size);
} swr_fn_table;

SWR_API int32_t swr_bootstrap_query(swr_bootstrap_info* out, uint32_t caller_size);
SWR_API int32_t swr_sentinel_add(int32_t a, int32_t b);

#ifdef __cplusplus
}
#endif

#endif
