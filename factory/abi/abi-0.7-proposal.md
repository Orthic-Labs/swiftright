# ABI 0.7 proposal — HELD

Proposal only, following ABI 0.6 freeze. `render/`, bridge ABI, headers & implementation remain HELD until `docs/sr0-status.md` explicitly records SR0 **CLOSED**, expected tuple10. Tuple10 staging, proposal approval or factory receipts do not substitute for closure. No current qualification changes follow from this document.

## Evidence & scope

Read-only inputs: `render/swiftright-abi/include/swiftright.h`, identical `packages/SwiftRightBridge/Sources/CSwiftRight/swiftright.h`, Swift `Loader.swift`, `Bridge.swift` validation/marshalling, `factory/spec/schema/capture.schema.json`, `factory/native/windows/{README.md,adapter.py,capture-native.ps1}`, `examples/BridgeSmoke/result-bridgepixels09.txt`.

ABI0.6 has 16 table entries, no renderer frame readback, committed-node geometry export or per-frame presentation history. `tick(timestamp_ns)` coalesces; `stats.paints` counts paints without proving which primitives drew. Factory adapter's fixed-advance headless layout is observational; screen/UIA observations stay independent from provider evidence. Proposed exports supply applied geometry, actual draw receipt, pixels & clock records without new drawing primitives, callbacks, native layout engine or synthetic fixture API.

F7 capture implementation reuse: Smoke09 PrintWindow `PW_RENDERFULLCONTENT` plus screen capture works for visible foreground runs; all ten receipt rows say `fg=True`, `occluded=False`, `pw_pass=True`, `screen_pass=True`. Reuse those capture paths, hash binding & comparisons. Those rows certify neither background nor occluded behavior. Factory background screen crops remain observed desktop pixels with unqualified occlusion. Proposed GPU readback is its own provider channel, never renamed PrintWindow/compositor evidence.

## Compatibility & negotiation

Keep major0; minor becomes7 only after closure/freeze. Preserve every ABI0.6 field, offset, enum, callback, ownership rule & function signature. Append five size words to `swr_bootstrap_info`, six pointers to `swr_api`; keep all other existing structs unchanged. Do not repurpose reserved slots. `swr_frame` is a new opaque `uint64_t` generation handle.

Retain **exact major/minor** validation. Current0.6 Swift loader rejects0.7 before table access;0.7 loader rejects0.6. Append-only layout does not promise cross-minor binary compatibility. `swr_bootstrap_query` remains caller-bounded & allocation/thread/callback-free: return `struct_size=108`, `api_table_size=184`, `fn_count=22`, `abi_minor=7`; never write beyond caller_size. Existing88-byte callers can read minor then refuse safely.0.7 loader requires full108-byte bootstrap, pointer_width64, supported arch & all size values before resolving/getting API.

Bootstrap tail: `uint32_t frame_request_size@88=32, frame_info_size@92=144, node_geometry_size@96=64, frame_record_size@100=72, clock_sample_size@104=64`. Alignment4, total108. Supported runtime target remains Windows x64; arm64 layout proof supports fixed-layout reasoning, not Windows arm64 qualification. Mac arm64 oracle remains native SwiftUI.

`get_api(out,caller_size)` must receive184 bytes from0.7 hosts; reject smaller tables with `SWR_E_ABI`, no writes. Table `struct_size=184`, reserved0, no NULL appended pointers; unsupported presentation feedback reports status/validity through implemented exports. Later minor revisions repeat exact-version handshake, append tails & advertise sizes; breaking existing layouts require new major. No optional capabilities registry is needed for this bounded revision.

Indices below are zero-based; table header is8 bytes, pointer width8.

| Index | Offset | Table member / C export | Signature |
|---|---:|---|---|
|0–15|8–128|Existing run through image_release|Unchanged;0.6 table prefix136 bytes|
|16|136|frame_acquire / swr_frame_acquire|`swr_status(const swr_frame_request *, swr_frame *)`|
|17|144|frame_copy / swr_frame_copy|`swr_status(swr_frame, swr_frame_info *, uint8_t *pixels, uint64_t cap_bytes)`|
|18|152|frame_nodes / swr_frame_nodes|`swr_status(swr_frame, swr_node_geometry *, uint32_t cap, uint32_t *count)`|
|19|160|frame_release / swr_frame_release|`swr_status(swr_frame)`|
|20|168|frame_records / swr_frame_records|`swr_status(swr_window, uint64_t after_seq, swr_frame_record *, uint32_t cap, uint32_t *count, uint64_t *oldest_seq)`|
|21|176|clock_sample / swr_clock_sample_query|`swr_status(swr_clock_sample *)`|

`clock_sample_query` avoids C typedef/function namespace collision with `swr_clock_sample`. No new fault-injection export, callback, pump, activate-window API or native HWND export.

## Exact layouts

C declarations live in standalone `abi-0.7-layout-mock.c`; use C fixed-width integers, `float` & natural alignment. No packing pragmas, `bool`, `size_t`, pointers inside new data structs or platform enums. x64 Windows/MSVC ABI & arm64 Apple ABI give identical sizes, alignments & offsets below. All reserved fields/unknown flags must be0; request/output structs have `struct_size@0`, `flags@4` unless noted. Output flags describe validity rather than accepted request bits.

| Struct | Size | Alignment | Fields (`type name@offset`) |
|---|---:|---:|---|
|swr_frame_request|32|8|`u32 struct_size@0, flags@4; u64 window@8, min_snapshot@16, frame_id@24`|
|swr_frame_info|144|8|`u32 struct_size@0, flags@4; u64 frame_id@8, snapshot@16, paint_seq@24, render_completed_ns@32, presented_ns@40, clock_id@48; u32 width_px@56, height_px@60, stride_bytes@64, pixel_format@68, color_space@72, alpha_mode@76, orientation@80, occlusion@84; u64 bytes_required@88, rects_drawn@96, text_runs_drawn@104, images_drawn@112, underlines_drawn@120; f32 scale@128; u32 provider@132, presented_valid@136, reserved@140`|
|swr_node_geometry|64|8|`u64 node@0, parent@8; swr_rect bounds@16, clip@32; u32 order@48, flags@52; f32 baseline@56; u32 reserved@60`|
|swr_frame_record|72|8|`u32 struct_size@0, flags@4; u64 seq@8, frame_id@16, snapshot@24, render_completed_ns@32, presented_ns@40, clock_id@48; u32 outcome@56, provider@60, occlusion@64, reserved@68`|
|swr_clock_sample|64|8|`u32 struct_size@0, flags@4; u64 clock_id@8, raw_ticks@16, frequency_hz@24, monotonic_ns@32, sample_begin_ns@40, sample_end_ns@48, uncertainty_ns@56`|
|swr_rect (existing)|16|4|`f32 x@0, y@4, w@8, h@12`|

Geometry output entries use fixed64-byte stride, with no embedded struct_size; frame_nodes belongs to exact0.7 table. For later growth use new version/table contract. `frame_info` & clock output callers initialize struct_size to exact declared size; renderer verifies before reading/writing. Record output always72-byte stride.

Frozen0.6 sizes read from identical headers: bootstrap88/4, api136/8, callbacks112/8, transaction72/8, node144/8, primitive80/8, semantic88/8, AX text run80/8, event136/8, measure request88/8, measure result56/8, line24/4, cell24/4, stats200/8, modal request80/8. Those structs remain unchanged except bootstrap/API appended tails.

## Frames, buffers & errors

`frame_acquire`: validate size32, flags0, live window & shutdown state. `frame_id=0` selects latest completed provider frame in current render generation whose snapshot >= min_snapshot. Render generation changes on resize, DPI/surface recreation or device loss; it is separate from window-handle generation. Minimized window, lost surface, absence of valid completed current-generation surface or latest completed frame unavailable because archive budget is exhausted -> `SWR_EMPTY`, out handle0. Latest requests never substitute an older archived frame when newer completed paint lacks capture storage. Static non-minimized window may retain/reuse its latest current-generation completed frame when minimum matches; reuse proves no new rendering or presentation. Pending/newer unpainted commit never retags that retained frame. Never satisfy latest requests using commit acceptance, input transaction arrays, old-generation surface or synthetic repaint. Explicit nonzero frame_id is historical lookup: it may pin one of newest2 retained completed surfaces, including pre-resize/minimized history, if snapshot minimum matches; missing/expired id -> `SWR_E_NOT_FOUND`. Historical metadata remains unchanged & cannot certify current window state or fresh presentation. Already acquired handles remain valid across minimize/resize until release/window teardown; immutable info retains captured dimensions/state. Success pins rendered surface, geometry, counters & timings, starts asynchronous GPU readback & returns retained generation handle. Pixel completion can arrive later. Acquiring must not block UI waiting for GPU/presentation or cause host callbacks.

Bound retention: at most4 frame handles/window, newest2 successfully preserved completed provider surfaces eligible for explicit historical acquisition,256 timing records/window; reserve total unique archive/readback storage within64MiB/frame &256MiB/window. Share immutable backing storage for handles of same frame; budget counts GPU archive, staging & CPU pixel storage, with duplicate buffers counted separately. Evict unpinned old archives first. If retained pins leave insufficient budget to preserve newest completed frame, continue normal rendering/presentation & timing records; latest acquisition returns `SWR_EMPTY` until a newest completed frame is successfully preserved. Existing pinned frames remain available by handle, eligible archived history by explicit id; neither substitutes for unavailable latest frame. Budget pressure drops capture availability only, never actual paint/presentation. Acquisitions requiring excess handle/storage capacity return `SWR_E_QUEUE_FULL`; no synchronous release wait or forced repaint. Maximum dimension8192, but checked total byte bound can impose smaller combined dimensions. Exhausted live handle/storage slots -> `SWR_E_QUEUE_FULL`; dimensions/arithmetic overflow/storage limit -> `SWR_E_TOO_LARGE`; allocation/device failure -> `SWR_E_PLATFORM`. Disabled/lost readback capability -> `SWR_E_UNSUPPORTED`, never fake pixels.

`frame_copy`: valid handle +144-byte initialized info. While asynchronous copy pending return `SWR_E_BUSY`, never spin/pump. On completion, NULL pixels + cap0 queries metadata only (`SWR_OK`). Otherwise cap must cover bytes_required; short -> `SWR_E_TOO_LARGE`, full metadata written, pixel buffer untouched. NULL with nonzero cap -> `SWR_E_BAD_ARG`. Successful copy fills exactly bytes_required, retains neither pointer nor output struct. Multiple copies are identical; caller owns output buffers & PNG/hash encoding. Acquisition pins geometry immediately; frame_nodes can complete before pixels.

`frame_nodes`: exports node snapshot used for this exact painted frame, sorted by order then node id within tree preorder; includes nodes without semantics/paint. Count query NULL/cap0 -> `SWR_OK`, count total. Short cap -> `SWR_E_TOO_LARGE`, count total, no partial writes. Limit4096 nodes. Node identity/parent match committed renderer tree; host sidecar maps node ids to viewIdentity/probeTag. bounds are applied physical client coordinates; clip is physical client viewport/common actual clip applying to every primitive of that node. Current renderer resets clip stack per node & permits different sequential primitive masks; node bounds/ancestor masks do not imply inherited clipping. Under current behavior, common clip is client viewport. Export never claims one scalar rectangle represents disjoint or changing primitive masks. Precise per-primitive mask geometry stays HELD pending separately scoped evidence/API design. If every primitive truly shares an additional mask in future implementation, clip may reflect that common mask only, without changing existing renderer paint behavior. Flags: `BASELINE_VALID=1`, `CLIP_EMPTY=2`; invalid baseline=0. Baseline is first text-run baseline in client physical y; multiple distinct text baselines require existing text-run export/host mapping rather than pretending one scalar covers them. Export applied geometry, never SwiftUI proposals/alignment guides or UIA bounds relabelled as layout. Native provider layout obligations remain held unless separately observed at appropriate source.

`frame_release`: release retained handle once; stale/double release -> `SWR_E_STALE_HANDLE`. Window close invalidates handles, cancels pending readbacks & releases GPU/CPU storage. Frame ids/record sequences increase within window generation & never reuse; handle low32 slot/high32 generation follows existing convention. No renderer-owned raw pointer escapes.

All five frame exports are UI-thread only, outside IME/native borrows. Wrong thread -> `SWR_E_WRONG_THREAD`; inside restricted IME callback/borrow -> `SWR_E_BUSY`; before loop ready -> `SWR_E_NOT_READY`; new acquire after shutdown -> `SWR_E_SHUTDOWN`. Release during window_closed is allowed while handles remain live; after teardown it is stale. Copy/nodes/records after close return `SWR_E_STALE_HANDLE`. `clock_sample_query` is thread-safe, allocation/callback-free, available before run & after close. All boundary panics are contained as `SWR_E_PANIC`. Validate arguments before touching user memory; errors write only documented size/count/metadata outputs. No new export reenters host callbacks.

## Pixels, draw receipts & provenance

One canonical pixel contract: `pixel_format=1` RGBA8 byte order R,G,B,A; `color_space=1` sRGB transfer/primaries; `alpha_mode=1` premultiplied alpha; `orientation=1` top-left, rows downward. Convert provider BGRA/swizzled/bottom-up storage explicitly. `stride_bytes=width_px*4`, rows tight, `bytes_required=(uint64_t)stride_bytes*height_px`; no padding or uninitialized bytes. Values with alpha0 have RGB0. Opaque swapchain alpha becomes255; no claim to recover transparency absent from rendered surface. Never equate this output alpha contract with existing straight-alpha image_register input.

Capture client content only, excluding decorations, cursor, other windows & desktop. width/height/scale describe rendered frame, pinned across later resize/DPI changes. scale=dpi/96. HDR/wide-gamut requires explicit canonical sRGB conversion receipt; if unavailable return unsupported instead of tagging HDR bytes sRGB. Disclose conversion in adapter sidecar & test with opaque/alpha/color controls.

`provider=1` means actual renderer GPU target readback; other values reserved. Occlusion:0 unknown,1 observed unoccluded,2 observed partially occluded,3 observed fully occluded,4 minimized. Record observed window state at render completion; GPU readback may work behind windows without proving desktop visibility. Occlusion inference is not certification. Readback never activates/shows/moves windows; latest acquisition while minimized/lost/current-generation surface absent yields EMPTY. Static non-minimized latest-frame reuse & explicit historical lookup follow frame_acquire rules; neither establishes fresh presentation. Provider pixels can prove paint under occlusion only with independent observed occlusion receipt & non-stale changing frames.

`rects_drawn/text_runs_drawn/images_drawn/underlines_drawn` count actual submitted primitive draw operations on this frame, after validation/culling; clips/transforms are excluded. Counts0 for omitted/no-op operations. Counters prove draw path execution, not visual correctness; independently assert output pixels. `paint_seq` identifies provider render completion. `frame_id` matches timing records. Host sidecar binds executable/renderer/header/source/font hashes, tuple, case, run, window-generation, snapshot, frame_id, capture method, pixel hash, conditions & conversion metadata. ABI does not hash DLLs or mint factory verdicts.

Factory schema mapping: canonical pixels -> images hash/dimensions/captureScale; frame geometry -> layout frame with host-owned identity mapping; frame_records -> anim.presentedFrames only for real valid presentation records plus matched image hashes. Empty channels remain empty. Additional raw receipt details stay in hashed sidecars/meta.conditions, preserving schema0.1 without inventing unsupported fields. Readback images without observed presentation stay paint evidence & do not enter presentedFrames.

## Private custom-font obligation — HELD

`factory/resources/fonts/windows/README.md` proves headless private DirectWrite collection loading of hashed Tinos bytes, family/PostScript resolution & metrics; it explicitly has no glyph-raster capture or SwiftUI Font.custom integration. Renderer `src/lib.rs` passes borrowed font_family into text request; `src/text.rs` resolves `font(r.family.to_string())`. ABI0.6 exposes no resource registration, collection/font handle, resolved face/resource identity or private-font selector. External isolated DirectWrite collection cannot bind renderer/GPUI shaping merely by sending `"Tinos"` or `"Tinos-Regular"`; proposed readback/counters likewise cannot prove selected font bytes. Existing factory host uses Segoe UI explicitly.

This bounded0.7 frame proposal grants **no Font.custom/private-font qualification**. Before that obligation can close, post-SR0 work must establish private renderer-process registration into actual GPUI/DirectWrite text system, exact resource selection without system fallback, cache key including resource identity, resolved per-run/per-face identity bound to vendored SHA256/face index & actual glyph raster evidence. Wrong/missing font bytes, duplicate system family, fallback glyphs & resource release while text runs reference it need negative controls. SwiftRightUI Font.custom API support is separate prerequisite.

No font exports are appended here: current evidence establishes missing integration, not which registration/selection boundary GPUI can support. Keep `text.custom-font-resource` & `text.resolved-font-identity` held proposal items. Post-closure investigation must choose provider-internal immutable bundled-resource registration with truthful identity receipts, or explicit retained font-resource registration/release plus font-selected measurement & identity export. If latter is required, write supplemental append-only ABI design with byte ownership, resource/face identity, per-run fallback identities, handle/cache lifetime & compiled sizes before adding entries; do not claim present six exports cover it.

## Timing & correlation

`frame_records` returns immutable completed attempts with seq>after_seq, oldest_seq always reporting ring floor; count reports available records. NULL/cap0 queries. Short cap -> TOO_LARGE/count total/no partial writes. Cursor0 starts oldest retained record; nonzero cursor older than oldest_seq-1 -> NOT_FOUND with count/oldest_seq, no records. Consumer records explicit gap; it cannot silently claim complete history. Records survive frame_release; cease at window teardown.

Outcomes:1 confirmed presented,2 submitted without presentation feedback,3 dropped before presentation. `flags PRESENTED_VALID=1` only when provider/platform observes presentation completion for this frame; `flags DROPPED=2` only observed discard. Coalesced tick, render completion, Present() return, nominal refresh deadline or screenshot timestamp do not establish presentation completion. Unavailable feedback yields outcome2, presented_ns0 & flag0. DROPPED may have frame_id but never invented presentation timestamp. A repeated display of same frame creates presentation record only with corresponding platform feedback; snapshot alone is insufficient. No frame sampling changes animation scheduling.

`render_completed_ns` records GPU completion, not CPU command submission; lack of GPU completion observation must leave value0 with `flags RENDER_COMPLETED_VALID=4` unset. Readback becomes ready only for completed GPU work. `presented_ns` is observed display/presentation completion normalized to renderer monotonic clock; never wall clock. Provider may support readback while presentation qualification stays held.

`clock_id` is nonzero process-lifetime correlation identity, changes each process; paired with executable/process receipt to prevent cross-process collision assumptions. Windows uses QPC raw ticks/frequency; monotonic_ns=floor(raw_ticks*1e9/frequency_hz), checked128-bit intermediate. Query brackets sampled raw_ticks, reports begin/end converted ns & uncertainty_ns=end-begin, with begin<=monotonic<=end. Clock values never use wall time. Adapter brackets call with its own monotonic clock, writes raw values, conversion, offset/drift/uncertainty calculation & correlation hash consumed by meta.clock. Correlation must cover stimulus/transaction/sample/presentation window; fresh samples before/after run establish drift bound. Clock ABI exports evidence; no fabricated zero-error cross-clock mapping.

## Fault controls & qualification after closure

Use factory consumers/test builds, not production injection functions. Reject ABI/minor/size/count/arch/pointer mismatch before function calls; forged sizes/reserved flags; null/short buffers with canaries; multiplication overflow; stale/double-released/reused-slot handles; wrong thread; IME borrow; resize/DPI/close during pending copy; exhausted retention/ring; device loss; withheld presentation feedback; ring overflow; malformed clock correlation. No GUI or renderer work is authorized by this proposal itself.

Qualification must bind new0.7 tuple, header bytes, bridge/compiler/renderer hashes & raw receipts. Require matching Rust repr(C), C/MSVC & Swift importer sizes/offsets on Windows x64, unchanged0.6 prefix & exact-version refusal in both directions. Arm64 mock proof is layout evidence only.

Require independent opaque/alpha/color/orientation/stride/crop controls, per-primitive rect/text/image/underline pixel controls, glyph/font identity, draw counters, changing-frame non-staleness, resize/DPI geometry correlation & instrumented-vs-uninstrumented output/timing transparency. Count assertions never replace pixels. Provider geometry must match independently observed committed display geometry; proposal/alignment/baseline channels lacking source remain held.

Require20 independent launches for each foreground-visible, background-unoccluded, partial/full-occluded state on Windows x64, each with independent foreground/occlusion observations, expected changing pixels, no activation/focus theft & paired provider/PrintWindow/screen receipts where meaningful. Minimized behavior tested as EMPTY/unsupported, not relabelled capture PASS. Reuse Smoke09 visible controls before qualifying additional states. Background screen crops cannot certify hidden client pixels.

Timing qualification needs independently witnessed presentation feedback, monotonic ordering, snapshot/frame/image correlation, dropped/gap records, measured clock uncertainty/drift & documented bounds chosen by factory timing obligation before runs. Poll/export overhead & asynchronous copy must satisfy existing workload bounds with exports off/on; failures keep presentation/animation held. Fault checks must prove no output overrun, callback reentry, leaks or stale geometry/pixels; pending copies release on close, gauges return to baseline.

## Standalone proof receipt

`abi-0.7-layout-mock.c` SHA256 `8fec30c4d52c47ee372f29870ac9f5fffd67eac080497a6481f95109c8831ccf`.

Internal-disk scratch `/private/tmp/swr-abi07.rsUh3v` (`/System/Volumes/Data`, `/dev/disk3s5`), Apple clang21.0.0 `(clang-2100.3.34.2)`. Copied standalone source only; no renderer build or execution. Native arm64 executable exited0: `PASS: all proposal size/alignment/offset assertions; pointers=64-bit`, `request=32/8 info=144/8 geometry=64/8 record=72/8 clock=64/8 api=184/8 bootstrap=108/4`. Both cross-target assertion compilations exited0: `x86_64-pc-windows-msvc` emitted Intel amd64 COFF; `arm64-apple-macosx` emitted Mach-O arm64. Windows object was compiled, not executed. Baseline header copy native compile confirmed existing sizes listed above; header mirror cmp exited0.

Reproduce from internal scratch copy:

```sh
clang -std=c11 -Wall -Wextra -Werror layout.c -o layout-arm64
./layout-arm64
clang -std=c11 -Wall -Wextra -Werror -ffreestanding -DSWR_LAYOUT_FREESTANDING -target x86_64-pc-windows-msvc -c layout.c -o layout-win-x64.obj
clang -std=c11 -Wall -Wextra -Werror -ffreestanding -DSWR_LAYOUT_FREESTANDING -target arm64-apple-macosx -c layout.c -o layout-mac-arm64.o
```

Proposal completes bounded ABI design & standalone layout proof; implementation remains governed by explicit SR0 closure gate.
