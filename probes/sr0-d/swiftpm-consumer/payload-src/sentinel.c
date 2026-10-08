#define SWR_SENTINEL_BUILD
#include "sentinel.h"
#include <string.h>
#include <stddef.h>

SWR_API int32_t swr_bootstrap_query(swr_bootstrap_info* out, uint32_t caller_size) {
    if (out == NULL || caller_size < (uint32_t)sizeof(swr_bootstrap_info)) {
        return -1;
    }
    out->struct_size = (uint32_t)sizeof(swr_bootstrap_info);
    out->abi_major = 0;
    out->abi_minor = 1;
    out->pointer_width = (uint32_t)(sizeof(void*) * 8);
    {
        static const char arch_name[] = "x86_64";
        size_t i;
        memset(out->arch, 0, sizeof out->arch);
        for (i = 0; i + 1 < sizeof out->arch && arch_name[i] != 0; i++) {
            out->arch[i] = arch_name[i];
        }
    }
    out->fn_table_size = (uint32_t)sizeof(swr_fn_table);
    return 0;
}

SWR_API int32_t swr_sentinel_add(int32_t a, int32_t b) {
    return a + b;
}
