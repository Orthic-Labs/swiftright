# Text Mac exit-proof replay v1

This packet replays retained `capture-host` bytes from `producer-bytes-v1`; it never compiles or rebuilds host sources. It validates producer-manifest rows, exact host/AX hashes, measured case `swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418`, tuple `sr1-text-paint-v2-r11-paired20-20261012`, fresh AX trust, internal scratch, fresh output, bounded 45s host / 15s AX waits, 1GiB RSS, 8MiB stream files, 256MiB total output, exact Popen waitpid, & sealed stdout/stderr hashes.

Before any preflight or host launch, exact measured producer bytes are streamed into fresh `<scratch>/bin/`, rehashed, & chmod 0700. All Popen argv use these internal execution paths; archived paths remain explicit provenance refs. Existing scratch/bin contents, symlink components, source drift, & copy collisions hold closed.

Producer archive rows store measured SHA values as bare 64-hex strings; validator canonicalizes them to `sha256:` refs before comparing pinned values, while rejecting malformed hashes.

Root runs on Mac only after AX preflight is `axTrusted:true`. Each run records plain host, instrumented host, window host, & external AX child. Existing captures remain immutable; semantic qualification stays held. New output must use fresh internal scratch & archive paths.

```sh
python3 factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1/replay_exit_proof.py \
  --scratch /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/text-exit-proof-r1 \
  --output factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1/observed-mac20-exit-proof-r1
```

`replay-receipt.json` is observational only. Missing AX trust, child wait, RSS, stream seal, or exact retained-byte join is held before qualification.
