# R8 partial: qualification runner on the final tuple

10 October 2026, repo HEAD `c370228`, Mac mini macOS 27.0.1 arm64. Run output: `qualification/out/r8-partial-final.txt` (`qualification/out/` is gitignored: `git add -f` it). No Mac GUI program was launched and no Dell desktop job was started. Dell access was read-only `win` queries.

Final tuple (`docs/sr0-snapshot.md` 2c): renderer `7533963D…3F149FC`, FreshOnBridge `AA4353CE…E1D7E`, BridgeSmoke `21992F16…DF1A5`. The three hashes were re-read on the Dell (`D:\Claude\sr0s-bridge06f`, `D:\Claude\sr0b-abi06c`) and equal the tuple.

## Stage table

| Stage | Status | What ran | What a no-skip run still needs |
|---|---|---|---|
| unit tests | ran-PASS | `python3 -I -m unittest discover -s qualification -p 'test_*.py'`: 74/74 OK, before and after the three edits below | nothing |
| mac-oracle | **blocked** (offline half ran-PASS) | `load_accepted` on all 16 configs: 16/16 baselines intact (canonical v2). `FixtureApp` builds from the HEAD fixtures tree `1b4affaf44f8` (sha256 `5b71cb56…aada3b7`), not launched. Baselines were seeded from tree `bb4258a2549f`; SR1 edits to `FixtureSession.swift` and `SelfTest.swift` landed since, so whether F1-F9 traces are unchanged is only known after a launch | Mac free: 16 configs x 3 launches, about 5 to 8 min incl. build. F6 is unstable under canonical v2 (1 of 20 runs), so a 3-run F6 fails about 14% of the time until the F10 decision |
| win-replay | **blocked** (ingestion ran-PASS) | `win_stage` fed the 320 committed `matrix-final` records: 320/320 PASS, ids exe `aa4353ce…`, renderer `7533963d…`, trace `84c2f00b…`. Separate audit: 320/320 records carry the ARTIFACT header and ARTIFACTS line with the final hashes | Dell desktop: about 13 s per run, 48 runs (16 x 3) about 11 min; 16 x 20 about 71 min (`matrix-final` timestamps) |
| compare | ran-PASS, **not final-tuple** | real runner stage, 0 diffs. Inputs are historical: Mac `accepted/F1/trace-v0.json` = `mac-trace-strict-m1.json` (9 Oct, `eaf40dc`, before the R6 signed-recorder re-record) and Windows `win-trace-strict-w6.json` (0.5 stack, exact binary UNVERIFIED per snapshot section 4) | R6 F1 re-record on the Mac, replace `accepted/F1/trace-v0.json` (no runner command does this), and a fresh Windows F1 trace on the final FreshOnBridge (Dell desktop: `schedule-f1.ps1 -Mode record -Bin D:\Claude\sr0s-bridge06f\scratch\out\Products\Release-windows-x86_64`, then `F1Assemble win`) |
| smoke | **blocked** (ingestion ran-PASS) | `smoke_stage` fed `result-smoke-rev06final.txt` (40/40) and `result-smoke-timeout06final.txt` (41/41): PASS, exe `21992f16…`, renderer `7533963d…` | Dell desktop, about 1 min. The runner dispatches the normal mode only, not timeout mode |
| package | **ran-FAIL** | real stage on R5 final2: `receipts-offline-4` fails (W08 FAIL; `expected_checks` has 14 entries, runner requires 15), `receipts-network-2` fails (3 entries, W12 only); macOS: no run record exists; default dir `qualification/receipts/package/` does not exist | see D4 |

Not runner stages and not covered: R6 itself (`F1MacRecord.app` re-record F1-F9, 100-run F6 sample) and any Windows-to-Mac compare for F2-F9 (the compare stage is F1 only).

## Defects found

| # | Defect | State |
|---|---|---|
| D1 | `SMOKE_BASE` was `D:\Claude\sr0b-abi0`, which does not exist on the Dell (also the `schedule-smoke.ps1` default); a real smoke stage could not start | **fixed**: base `D:\Claude\sr0b-abi06c`, plan passes `-Base` |
| D2 | `BUILD_ROOT` and `OUT_ROOT` were fixed under `/Volumes/D`: fresh Mac binaries would build and run there (removable-volume prompts) | **fixed**: env `SR0A_BUILD_ROOT`, `SR0A_OUT_ROOT` (defaults unchanged) |
| D3 | `compare` after `win-replay` needs `win-matrix/win-trace-v0.json`; nothing writes it, so that order can never pass | open: compare must run as its own invocation with `--win-candidate` |
| D4 | `package` needs one run record with all 15 W checks (and 12 M checks). R5 now emits two profiles (offline 14, network 3), so no R5 record can pass even without W08. No macOS record exists: `mac-clean-run.sh` never ran (refuses uid 501, M11 manual), R3 final and R7 evidence is not in the v2 receipt form | open: merge profiles in the runner or emit one run; W08 is a separate FAIL |
| D5 | The runner records exe and renderer hashes but never checks them against the tuple: the old `rev06c` smoke receipt (renderer `777F14C4`) passes the smoke stage (negative control in the output file) | open |
| D6 | `docs/qualification.md` line 137 says `schedule-fixture.ps1` and `drive-smoke.ps1` do not emit the ARTIFACTS line; both do (`drive-fixture.ps1:377`, `drive-smoke.ps1:219`, 320/320 matrix-final records). `win-replay` defaults to F1, F2 x 3 only: pass `--configs` for the full set | doc stale, not edited |

## Edits to `qualification/run.py` (not committed)

`git diff`: `OUT_ROOT`/`BUILD_ROOT` read the two env vars, `SMOKE_BASE` set to `D:\Claude\sr0b-abi06c`, `-Base {SMOKE_BASE}` added to the smoke command. +6/-4 lines, 74/74 tests still pass.

## Full run once R6 and a Dell desktop window exist

D3 forces two invocations (`compare` cannot follow `win-replay`). Fill the paths once the evidence exists; both must exit 0.

```
cd /Volumes/D/claude/swiftright
export SR0A_BUILD_ROOT=/private/tmp/sr0a-build SR0A_OUT_ROOT=/private/tmp/sr0a-out

# A: Dell desktop free
python3 -I qualification/run.py run --stages win-replay --win-runs 3 --confirm-windows-gui \
  --configs F1:none F2:none F3:list-0s F3:list-1s F3:list-3s F3:vstack-1s F3:vstack-3s F3:lazy-1s F3:lazy-3s \
            F4:none F5:none F6:none F6:reduced F7:none F8:none F9:none

# B: Mac free, Dell desktop free (smoke), R6 trace and package records in place
python3 -I qualification/run.py run --stages mac-oracle compare smoke package --runs 3 --confirm-windows-gui \
  --win-candidate <fresh final-tuple win F1 schema-v0 trace.json> \
  --package-receipts <win run dir, W00-W14> <mac run dir, M00-M11>
```

Both were dry-run (plans only) in section 9 of the output file.
