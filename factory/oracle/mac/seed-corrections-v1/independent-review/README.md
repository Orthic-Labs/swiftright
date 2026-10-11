# Seed corrections v1 independent Mac review

Offline review covers seed `14577611000270672472`, five exact cases, & twenty runs per case. It verifies input source/case/recipe lineage, producer stage hashes, fresh AX no-prompt preflight, signed recorder identity, arm64 internal-device records, four distinct owned processes per run, raw process ownership, AX witness counts, pixel hashes, candidate-only tags, held custom external AX, held scroll offscreen paint, & six mutation controls.

`review.json` records PASS for 5 cases x 20 runs x 400 distinct process IDs. `sourceJoin` keeps five witness source hashes separate from 100 capture `provenance.sourceHash` values, each of which equals its `instrumented.raw.json` bytes. Summary adapter & compiled-adapter hashes exist, but packet stages no adapted CaptureHost source, embedded witness bytes, or compile argv/source manifest keyed by those hashes; join remains `HELD_MISSING_GENERATED_HOST_SOURCE_ARCHIVE` without aliasing.

Run offline with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-corrections-v1/independent-review/review.py
```
