# Rounded stroke matched-scale Mac source

`Sources/FactoryProbe/Witness.swift` is byte-identical to rounded-stroke-host-v1 (`sha256:73235389c2f255b5ceea4184a356fbf0e582d91e00a6ad9887da8de68c2773c7`). `CaptureHost.swift` only supplies centered 320x240-point host geometry, opaque white background, light scheme, & scale metadata; witness remains unchanged.

Root may stage source into `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/rounded-stroke-matched-scale-v1`, compile under aggregate 1 GiB supervisor, then capture offscreen with `--scale 2.5 --png <fresh path>`. Expected image is 800x600. No AX or screen permission request is made; denied channels stay held.
