/* Standalone proposal layout proof; no renderer/header dependencies. */
#include <stdint.h>
#include <stddef.h>
#ifndef SWR_LAYOUT_FREESTANDING
#include <stdio.h>
#endif
typedef int32_t swr_status;
typedef uint64_t swr_window;
typedef uint64_t swr_frame;
typedef struct { float x,y,w,h; } swr_rect;
typedef struct swr_frame_request {
 uint32_t struct_size,flags; swr_window window; uint64_t min_snapshot,frame_id;
} swr_frame_request;
typedef struct swr_frame_info {
 uint32_t struct_size,flags; uint64_t frame_id,snapshot,paint_seq;
 uint64_t render_completed_ns,presented_ns,clock_id;
 uint32_t width_px,height_px,stride_bytes,pixel_format,color_space,alpha_mode,orientation,occlusion;
 uint64_t bytes_required,rects_drawn,text_runs_drawn,images_drawn,underlines_drawn;
 float scale; uint32_t provider,presented_valid,reserved;
} swr_frame_info;
typedef struct swr_node_geometry {
 uint64_t node,parent; swr_rect bounds,clip;
 uint32_t order,flags; float baseline; uint32_t reserved;
} swr_node_geometry;
typedef struct swr_frame_record {
 uint32_t struct_size,flags; uint64_t seq,frame_id,snapshot,render_completed_ns,presented_ns,clock_id;
 uint32_t outcome,provider,occlusion,reserved;
} swr_frame_record;
typedef struct swr_clock_sample {
 uint32_t struct_size,flags; uint64_t clock_id,raw_ticks,frequency_hz,monotonic_ns,sample_begin_ns,sample_end_ns,uncertainty_ns;
} swr_clock_sample;
/* Prefix occupies 136 bytes: 8-byte table header plus 16 pointers. */
typedef struct swr_api_07_mock {
 uint32_t struct_size,reserved; void (*prefix[16])(void);
 swr_status (*frame_acquire)(const swr_frame_request *,swr_frame *);
 swr_status (*frame_copy)(swr_frame,swr_frame_info *,uint8_t *,uint64_t);
 swr_status (*frame_nodes)(swr_frame,swr_node_geometry *,uint32_t,uint32_t *);
 swr_status (*frame_release)(swr_frame);
 swr_status (*frame_records)(swr_window,uint64_t,swr_frame_record *,uint32_t,uint32_t *,uint64_t *);
 swr_status (*clock_sample)(swr_clock_sample *);
} swr_api_07_mock;
typedef struct swr_bootstrap_07_mock {
 uint32_t prefix[22];
 uint32_t frame_request_size,frame_info_size,node_geometry_size,frame_record_size,clock_sample_size;
} swr_bootstrap_07_mock;
#define CHECK(T,S,A) _Static_assert(sizeof(T)==S,#T " size"); _Static_assert(_Alignof(T)==A,#T " alignment")
#define OFF(T,F,O) _Static_assert(offsetof(T,F)==O,#T "." #F " offset")
CHECK(swr_rect,16,4); CHECK(swr_frame_request,32,8); CHECK(swr_frame_info,144,8);
CHECK(swr_node_geometry,64,8); CHECK(swr_frame_record,72,8); CHECK(swr_clock_sample,64,8);
CHECK(swr_api_07_mock,184,8); CHECK(swr_bootstrap_07_mock,108,4);
OFF(swr_frame_request,window,8); OFF(swr_frame_request,min_snapshot,16); OFF(swr_frame_request,frame_id,24);
OFF(swr_frame_info,frame_id,8); OFF(swr_frame_info,snapshot,16); OFF(swr_frame_info,paint_seq,24);
OFF(swr_frame_info,render_completed_ns,32); OFF(swr_frame_info,presented_ns,40); OFF(swr_frame_info,clock_id,48);
OFF(swr_frame_info,width_px,56); OFF(swr_frame_info,height_px,60); OFF(swr_frame_info,stride_bytes,64);
OFF(swr_frame_info,pixel_format,68); OFF(swr_frame_info,color_space,72); OFF(swr_frame_info,alpha_mode,76);
OFF(swr_frame_info,orientation,80); OFF(swr_frame_info,occlusion,84); OFF(swr_frame_info,bytes_required,88);
OFF(swr_frame_info,rects_drawn,96); OFF(swr_frame_info,text_runs_drawn,104); OFF(swr_frame_info,images_drawn,112);
OFF(swr_frame_info,underlines_drawn,120); OFF(swr_frame_info,scale,128); OFF(swr_frame_info,provider,132);
OFF(swr_frame_info,presented_valid,136); OFF(swr_frame_info,reserved,140);
OFF(swr_node_geometry,parent,8); OFF(swr_node_geometry,bounds,16); OFF(swr_node_geometry,clip,32);
OFF(swr_node_geometry,order,48); OFF(swr_node_geometry,flags,52); OFF(swr_node_geometry,baseline,56); OFF(swr_node_geometry,reserved,60);
OFF(swr_frame_record,seq,8); OFF(swr_frame_record,frame_id,16); OFF(swr_frame_record,snapshot,24);
OFF(swr_frame_record,render_completed_ns,32); OFF(swr_frame_record,presented_ns,40); OFF(swr_frame_record,clock_id,48);
OFF(swr_frame_record,outcome,56); OFF(swr_frame_record,provider,60); OFF(swr_frame_record,occlusion,64); OFF(swr_frame_record,reserved,68);
OFF(swr_clock_sample,clock_id,8); OFF(swr_clock_sample,raw_ticks,16); OFF(swr_clock_sample,frequency_hz,24);
OFF(swr_clock_sample,monotonic_ns,32); OFF(swr_clock_sample,sample_begin_ns,40); OFF(swr_clock_sample,sample_end_ns,48); OFF(swr_clock_sample,uncertainty_ns,56);
OFF(swr_api_07_mock,frame_acquire,136); OFF(swr_api_07_mock,frame_copy,144); OFF(swr_api_07_mock,frame_nodes,152);
OFF(swr_api_07_mock,frame_release,160); OFF(swr_api_07_mock,frame_records,168); OFF(swr_api_07_mock,clock_sample,176);
OFF(swr_bootstrap_07_mock,frame_request_size,88); OFF(swr_bootstrap_07_mock,clock_sample_size,104);
#ifndef SWR_LAYOUT_FREESTANDING
int main(void) {
 puts("PASS: all proposal size/alignment/offset assertions; pointers=64-bit");
 puts("request=32/8 info=144/8 geometry=64/8 record=72/8 clock=64/8 api=184/8 bootstrap=108/4");
 return 0;
}

#endif
