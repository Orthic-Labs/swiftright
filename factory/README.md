# SR1 factory — Phase 0 & independent spikes

Started 10 October 2026 under plan rev 3 (`56be363`). These are draft specifications, executable format checks &
capture-method experiments. SR0 remains OPEN; none of this promotes goldens, changes SR0 evidence, or grants parity.

[Verification & next work](VERIFICATION.md) records actual results, raw spike evidence & remaining gates.

## Working boundary

Factory work proceeds while SR0 closes. Runtime source at `probes/sr0-s/fresh-runtime` is released additively:
new API surface, unit tests &one commit per API, preserving original behavior. Renderer/bridge ABI remain held
until explicit closure in `../docs/sr0-status.md`; FreshOnBridge fixtures, `qualification/` &`probes/sr0-o/` retain
Swift Mac ownership. New closure bindings use tuple10, measured from `../docs/sr0-tuple10-staging.md`.
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
4. Run Rectangle through real hosts, qualify 20 independent runs per side, review candidate promotion & retain all raw evidence.
5. Add only foundations needed by each pilot round; open contributor queue only at plan's specified exit.
