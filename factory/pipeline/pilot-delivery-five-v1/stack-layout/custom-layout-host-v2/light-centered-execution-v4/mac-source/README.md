# Custom Layout Mac source packet

Source-only companion for current two-child witness `20bd1f475c71d9733e5c8376dfd70466199e10f49d57ff788e30fab3b90c85ff`. `Witness.swift` preserves same two-child spacing/layout algorithm while aliases map Apple `CGSize`/`CGRect`/`CGPoint` to current runtime `LayoutSize`/`LayoutRect`/`LayoutPoint` names used by Windows source.

`CaptureHost.swift` exposes only `--preflight`, `--observe`, `--scale`, & `--scratch-root`. Both modes request no permissions. Observe uses fixed 320x240 points, centered opaque white host, offscreen `NSHostingView` & `ImageRenderer`, default scale 2.5 (800x600 pixels), internal cache scratch, plus before/after `rootRSS` samples from `task_info`; no screen/window capture is enabled.

Root build packet (source only; no EXE/hash claim). Observe writes `client.png` beside `observation.json`. Prep stages source into `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/source`; scratch/build/bin stay inside same cache root. `build-mac-source.sh` emits `compile-request.json`; root must execute request through `factory/tools/supervise-job-v2.py`, which owns process-group RSS/quiescence.

```sh
factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/light-centered-execution-v4/mac-source/tools/prepare-mac-source.sh
factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/light-centered-execution-v4/mac-source/tools/build-mac-source.sh
```

Root must bind produced receipt & binary after build, then run:

```sh
/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/bin/CustomLayoutMacHost --preflight --scale 2.5 --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/scratch/count1
/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/bin/CustomLayoutMacHost --observe --scale 2.5 --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/scratch/count1
```
