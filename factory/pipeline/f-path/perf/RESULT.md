# F-path P2 frame-time probe (20 Oct 2026)

Ring raster (inset circle 60 pt, trim 0..0.62, 6 pt round caps, rotated, scale 2.5; `RingBench-main.swift`, 200 frames, release):

| Host | Before (commit 93897a903) | After byte-identical speed-up |
|---|---|---|
| Mac (arm64) | p50 1.247 ms, p95 2.505 | p50 0.281 ms, p95 0.666 |
| Dell (x86_64 Windows) | p50 3.875 ms, p95 5.508 | p50 0.962 ms, p95 1.273 |

The speed-up keeps output byte-identical (PathRasterizerByteIdentityTests: F-path cases at scales 1/2/2.5, a 12-angle spin, 60 random paths, 120 non-convex end-tangent cases). The ABI 0.12 trigger (> 2 ms per animated ring frame on the Dell) is not hit, so the path primitive stays deferred. Not measured: the bridge `registerImage` cost per frame, which comes on top of the raster.
