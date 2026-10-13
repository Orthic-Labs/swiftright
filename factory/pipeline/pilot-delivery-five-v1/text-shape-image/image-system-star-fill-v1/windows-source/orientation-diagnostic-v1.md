# star.fill orientation diagnostic

Status: diagnostic only. It does not alter witness, source bindings, provider map, acceptance, or qualification.

Inputs:

- Mac reference: factory/pipeline/pilot-delivery-five-v1/root-execution/image-star-full-viewport-v1/observed-mac20-r1/run-020/client.png, 800x600 RGBA, SHA256 4d4eb18319d2b9d1e88f9d1bc3827e2a7499422bc8f5e69801fac0eebc35c915.
- Provider map: windows-source/provider-bound-delivery-v2/package/FactorySystemImageAssets.json, mapping SHA256 f2faccf7547f249ab396fc6bfc991784c646594b613addf29185a49707c21268; RGBA payload is 34x30, 4080 bytes, SHA256 6a8be6929a9243dd5f5e4fb4c7cc6dd03feff282437109c20128733e63cd7594.
- Windows input: sealed native capture PNG from current Image v9 run after root archives it. Prebuild observation is compile-only and contains no PNG.

For each RGBA PNG, derive foreground rows inside its non-white bounding box: count pixels whose RGB differs from opaque white & whose alpha is nonzero. Preserve raw row counts, crop bounds, image SHA256, dimensions, source/executable hashes, and sealed capture receipt. Compare direct row order against vertically reversed order after resampling both profiles to common length. Record both errors; do not select or flip rows from expected pixels. A sign check is useful as an orientation signal only:

- Mac reference crop rows 1..75 has first-moment +3.488 around crop center.
- Provider payload in current top-down order has first-moment +1.5038167938931297; reversed order has negative sign.
- Mac profile begins [5,7,8,9,9,10,11,11,12,13] & ends [36,33,31,30,27,24,23,19,16,11].
- Provider profile begins [4,4,6,6,8,8,10,10,12,16] & ends [20,20,20,20,20,20,20,16,12,8].

This static profile is consistent with current top-down provider bytes, but native Windows PNG remains required. Current GlyphRasterProducer.cpp row reversal is an implementation assertion, not proof.

Source/API finding: runtime ImageReference exposes only .system(String) & .named(String); Graph.imageIntrinsicSize is host callback only. ABI 0.6 exposes Bridge.registerImage for RGBA handles. Renderer swr_image_register copies rows in increasing y & swaps R/B; it performs no vertical flip. Existing registry therefore can transport measured RGBA through existing ABI, but cannot prove or provide Apple SF Symbol provider. Exact same-source star.fill parity still needs protected provider/renderer support or external native provider evidence; Segoe Fluent Icons E735 remains explicit diagnostic substitute.
