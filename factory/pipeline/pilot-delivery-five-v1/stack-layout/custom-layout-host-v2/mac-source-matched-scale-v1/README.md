# Custom Layout v2 matched-scale Mac source packet

Fresh source-only Mac packet for exact v2 witness `sha256:f032a6b2a4b1f850fcce02ed97964eb05c2bc8965feb3403db975c8da44c7ee3`. v2 packet remains unchanged. Host composes `Witness_custom_layout` through `NSHostingView`, lays out fixed 320x240 points, centers 32x32 witness, supplies opaque white background & light scheme, then renders `ImageRenderer.cgImage` at scale 2.5 for expected 800x600 pixels. Observe also writes `client.png` in supplied scratch root for each reference run. No AX query, screen capture, or permission call occurs.

Internal Mac staging root: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-matched-scale-v1`. Root must invoke existing aggregate supervisor `factory/tools/supervise-job-v2.py` with 1 GiB bound. Scripts only stage source & emit compile request; no compile/native action occurs during prep.

For 20 references, invoke same binary serially with distinct `scratch/reference-01` through `scratch/reference-20` roots; each observe writes `client.png` & `observation.json`.

Root invocation after source review:

```sh
cd /Volumes/D/claude/swiftright/factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/mac-source-matched-scale-v1/mac-source
./tools/prepare-mac-source.sh
# Root invokes emitted compile request through factory/tools/supervise-job-v2.py.
```

Joins: case `swiftui.custom-layout.recipe/case/b30ed0b185e8cb29` (`sha256:fb33f02b...d6dab1a39`), recipe `sha256:87d402e0...f3ba4cc1`, Windows plan `sha256:87e4874c...b938c43a`, witness `sha256:f032a6b2...d44c7ee3`, renderer `sha256:e280f4a9...f39ccc93`, runtime `37429120...f1a58a92ae3a7f4d2b12b`.

Color observation: Mac evidence is RGBA `[255,56,60,255]`; current Windows `FactoryFill.swift` maps `system.red` to `[255,59,48,255]` (`0xff3b30ff`). `prospective/factory-fill-red-v1.patch` proposes `0xff383cff` (`[255,56,60,255]`). Patch is advisory & is not applied to immutable v2 Windows source.

Required post-build joins are receipt/executable path, exact witness/source hash, runtime commit/tree, preflight & observe scratch receipts, fixed geometry, scale, image dimensions, opaque white background, light scheme, & both rootRSS samples. Qualification remains held.
