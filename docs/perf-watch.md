# Perf watch (issue #65)

Four metrics are reported, not gated, by the SR0 bar (`docs/sr0-findings.md` section 11). `qualification/perf-watch.py` (stdlib only) reads the existing receipts, prints a table, writes `qualification/perf-watch.json`, appends `qualification/perf-trend.jsonl` (run id, date, four metrics; a repeat of the same run id and values is not re-appended) and exits non-zero only on FAIL. It is the last stage of `qualification/tuple13-run.sh` (skipped on `--dry-run`; the earlier stages and their exit code are unchanged, and a failed earlier stage keeps its code).

Run by hand: `python3 -I qualification/perf-watch.py [--workload FILE] [--coldopen FILE] [--native-dir DIR] [--f7-last N] [--run-id ID]`. Defaults: newest `r10-*-windows.txt` (diag/light/memdeep/nokeys variants excluded), newest `result-coldopen*.txt`, the last 8 `native-ime-f7-tuple*.txt`.

## Sources

| Metric | Produced by | Parsed line |
| --- | --- | --- |
| Missed vblanks per 60 s (worst timed run) | R10 analyzer (`probes/sr0-b/workload/scripts/`), PresentMon intervals > 1.5 x refresh; `qualification/run.py:1764,1830` | `THRESHOLD W5 rN INFO missed vblanks ...: N` (e.g. `r10-20261019-tuple13-renderer1aa8-windows.txt:40,79,118`) |
| R10 leak slope, MB/min (worst run, app only, trace buffers excluded) | same analyzer, threshold R, limit 5.0 | `THRESHOLD R rN ... leak flag: X` (`...tuple13...txt:37,76,115`) |
| M2 cold dialog p95, ms | `examples/BridgeGeoModal` ColdOpen06, M2win = request to first window-visible stamp | per-run rows `cold-dialog #NNaN ... m2win=` (`result-coldopen09.txt:36-55`); p95 computed here, the file reports only p90 and max |
| F7 flake rate | native IME receipts (`qualification/run.py:1763,1766`) | `NATIVE_SUMMARY ime-F7 pass= fail=`; flaky = any run with fail > 0 over the last N receipts |

## Thresholds and rationale

| Metric | Warn | Fail | Why |
| --- | --- | --- | --- |
| Missed vblanks / 60 s | > 3 | > 10 | Committed range is 0-6 (`docs/sr0-status.md:59-61,85`: tuple 08 5/1/1, 09 1/0/1, 10 1/1/1, 13 6/0/0); the zero-miss gate was dropped 2026-10-10 (`:63`). Warn above the usual 1-3 (`:57`), fail above 10, which is worse than any run on record (the paced build was 243-442, `:55`). |
| M2 cold dialog p95 | > 50 ms | > 80 ms | 50 ms is the cold-open criterion (`result-coldopen09.txt:12`: max 52.16, 1 of 20 above 50; 60.9 ms once on tuple 07, `docs/sr0-status.md:88`). 80 ms leaves headroom over the worst seen. |
| R10 leak slope | > 4.0 | > 5.0 MB/min | 5.0 is the R10 limit (`docs/sr0-status.md:5`; tuple 12 failed at 5.17). 4.0 is warned because tuple 10 reached 3.90 and 4.20 (`:61,86`). |
| F7 flake rate | > 0 | none | Any non-passing F7 run in the window is a flake or regression (tuple 10 17/20 then 20/20, `docs/sr0-status.md:83`). No fail limit was specified. |

## Run on the latest local data (2026-10-21)

Run id `tuple13-qualified-20261019`; overall WARN, exit 0.

| Metric | Value | Warn > | Fail > | Status | Source |
| --- | --- | --- | --- | --- | --- |
| Missed vblanks / 60 s | 6 (runs 6, 0, 0) | 3 | 10 | WARN | `r10-20261019-tuple13-renderer1aa8-windows.txt` |
| M2 cold dialog p95 | 49.97 ms (n=20, max 52.16) | 50 | 80 | OK | `result-coldopen09.txt` (tuple 09 era; no tuple 13 cold-open exists) |
| R10 leak slope | 2.97 MB/min (2.97 / 2.51 / 2.62) | 4.0 | 5.0 | OK | tuple 13 workload receipt |
| F7 flake rate | 0.25 (2 of 8: tuple10 17/20, tuple12 5/20) | 0 | - | WARN | `native-ime-f7-tuple08..13.txt` |

Notes: the F7 window includes the tuple 12 run (5/20), which belongs to the failed tuple; use `--f7-last 2` to look at tuple 12b and 13 only (0.0). The M2 figure is not from tuple 13 because ColdOpen has not been rerun on it.
