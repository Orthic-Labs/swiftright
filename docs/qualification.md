# SR0-A local qualification runner

Status: runner built and Mac-side verified. SR0-A is **not closed**: `docs/architecture.md` §12 makes SR0-A depend on stage P, which is still blocked (`docs/sr0-status.md`), and the Windows matrix has not been run for this runner. Nothing here commits, pushes, or branches.

## Scope of this change

| Path | What |
|---|---|
| `qualification/run.py` | stdlib-only runner, run as `python3 -I qualification/run.py <command>` |
| `qualification/test_run.py` | 22 unit tests: `python3 -I -m unittest discover -s qualification -p 'test_*.py'` |
| `conformance/accepted/F1/`, `conformance/accepted/F2/` | accepted baselines (normalized traces, manifests, provenance, PROMOTIONS log); F1 also has the schema-v0 comparator trace and its adaptations |
| `qualification/out/` (ignored) | per-run `events.jsonl`, fixture stdout, comparator reports |
| `qualification/.build/` (ignored) | SwiftPM scratch and exported committed source trees |

No file under `probes/` is written. Builds use committed source only (see below).

## Commands

```
python3 -I qualification/run.py run --stages mac-oracle --fixtures F1 F2 --runs 3
python3 -I qualification/run.py run --stages compare
python3 -I qualification/run.py run --stages smoke
python3 -I qualification/run.py run --stages compare smoke win-replay --dry-run   # plans only
python3 -I qualification/run.py run --stages win-replay --confirm-windows-gui     # desktop job; not run here
python3 -I qualification/run.py seed --fixture F1 --approved-by <name> [--v0-trace ... --adapt ...]
python3 -I qualification/run.py promote --fixture F1 --candidate conformance/candidates/F1/<ts> --approved-by <name>
```

Exit code 0 when no `fail` event was emitted, 1 otherwise, 2 for usage errors.

### Stages

- **mac-oracle**: exports the committed `probes/sr0-o/fixtures` tree (`git archive HEAD`), builds `FixtureApp` into `qualification/.build/`, runs `--fixture <F> --events <jsonl> --self-test` N times (self-test flag last), relaunches only when `root-appear` is absent (same rule as `run-self-test.sh`), normalizes each trace (drops `mono_ns`, sorts keys), and checks the canonical digest against `conformance/accepted/<F>/`. All N runs must PASS and agree. A differing trace is written to `conformance/candidates/<F>/<ts>/` with `diff.txt` and `candidate.json` (`status: candidate-not-promoted`). It is never written to `accepted/`.
- **compare**: builds the comparator from committed `probes/sr0-o/comparator` and runs `sr0o-trace compare` on the Mac accepted v0 trace against the committed Windows trace (`probes/sr0-o/f1-cross/out/win-trace-strict-w6.json`), with `adapt-v0.json`.
- **smoke**: BridgeSmoke is a Windows executable that needs an interactive desktop. It is recorded as `skip` on macOS.
- **win-replay**: plans `probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh` through `win`. Dry run prints the plan to stderr. A real run is refused unless `--confirm-windows-gui` is given. The desktop is busy, so this was not run.

### Event schema

One JSON object per line on stdout and in `qualification/out/<run>/events.jsonl`:

`{"ts": "...Z", "stage": "mac-oracle|compare|smoke|win-replay|seed|promote", "event": "start|pass|fail|skip", "fixture": "F1"|null, "artifact_ids": {name: "sha256:<64 hex>"}, "reason": string|null}`

`artifact_ids` holds `fixture_binary`, `trace_raw`, `trace_canonical`, `accepted_canonical`, `comparator_binary`, and similar keys. `fail` and `skip` always carry a reason. `validate_event` enforces this.

### Accepted-baseline rules

- The canonical digest decides a match. It is order-insensitive within each driver step, as in `normalize-hash.py --canonical`. The raw digest is recorded too.
- `seed` creates a baseline only when every run in the source set is PASS and has one canonical digest. It refuses to overwrite an existing baseline.
- `promote` needs `--approved-by <name>` (argparse-required, and validated as a name). It verifies the candidate's digest, archives the previous baseline under `history/`, and appends to `PROMOTIONS.jsonl` with the approver.
- Accepted files are checked against their manifest digests on every load. A mismatch is a fail.

## Provenance of the accepted baselines

- F1 and F2 were seeded from the 20-run Mac repeatability sweep (`probes/sr0-o/fixtures/out/repeat20/`, 20/20 PASS each, one distinct raw and canonical trace each, see `probes/sr0-o/fixtures/REPEAT20.md`).
- That sweep ran on the source at commit `4ff202f`. Its `probes/sr0-o/fixtures` tree equals HEAD (`bb4258a2549f`). Each manifest records `source_tree`.
- The F1 comparator trace (`trace-v0.json`) is the committed `probes/sr0-o/f1-cross/out/mac-trace-strict-m1.json`, with `adapt-v0.json` from `f1-cross/adapt.json`.
- Caveat: the 20-run JSONL logs are in gitignored `out/` directories on this Mac. The committed copies are the baselines under `conformance/accepted/`. The approver recorded for the seed is Adrian, who requested this baseline set. Under AD7 this is a maintainer decision, not an agent one.
- Cross-check: before seeding, three fresh committed-source runs produced canonical digests `482f9d887ac2…` (F1) and `8e1dcf01f2a9…` (F2), identical to the seeded baselines.

## Result: real Mac oracle run, F1 and F2, 3 runs each

Command: `python3 -I qualification/run.py run --stages mac-oracle --fixtures F1 F2 --runs 3`. Exit code 0. Host: macOS arm64, Xcode 27 RC toolchain, committed tree `bb4258a2549f`. The `10 uncommitted change(s)` in the build event are edits in the shared working tree under `probes/sr0-o/fixtures`. They were not built, and the oracle tests the committed tree.

```jsonl
{"artifact_ids": {}, "event": "start", "fixture": null, "reason": "build FixtureApp from committed source", "stage": "mac-oracle", "ts": "2026-10-09T06:05:33.716Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4"}, "event": "pass", "fixture": null, "reason": "built FixtureApp from committed tree bb4258a2549f; 10 uncommitted change(s) under probes/sr0-o/fixtures NOT built", "stage": "mac-oracle", "ts": "2026-10-09T06:05:35.920Z"}
{"artifact_ids": {}, "event": "start", "fixture": "F1", "reason": "3 runs of FixtureApp --fixture F1 --self-test", "stage": "mac-oracle", "ts": "2026-10-09T06:05:35.920Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:482f9d887ac25ee3303e3c7cf804b637be459e892efbcf57335f21337daafc29", "trace_raw": "sha256:88fbd120b8a43db153c2788cacb873f1a6a59c2275fa4425fa7af8d57e66fee5"}, "event": "pass", "fixture": "F1", "reason": "run 1/3: self-test PASS (7/7); trace events=27; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:37.605Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:482f9d887ac25ee3303e3c7cf804b637be459e892efbcf57335f21337daafc29", "trace_raw": "sha256:88fbd120b8a43db153c2788cacb873f1a6a59c2275fa4425fa7af8d57e66fee5"}, "event": "pass", "fixture": "F1", "reason": "run 2/3: self-test PASS (7/7); trace events=27; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:39.160Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:482f9d887ac25ee3303e3c7cf804b637be459e892efbcf57335f21337daafc29", "trace_raw": "sha256:88fbd120b8a43db153c2788cacb873f1a6a59c2275fa4425fa7af8d57e66fee5"}, "event": "pass", "fixture": "F1", "reason": "run 3/3: self-test PASS (7/7); trace events=27; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:41.459Z"}
{"artifact_ids": {"accepted_canonical": "sha256:482f9d887ac25ee3303e3c7cf804b637be459e892efbcf57335f21337daafc29", "fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:482f9d887ac25ee3303e3c7cf804b637be459e892efbcf57335f21337daafc29"}, "event": "pass", "fixture": "F1", "reason": "3/3 runs PASS; canonical trace equals accepted baseline (raw 88fbd120b8a4..., canonical 482f9d887ac2...)", "stage": "mac-oracle", "ts": "2026-10-09T06:05:41.463Z"}
{"artifact_ids": {}, "event": "start", "fixture": "F2", "reason": "3 runs of FixtureApp --fixture F2 --self-test", "stage": "mac-oracle", "ts": "2026-10-09T06:05:41.463Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:8e1dcf01f2a933f85eeb8dd8a0baff51c724dab113777a3d31f49d536a8130b5", "trace_raw": "sha256:3d70dd034fd3aff19504536999247528d948b17b0e9adede943bbde2db476d63"}, "event": "pass", "fixture": "F2", "reason": "run 1/3: self-test PASS (6/6); trace events=18; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:42.947Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:8e1dcf01f2a933f85eeb8dd8a0baff51c724dab113777a3d31f49d536a8130b5", "trace_raw": "sha256:3d70dd034fd3aff19504536999247528d948b17b0e9adede943bbde2db476d63"}, "event": "pass", "fixture": "F2", "reason": "run 2/3: self-test PASS (6/6); trace events=18; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:44.296Z"}
{"artifact_ids": {"fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:8e1dcf01f2a933f85eeb8dd8a0baff51c724dab113777a3d31f49d536a8130b5", "trace_raw": "sha256:3d70dd034fd3aff19504536999247528d948b17b0e9adede943bbde2db476d63"}, "event": "pass", "fixture": "F2", "reason": "run 3/3: self-test PASS (6/6); trace events=18; attempts=1", "stage": "mac-oracle", "ts": "2026-10-09T06:05:45.707Z"}
{"artifact_ids": {"accepted_canonical": "sha256:8e1dcf01f2a933f85eeb8dd8a0baff51c724dab113777a3d31f49d536a8130b5", "fixture_binary": "sha256:6c972b766718ed0fa2d2e84d047c7f17600321db2231ded0a4ada2825c2d83a4", "trace_canonical": "sha256:8e1dcf01f2a933f85eeb8dd8a0baff51c724dab113777a3d31f49d536a8130b5"}, "event": "pass", "fixture": "F2", "reason": "3/3 runs PASS; canonical trace equals accepted baseline (raw 3d70dd034fd3..., canonical 8e1dcf01f2a9...)", "stage": "mac-oracle", "ts": "2026-10-09T06:05:45.707Z"}
```

Other results, same session:

| Stage | Result |
|---|---|
| `compare` (F1, Mac accepted v0 vs Windows w6, committed) | pass, 0 diffs |
| `smoke` | skip (Windows-only) |
| `win-replay --dry-run` | skip, plan printed (2 configs x 3 runs) |
| `python3 -I -m unittest discover -s qualification` | 22 tests OK |

## Not yet covered

- F3 to F9 have no accepted baseline. Running them reports "no accepted baseline", writes candidates, and fails. That is intended.
- The Windows matrix was not run. Stage P is blocked, and SR0-A depends on it.
- The candidate lane has only been exercised by unit tests and by the pre-seed run, which wrote and then superseded candidates. It has not seen a real drift.
- `promote` changes accepted files only through `--approved-by`. No candidate has been promoted.
