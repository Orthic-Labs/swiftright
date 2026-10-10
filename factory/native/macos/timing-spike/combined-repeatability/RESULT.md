Three independent packed-BGRA runs passed known mutation & bounded producer-stall controls using exact retained source/binary & reviewed launcher. GPU completion/physical scanout remain unavailable; scope is observational sample-event timing.

| Run | Samples / packed reads | Pixel variants | Stall ms | Mutation gap ms | Callbacks during stall | Strict clock brackets |
|---|---:|---:|---:|---:|---:|---:|
| 03 | 289 / 285 | 20 | 354.736875 | 355.138459 | 21 | 289/289 |
| 04 | 292 / 289 | 21 | 354.041500 | 355.063666 | 20 | 292/292 |
| 05 | 283 / 276 | 21 | 354.371250 | 354.963417 | 21 | 282/283 |

864 native samples supplied stream synchronization-clock conversion. Converted PTS versus SDK WindowServer event differed0..−1tick (0..−41.6667ns) in every run. Agreement concerns sample-event clocks. Duration/decode timestamps were invalid throughout.

Strict host-clock bracketing held863/864samples. Run05 sample48 converted CMHostSystemUnits was1tick below machBefore; exact raw values remain archived, with no tolerance applied. This records observed boundary miss instead of claiming universal bracket inclusion.

Exact source `625e13bfa8061a8fbdc73566212995e93cfba6b3688ee09089aea16599bdc256`; internal binary `7c356ea631bfee724c369c49908db93df9835b232a5976ef5fb7fbfd7c3f85f8`; launcher `faf429212a83c0ae20ee72b7631a0eac3f91000c4d882940dcfccd66895ea9c4`. Fresh no-prompt grants true; owned windows inactive/nonkey; watchdogs unchanged. Existing control01–03 & original receipt preserved. No nativecase/tuple/parity artifacts created.

[Exact hash manifest](/Volumes/D/claude/swiftright/factory/native/macos/timing-spike/combined-repeatability/manifest.json) binds all raw timestamps, analysis, reviews, stdout/stderr & retained source/binary paths. Independent known pixel mutation & continued callback delivery during measured producer stalls repeated3/3runs; owned processes0.
