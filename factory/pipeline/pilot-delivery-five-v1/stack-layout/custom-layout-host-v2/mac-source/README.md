# Custom Layout Mac source packet

Source-only companion for current witness `7b87f5dbfb5d248ba035747e81b8376bdc559ab57ddfa3caaaf31f23437d6b25`. `Witness.swift` preserves same one-child spacing/layout algorithm while aliases map Apple `CGSize`/`CGRect`/`CGPoint` to current runtime `LayoutSize`/`LayoutRect`/`LayoutPoint` names used by Windows source.

`CaptureHost.swift` exposes only `--preflight` & `--observe`. Both modes request no permissions. Observe uses fixed 320x240 points, offscreen `NSHostingView` & `ImageRenderer`, internal cache scratch, plus before/after `rootRSS` samples from `task_info`; no screen/window capture is enabled.

Root build packet (source only; no EXE/hash claim). Prep stages source into `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/source`; scratch/build/bin stay inside same cache root. `build-mac-source.sh` emits `compile-request.json`; root must execute request through `factory/tools/supervise-job-v2.py`, which owns process-group RSS/quiescence.

```sh
factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v1/mac-source/tools/prepare-mac-source.sh
factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v1/mac-source/tools/build-mac-source.sh
```

Root must bind produced receipt & binary after build, then run:

```sh
/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/bin/CustomLayoutMacHost --preflight --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/scratch/count1
/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/bin/CustomLayoutMacHost --observe --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/scratch/count1
```
