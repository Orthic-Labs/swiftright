# Stack overlay Mac typography diagnostic

This diagnostic keeps original `Witness_stack_overlay` byte exact (`sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee`) & preserves plain 320x240pt centered white/light capture. `--observe` renders unchanged witness into `client.png`, then renders separate bare `Text("+")` through public macOS 15 `SwiftUI.TextRenderer` API. Probe output records each line/run `typographicBounds` origin, width, ascent, descent, leading, & rect; provider family/point-size metadata is unavailable through this API. Probe pixels are discarded, so main PNG paint stays unchanged.

Root commands after supervised build:

```sh
StackOverlayV6MacHost --preflight --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-centered-v6-mac/scratch/preflight
StackOverlayV6MacHost --observe --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-centered-v6-mac/scratch/observe
```

No permissions, screen capture, accessibility queries, or witness font substitutions are used.
