# Mac source packet: rounded stroke

`Sources/FactoryProbe/Witness.swift` is exact witness source: `RoundedRectangle(cornerRadius:6).stroke(Color.blue,lineWidth:2).frame(width:40,height:20)`. `CaptureHost.swift` derives from `factory/native/macos/CaptureHost.swift`, adds tagged observables, wraps witness in fixed 320x240 `ZStack(alignment: .topLeading)`, & keeps signed-recorder no-prompt checks.

Mac SwiftUI stroke is centered on path. Windows ABI exposes rect bounds, radius, border color, & border width; renderer edge semantics are unmeasured. No prospective bounds correction is applied until paired Mac/Windows pixels establish one.

Root must attach RSS supervision to compile process group with 1 GiB maximum before invoking scripts; scripts apply no local VM memory limit.

Root-only bounded commands:

```sh
sh tools/prepare-mac-source.sh /Volumes/D/claude/swiftright /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<fresh-stage>
sh tools/compile-mac-source.sh <stage> /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<app>.app
```

There is no asset provisioning step. All measured hashes, captures, permission state, & parity fields remain pending root receipts; denied AX/screen channels stay held without prompt.
