# Rounded stroke matched-scale Mac source

Source-only successor for paired full viewport capture. Witness.swift is copied byte-for-byte from rounded-stroke-host-v1 (hash pinned in matched-scale-plan.json); CaptureHost.swift only supplies centered 320x240-point opaque white host under light scheme. Root may compile staged source in `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/rounded-stroke-matched-scale-v1`, then capture `--scale 2.5 --png <fresh path>`. Expected offscreen PNG is 800x600. No AX or screen permission request is made.
