/* ABI 0.9 layout proof (decision H1: slider role and numeric range): compile-time assertions against the REAL header
 * (render/swiftright-abi/include/swiftright.h, "REVISION 0.9"). The same numbers are asserted in
 * render/swiftright-render/src/abi.rs and packages/SwiftRightBridge/Tests/SwiftRightBridgeTests/SliderRangeTests.swift.
 * Build: clang -std=c99 -Wall -Werror -DSWR_LAYOUT_MAIN abi-0.9-layout-mock.c -o /tmp/x && /tmp/x */
#include <stddef.h>
#include "../../render/swiftright-abi/include/swiftright.h"

#define CHECK(T, SZ, AL) \
  _Static_assert(sizeof(T) == (SZ), #T " size"); \
  _Static_assert(_Alignof(T) == (AL), #T " alignment")
#define OFF(T, F, O) _Static_assert(offsetof(T, F) == (O), #T "." #F " offset")

/* Unchanged: 0.6, 0.7, 0.8 and the node/semantic/transaction layouts. */
CHECK(swr_bootstrap_info, 88, 4); CHECK(swr_api, 136, 8); CHECK(swr_bootstrap_info_v07, 96, 4);
CHECK(swr_bootstrap_info_v08, 120, 4); CHECK(swr_api_v08, 184, 8);
CHECK(swr_transaction, 72, 8); CHECK(swr_semantic, 88, 8);

CHECK(swr_range_entry, 56, 8);
OFF(swr_range_entry, id, 0); OFF(swr_range_entry, value, 8); OFF(swr_range_entry, min, 16); OFF(swr_range_entry, max, 24);
OFF(swr_range_entry, step, 32); OFF(swr_range_entry, jump, 40); OFF(swr_range_entry, flags, 48);
CHECK(swr_transaction_v09, 88, 8);
OFF(swr_transaction_v09, base, 0); OFF(swr_transaction_v09, ranges, 72); OFF(swr_transaction_v09, range_count, 80);
CHECK(swr_bootstrap_info_v09, 128, 4);
OFF(swr_bootstrap_info_v09, v08, 0); OFF(swr_bootstrap_info_v09, range_entry_size, 120); OFF(swr_bootstrap_info_v09, transaction_v09_size, 124);
_Static_assert(SWR_ABI_MINOR == 6 && SWR_ABI_MINOR_V08 == 8 && SWR_ABI_MINOR_V09 == 9 && SWR_ROLE_SLIDER == 15 && SWR_API_V08_FN_COUNT == 22, "revision constants");

#ifdef SWR_LAYOUT_MAIN
#include <stdio.h>
int main(void) { puts("PASS: ABI 0.9 layout assertions"); return 0; }
#endif
