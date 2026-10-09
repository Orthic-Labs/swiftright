# SR0-A local qualification runner

Status: runner built and Mac-side verified; hardened 2026-10-09 by SR0 close plan v2 lane R8 (see the end of this page). SR0-A is **not closed**: `docs/architecture.md` §12 makes SR0-A depend on stage P, which is still blocked (`docs/sr0-status.md`), and the Windows matrix has not been run for this runner. Nothing here commits, pushes, or branches.

## Scope of this change

| Path | What |
|---|---|
| `qualification/run.py` | stdlib-only runner, run as `python3 -I qualification/run.py <command>` |
| `qualification/test_run.py` | 74 unit tests: `python3 -I -m unittest discover -s qualification -p 'test_*.py'` |
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
- Caveat: the 20-run JSONL logs are in gitignored `out/` directories on this Mac. The committed copies are the baselines under `conformance/accepted/`. The seed was approved by the SwiftRight primary session under Adrian's standing autonomy grant (9 Oct 2026), on the 20-run evidence in `probes/sr0-o/fixtures/REPEAT20.md`; Adrian did not review these traces individually. Under AD7 any later promotion still needs a named approver.
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

## 2026-10-09 note: F3-F9 accepted-baseline seeding blocked

Status: **not seeded**. No file under `conformance/accepted/` was written for F3-F9. No Mac oracle verification ran for these configs. Nothing committed, pushed, or branched.

- Source evidence: `probes/sr0-o/fixtures/REPEAT20.md`. All 16 configs read 20/20 PASS and canonical distinct = 1, so none is excluded for disagreement.
- Blocker 1, approver: `run.py` `check_approver` (`APPROVER_RE`) rejects the required approver string (apostrophe, parentheses, semicolon, slash, length over 64). `seed --fixture F4` failed before any write: `qualification/out/20261009T060749.203Z-seed/events.jsonl`. F2's manifest already holds that string, so an earlier runner accepted it.
- Blocker 2, configs: `validate_fixture` accepts only `F1`..`F9`, and `run.py` never passes `--f3-variant` or `--reduced-motion-variant`. The F3 variants (`list-1s`, `list-3s`, `vstack-1s`, `vstack-3s`, `lazy-1s`, `lazy-3s`) and `F6-reduced` cannot be seeded or verified. Original F3 (no variant flag) is the `list-0s` config and is seedable as `F3`, from `F3-run*.jsonl`.
- Consulted `gpt-6-astra` (high effort): recommends stopping, since fixing blocker 1 requires editing `run.py`.
- Decision needed: approve a small `run.py` change for the approver charset and for variant plumbing (`--variant` mapped to `--f3-variant`/`--reduced-motion-variant`), then re-run seeding for F3, F4-F9, and the variants.
- Not touched: the G5 `FixtureApp` process (`probes/sr0-o/fixtures/.build/...`, `out/sr1-smoke/`) belongs to the SR1 lane.


Approver IDs: `swiftright-primary@autonomy-2026-10-09` means the SwiftRight primary session approved under Adrian's standing autonomy grant of 9 Oct 2026, on the 20-run evidence in `probes/sr0-o/fixtures/REPEAT20.md`; Adrian did not review the traces individually.

## 2026-10-09 update: F3 configs and F4-F9 seeded and verified (supersedes the blocked note above)

- Approver: `swiftright-primary@autonomy-2026-10-09` (validator-compatible short ID, per the coordinator decision in commit 8bb1d08).
- `qualification/run.py` now addresses 16 configs through an explicit allow-list (`CONFIGS`): `F1`-`F9`, `F3-{list-1s,list-3s,vstack-1s,vstack-3s,lazy-1s,lazy-3s}`, `F6-reduced`. Plain `F3` is the original `list-0s` config (the committed FixtureApp rejects `list-0s` as a variant). Variant flags go before `--self-test`, which stays last. Variant verdicts (`SELFTEST F3 variant=lazy-1s`) parse to the config id.
- Seeded from the 20-run evidence in `probes/sr0-o/fixtures/REPEAT20.md`: all 14 new configs were 20/20 PASS with one canonical trace each.
- Mac-oracle verification, committed tree `bb4258a2549f`, 3 runs per config: 14/14 PASS, 42/42 runs PASS, canonical digests equal the accepted baselines, no candidates written.
- Unit tests: `python3 -I -m unittest discover -s qualification -p 'test_*.py'`, 31 tests OK.
- Observation: canonical digests coincide across variants (`F3`, `list-1s`, `list-3s` share one; `vstack-1s`, `vstack-3s`, `lazy-1s`, `lazy-3s` share another). The canonical trace does not record the timing variant, so it cannot tell those variants apart.
- Not committed. The SR1 fixture working-tree edits were not touched. No FixtureApp process was left running.

## 2026-10-09 R8 hardening (close plan v2, findings F3 and F4)

### F4: canonical form v2 (`sr0-a.canonical/v2`)

The canonical digest groups events by driver step (steps keep their order), then by `node_id`. Node groups inside a step are sorted, so different nodes may permute, but each node's own event sequence keeps its recorded order (CONTRACT section 3). Reversing `onDisappear` and task-cancel on one node now changes the digest; swapping events of different nodes does not. Implemented identically in `qualification/run.py` (`canonical_body`) and `probes/sr0-o/fixtures/scripts/normalize-hash.py --canonical`. `load_accepted` refuses a manifest whose `canonical_form` is not v2. Tests: `CanonicalV2Tests`.

Offline recompute from the saved 20-run sweep (`probes/sr0-o/fixtures/out/repeat20`, 320 traces), all 16 configs:

- 15 configs: exactly one canonical v2 result in 20/20 runs. The accepted trace bytes are unchanged; only `canonical_sha256` in each manifest was recomputed. Each manifest records `canonical_form`, `previous_canonical_sha256_v1`, a `canonical_recomputed` block (ts, source, per-variant run lists) and `PROMOTIONS.jsonl` has a `recanonicalize` entry.
- **F6 is not stable under v2**: 2 canonical results (19 runs vs run 9). In step `burst-insert` the `animation` node completes tag B before tag A in run 9 (accepted order: A then B). The raw diff is in `conformance/candidates/F6/<ts>/diff.txt` (status `candidate-not-promoted`). `accepted/F6` keeps the majority trace and its manifest has `distinct_canonical_traces: 2` and a `canonical_variance` note. It was not re-seeded. Open decision: declare A/B completion order a permitted ordering (contract change) or treat it as a fixture/runtime defect. Until then F6 Mac oracle runs can fail about 1 in 20.
- `REPEAT20.md` still shows the v1 "canonical distinct" column; read it with this note.

### F3: runner strictness

- Every stage named in `run` is required. Outside `--dry-run`, any `skip`, any `fail`, or a stage with no `pass` exits 1. `--dry-run` prints plans, emits `skip` events and exits 0; it is not qualification evidence.
- `--stages` runs in the order given. Default order: `mac-oracle win-replay compare smoke package`. `compare` uses the Windows trace written by a preceding `win-replay` in the same run (`win-matrix/win-trace-v0.json`); a historical file needs explicit `--win-candidate` and `compare` declared before `win-replay` is a usage error (exit 2). There is no default historical trace.
- `mac-oracle` defaults to all 16 configs (`--fixtures` narrows it).
- Windows `pass` records (`win-replay`, `smoke`) must carry `windows_exe`, `windows_renderer`, `windows_trace` sha256 artifact ids (`validate_event` enforces it). The Windows scripts must print one line per run, `ARTIFACTS exe=<sha256> renderer=<sha256> trace=<sha256>`; the runner fails a PASS run that lacks it and fails when runs mix exe or renderer builds. Open item for the Windows lanes: `schedule-fixture.ps1` and `drive-smoke.ps1` do not emit that line yet.
- `smoke` dispatches BridgeSmoke through `win` and `schedule-smoke.ps1 -Tag <tag>` (dry run prints the plan; a real run needs `--confirm-windows-gui`). It passes only on `AUTOMATIONID PASS`, `run: ok` and the ARTIFACTS line.
- `package` reads harness run directories: `qualification/receipts/package/` by default, or `--package-receipts DIR ...`. A directory is a run when it holds `run.json`. A parent directory is scanned for run subdirectories. Each run directory holds `run.json` (record `run`, the authoritative summary) and one `<check_id>.json` per declared check (record `check`). Producers: `clean-machine/mac-clean-run.sh` writes into `~/clean-machine-receipts/<run id>/`. The Windows guest writes `W*.json` and `guest-run.json`, and `run-sandbox.ps1` verifies them against host hashes and writes `run.json`.
- Schema `sr0-a.package-receipt/v2` (v1 is retired). The one definition is `qualification/clean-machine/receipt.schema.json`. Platforms are `windows-x64` and `macos-arm64`. Declared checks are `W00`-`W11` and `M00`-`M11` (`PACKAGE_CHECKS` in `run.py`). A harness list that drifts from `PACKAGE_CHECKS` fails `HarnessDriftTests`.
- A check may be `pass` only when `implemented` is true. An unimplemented check is recorded as `fail` with reason `not-implemented: ...`.
- `package` passes a platform only when its `run.json` is `pass` and every declared check is implemented and `pass`, with the run summary agreeing with each check file. It fails when no run exists, a record is unreadable or invalid, a declared check file is missing, a record is undeclared, or a platform has no valid PASS run.
- Check record fields: `schema`, `record: "check"`, `product`, `platform`, `run_id`, `check_id`, `check_name`, `implemented`, `status` (`pass|fail`), `reason` (null on pass), `started_utc`, `ended_utc`, `exit_status`, `observations` (scalars), `artifact_ids` (`name: "sha256:<64 hex>"`), `environment` (`host`, `os_version`, `user`), `harness` (`name`, `sha256`).
- Run record fields: the same header, plus `status`, `expected_checks`, `checks` (`check_id`, `status`, `implemented`), `reason`, and `artifact_ids` (the sealed inputs, for example `old_msix` or `old_dmg`).

```json
{"schema": "sr0-a.package-receipt/v2", "record": "run", "product": "SliceApp", "platform": "macos-arm64",
 "run_id": "20261009T100000Z", "status": "fail", "expected_checks": ["M00-environment", "..."],
 "checks": [{"check_id": "M08-interrupted-install", "status": "fail", "implemented": false}],
 "started_utc": "2026-10-09T10:00:00Z", "ended_utc": "2026-10-09T10:05:00Z",
 "reason": "checks not passing: M08-interrupted-install", "artifact_ids": {"old_dmg": "sha256:<64 hex>"},
 "harness": {"name": "mac-clean-run.sh", "sha256": "sha256:<64 hex>"}}
```

Verification: `python3 test_run.py` from `qualification/`, 74 tests OK (62 before the v2 package receipt).
