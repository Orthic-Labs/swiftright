/* ABI 0.8 layout proof: compile-time size / offset assertions against the REAL header
 * (render/swiftright-abi/include/swiftright.h, revision 0.8 text extension, minimal form).
 * The same numbers are asserted in render/swiftright-render/src/abi.rs (Rust side) and
 * packages/SwiftRightBridge/Tests/SwiftRightBridgeTests/TextExtensionTests.swift (Swift side).
 * Build: clang -std=c99 -Wall -Werror -c abi-0.8-layout-mock.c  (or run: add -DSWR_LAYOUT_MAIN). */
#include <stddef.h>
#include "../../render/swiftright-abi/include/swiftright.h"

#define CHECK(T, SZ, AL) \
  _Static_assert(sizeof(T) == (SZ), #T " size"); \
  _Static_assert(_Alignof(T) == (AL), #T " alignment")
#define OFF(T, F, O) _Static_assert(offsetof(T, F) == (O), #T "." #F " offset")

/* 0.6 and 0.7 stay exactly as they were. */
CHECK(swr_bootstrap_info, 88, 4); CHECK(swr_api, 136, 8);
CHECK(swr_bootstrap_info_v07, 96, 4); CHECK(swr_api_v07, 152, 8);
CHECK(swr_measure_request, 88, 8); CHECK(swr_measure_result, 56, 8);

CHECK(swr_feature, 8, 4); CHECK(swr_str, 16, 8);
CHECK(swr_measure_request_v08, 160, 8);
OFF(swr_measure_request_v08, flags, 4); OFF(swr_measure_request_v08, base, 8);
OFF(swr_measure_request_v08, weight_f, 96); OFF(swr_measure_request_v08, width_axis, 100);
OFF(swr_measure_request_v08, opsz, 104); OFF(swr_measure_request_v08, slant, 108);
OFF(swr_measure_request_v08, tracking_dip, 112); OFF(swr_measure_request_v08, kerning_dip, 116);
OFF(swr_measure_request_v08, baseline_offset_dip, 120); OFF(swr_measure_request_v08, italic, 124);
OFF(swr_measure_request_v08, simulations, 128); OFF(swr_measure_request_v08, feature_count, 132);
OFF(swr_measure_request_v08, features, 136); OFF(swr_measure_request_v08, fallbacks, 144);
OFF(swr_measure_request_v08, fallback_count, 152);
CHECK(swr_measure_result_v08, 88, 8);
OFF(swr_measure_result_v08, base, 8); OFF(swr_measure_result_v08, applied, 64);
OFF(swr_measure_result_v08, ignored, 68); OFF(swr_measure_result_v08, resolved_weight, 72);
OFF(swr_measure_result_v08, resolved_italic, 76); OFF(swr_measure_result_v08, simulations, 80);
CHECK(swr_run_face, 296, 4);
OFF(swr_run_face, glyph_count, 8); OFF(swr_run_face, notdef_count, 12); OFF(swr_run_face, flags, 16);
OFF(swr_run_face, weight, 20); OFF(swr_run_face, ascent, 24); OFF(swr_run_face, advance, 32);
OFF(swr_run_face, sha256, 40); OFF(swr_run_face, family, 72); OFF(swr_run_face, ps_name, 136);
OFF(swr_run_face, version, 200); OFF(swr_run_face, file_name, 232);
CHECK(swr_axis_range, 16, 4);
CHECK(swr_face_metrics, 456, 4);
OFF(swr_face_metrics, weight, 8); OFF(swr_face_metrics, units_per_em, 24); OFF(swr_face_metrics, hhea_ascent, 28);
OFF(swr_face_metrics, cap_height, 60); OFF(swr_face_metrics, x_height, 64); OFF(swr_face_metrics, axis_count, 68);
OFF(swr_face_metrics, axes, 72); OFF(swr_face_metrics, sha256, 200); OFF(swr_face_metrics, family, 232);
OFF(swr_face_metrics, ps_name, 296); OFF(swr_face_metrics, version, 360); OFF(swr_face_metrics, file_name, 392);
CHECK(swr_system_font_entry, 88, 4);
OFF(swr_system_font_entry, version, 48); OFF(swr_system_font_entry, present, 80); OFF(swr_system_font_entry, face_count, 84);
CHECK(swr_system_fonts, 720, 4); OFF(swr_system_fonts, entries, 16);
CHECK(swr_bootstrap_info_v08, 120, 4);
OFF(swr_bootstrap_info_v08, measure_request_v08_size, 96); OFF(swr_bootstrap_info_v08, measure_result_v08_size, 100);
OFF(swr_bootstrap_info_v08, run_face_size, 104); OFF(swr_bootstrap_info_v08, face_metrics_size, 108);
OFF(swr_bootstrap_info_v08, system_fonts_size, 112);
CHECK(swr_api_v08, 184, 8);
OFF(swr_api_v08, image_release, 128); OFF(swr_api_v08, font_register, 136); OFF(swr_api_v08, font_resolve, 144);
OFF(swr_api_v08, measure_text_v08, 152); OFF(swr_api_v08, text_run_faces, 160);
OFF(swr_api_v08, font_face_metrics, 168); OFF(swr_api_v08, system_font_info, 176);
_Static_assert(SWR_ABI_MINOR == 6 && SWR_ABI_MINOR_V08 == 8 && SWR_API_V08_FN_COUNT == 22, "revision constants");
_Static_assert(SWR_TAG('k','e','r','n') == 0x6B65726Eu, "tag packing");

#ifdef SWR_LAYOUT_MAIN
#include <stdio.h>
int main(void) { puts("PASS: ABI 0.8 layout assertions"); return 0; }
#endif
