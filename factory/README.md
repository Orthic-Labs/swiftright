# SR1 factory — implementation, capture & verification

[Current delivery status & evidence](../docs/sr1-status.md) is authoritative for13October; work paused by Adrian.
Original-five milestone remains incomplete; cumulative ramp is5→10→20 total.

Started 10 October 2026 under plan rev 3 (`56be363`). These are draft specifications, executable format checks &
capture-method experiments. SR0 remains OPEN; none of this promotes goldens, changes SR0 evidence, or grants parity.

[Verification & next work](VERIFICATION.md) records actual results, raw spike evidence & remaining gates.

## Working boundary

Factory work proceeds while SR0 closes. Runtime source at `probes/sr0-s/fresh-runtime` is released additively:
new API surface, unit tests &one commit per API, preserving original behavior. Renderer/bridge ABI remain held
until explicit closure in `../docs/sr0-status.md`; FreshOnBridge fixtures, `qualification/` &`probes/sr0-o/` retain
Swift Mac ownership. Candidate hosts bind own measured tuple11 renderer & actual additive runtime; tuple12 SR0 candidate remains separate.
Final frozen binding follows recorded SR0 closure. Existing-ABI candidate implementation does not wait for freeze.
[Current results](pipeline/ADDITIVE-CURRENT.md) & [running holds](HELD.md) record exact evidence.

Window-targeted input stays default. Dell windowed runs require `D:\Claude\desktop.lock`; ordinary windows stay
background. Native-only IME/Narrator tests use foreground checks & abort-on-focus-loss in the held lane. Second-session
feasibility is recorded in [Windows spike](spikes/windows/RESULT.md). Never delete Dell files over SSH.

## Contents

| Area | Purpose | Evidence boundary |
|---|---|---|
| [Specifications](spec/schema/SCHEMA-INDEX.md) | Versioned artifact schemas & host/acceptance/operation protocols | Draft structural contracts; native semantics remain to qualify |
| [Rectangle example](spec/examples/rectangle-v0.1/README.md) | Worked artifact flow | Synthetic example; blocked native verdict |
| `tools/` & `tests/` | Canonical JSON, SHA-256 & local schema validation | Format & fault-control evidence only |
| `spikes/timing/` | Separate semantic & bounded timing comparison | Synthetic unit evidence; no timestamp support assumed from SR0 comparator |
| [Mac capture](spikes/macos/README.md) | TextRenderer, Layout, VM capture & AX feasibility | Only observed channels count; absent permission remains blocked |
| [Host lanes](hosts/README.md) | Isolated Mac VM & shared Dell operating rules | No frozen-contract/ABI integration |

## Mac build caches (`factory/tools/cache_paths.py`)

Every Mac build path is chosen by `factory/tools/cache_paths.py`; do not hard-code `~/Library/Caches/SwiftRightFactory` in new tools.

| Root | Path | Holds |
| --- | --- | --- |
| Build | `/Volumes/D/swiftright-cache/<lane>/` | SwiftPM `--scratch-path`, swiftc module caches, intermediates. Compile and link here; never launch from here (TCC prompt). |
| Run | `~/Library/Caches/SwiftRightFactory/run/<lane>/` | Only the binaries or app bundles launched. 2 GB cap, LRU eviction. |
| Moved | `/Volumes/D/swiftright-cache-moved/<date>/` | Where the sweep and lane cleanup move things. Move, never delete. |

- Use `cache_paths.build_root(lane)`, `run_root(lane)`, `preflight()` and `finish_lane(lane, ok)` from Python, or `python3 factory/tools/cache_paths.py path build|run <lane>` / `preflight <lane>` / `finish <lane>` from shell.
- `pair.py`, `mac-stage-test.py`, `appkit-probe`, `image-io`, `symbol-metrics` and `font-metrics` already use it; `consolidation/run_all.py` and `recompare_all.py` print the free-space warning.
- `python3 factory/tools/cache_paths.py sweep --report` prints sizes and the plan; without `--report` it moves internal entries older than 24 h, anything over the cap and finished build lanes. Anything modified in the last 4 h is never moved.
- Internal free space: warning below 40 GB, a new Mac build is refused below 15 GB.
- `SWIFTRIGHT_CACHE_ROOT=<dir>` puts both roots under `<dir>/build` and `<dir>/run`.
- `swift test` launches its test bundle from the scratch path, so `mac-stage-test.py` keeps its scratch on the internal run root and moves it out when the run passes.

## Local validation

Private repository: use local tools; no billed GitHub Actions. Dependency installation is confined to ignored
`factory/.venv`; transitive versions are pinned in `requirements.lock`.

```sh
python3 -m venv factory/.venv
factory/.venv/bin/python -m pip install -r factory/requirements.lock
factory/.venv/bin/python -m unittest discover -s factory/tests -v
factory/.venv/bin/python factory/tools/schema_validate.py factory/spec/examples/rectangle-v0.1/*.json
```

## Outstanding gates

1. Complete host capture/channel calibration & native timing controls; VM capture follows later permission provisioning.
2. Review draft acceptance schemas, normalization rules & tolerances; synthetic controls cannot approve them.
3. Observe recorded SR0 closure, then bind actual frozen contract/ABI & replace illustrative hashes with measured native inputs.
4. Finish original Rounded/Image/Stack/font/Custom obligations; Rectangle fill already has exact paired20 evidence.
   Verify originalfive, fix gaps, then10 &20 total; reviewed promotion remains separate.
5. Add only foundations needed by each pilot round; open contributor queue only at plan's specified exit.
