#!/usr/bin/env python3
"""Perf-watch report (issue #65): four reported-not-gated metrics against warn/fail thresholds.

Stdlib only. Reads existing qualification receipts; drives nothing. Exit 1 only when a metric is FAIL.
Sources (see docs/perf-watch.md):
  vblank  R10 analyzer receipt probes/sr0-b/workload/results/r10-*-windows.txt, "THRESHOLD W5 rN ... missed vblanks" lines
  R10     same file, "THRESHOLD R rN ... leak flag: <slope>" lines (app-only private-bytes slope, MB/min)
  M2      examples/BridgeGeoModal/result-coldopen*.txt, "cold-dialog #NNaN ... m2win=" per-run rows
  F7      probes/sr0-b/native-interaction/out/native-ime-f7-tuple*.txt, "NATIVE_SUMMARY ime-F7 pass= fail=" lines
"""
import argparse, datetime, json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
QUAL = REPO / "qualification"
WORKLOAD_DIR = REPO / "probes/sr0-b/workload/results"
COLDOPEN_DIR = REPO / "examples/BridgeGeoModal"
NATIVE_DIR = REPO / "probes/sr0-b/native-interaction/out"

# (warn, fail): value > warn is WARN, value > fail is FAIL. F7 has no fail limit.
THRESHOLDS = {
    "missed_vblanks_per_60s": (3, 10),
    "m2_cold_dialog_p95_ms": (50.0, 80.0),
    "r10_leak_slope_mb_min": (4.0, 5.0),
    "f7_flake_rate": (0.0, None),
}
VARIANT_RE = re.compile(r"diag|light|memdeep|nokeys")
MISSED_RE = re.compile(r"^THRESHOLD W5\s+(r\d+)\s+\S+\s+missed vblanks .*?: (\d+)")
LEAK_RE = re.compile(r"^THRESHOLD R\s+(r\d+)\s+\S+\s+private bytes growth slope.*?leak flag: ([0-9.]+)")
M2_RE = re.compile(r"^cold-dialog\s+#\S+\s.*?m2win=\s*([0-9.]+)")
F7_RE = re.compile(r"NATIVE_SUMMARY ime-F7 pass=(\d+) fail=(\d+)")


def natural(p):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p.name)]


def last_analysis(text):
    marker = "=== RE-ANALYSIS"
    return text[text.rindex(marker):] if marker in text else text


def percentile(values, q):
    v = sorted(values)
    k = (len(v) - 1) * q
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def latest(directory, pattern, exclude=None):
    files = [p for p in directory.glob(pattern) if p.is_file() and not (exclude and exclude.search(p.name))]
    return sorted(files, key=natural)[-1] if files else None


def read(p):
    return Path(p).read_text(encoding="utf-8", errors="replace")


def metric_workload(path):
    if not path:
        return None, None, None
    text = last_analysis(read(path))
    missed, leak = {}, {}
    for line in text.splitlines():
        line = line.strip()
        m = MISSED_RE.match(line)
        if m:
            missed[m.group(1)] = int(m.group(2))
        m = LEAK_RE.match(line)
        if m:
            leak[m.group(1)] = float(m.group(2))
    return (max(missed.values()) if missed else None, max(leak.values()) if leak else None,
            {"missed": missed, "leak": leak})


def metric_m2(path):
    if not path:
        return None, None
    vals = [float(m.group(1)) for m in (M2_RE.match(l.strip()) for l in read(path).splitlines()) if m]
    return (round(percentile(vals, 0.95), 2) if vals else None), {"n": len(vals), "max": max(vals) if vals else None}


def metric_f7(directory, last_n, files=None):
    paths = files or [p for p in directory.glob("native-ime-f7-tuple*.txt") if "final" not in p.name]
    paths = sorted(paths, key=natural)[-last_n:]
    runs = []
    for p in paths:
        s = F7_RE.findall(read(p))
        if s:
            ps, fl = (int(x) for x in s[-1])
            runs.append({"file": p.name, "pass": ps, "fail": fl})
    if not runs:
        return None, None
    flaky = sum(1 for r in runs if r["fail"] > 0)
    return round(flaky / len(runs), 4), {"runs": len(runs), "flaky": flaky, "files": runs}


def judge(name, value):
    if value is None:
        return "N/A"
    warn, fail = THRESHOLDS[name]
    if fail is not None and value > fail:
        return "FAIL"
    return "WARN" if value > warn else "OK"


def default_run_id():
    runs = sorted((QUAL / "out").glob("*-run")) if (QUAL / "out").is_dir() else []
    return runs[-1].name if runs else datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-perfwatch")


def rel(p):
    try:
        return str(Path(p).resolve().relative_to(REPO))
    except ValueError:
        return str(p)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workload", type=Path, help="R10 Windows analyzer receipt (default: newest r10-*-windows.txt, variant runs excluded)")
    ap.add_argument("--coldopen", type=Path, help="M2 cold-open result (default: newest result-coldopen*.txt)")
    ap.add_argument("--native-dir", type=Path, default=NATIVE_DIR)
    ap.add_argument("--f7-last", type=int, default=8, help="N most recent F7 receipts for the flake rate")
    ap.add_argument("--run-id", default=None)
    ap.add_argument("--json-out", type=Path, default=QUAL / "perf-watch.json")
    ap.add_argument("--trend", type=Path, default=QUAL / "perf-trend.jsonl")
    ap.add_argument("--no-trend", action="store_true")
    a = ap.parse_args(argv)

    wl = a.workload or latest(WORKLOAD_DIR, "r10-*-windows.txt", VARIANT_RE)
    co = a.coldopen or latest(COLDOPEN_DIR, "result-coldopen*.txt")
    missed, leak, wl_detail = metric_workload(wl)
    m2, m2_detail = metric_m2(co)
    f7, f7_detail = metric_f7(a.native_dir, a.f7_last)

    values = {"missed_vblanks_per_60s": missed, "m2_cold_dialog_p95_ms": m2,
              "r10_leak_slope_mb_min": leak, "f7_flake_rate": f7}
    sources = {"missed_vblanks_per_60s": wl, "r10_leak_slope_mb_min": wl, "m2_cold_dialog_p95_ms": co,
               "f7_flake_rate": a.native_dir}
    rows = []
    for name, v in values.items():
        warn, fail = THRESHOLDS[name]
        rows.append({"metric": name, "value": v, "warn_above": warn, "fail_above": fail,
                     "status": judge(name, v), "source": rel(sources[name]) if sources[name] else None})

    print(f"{'metric':<26}{'value':>10}{'warn>':>8}{'fail>':>8}  status  source")
    for r in rows:
        v = "n/a" if r["value"] is None else f"{r['value']:g}"
        f = "-" if r["fail_above"] is None else f"{r['fail_above']:g}"
        print(f"{r['metric']:<26}{v:>10}{r['warn_above']:>8g}{f:>8}  {r['status']:<6}  {r['source']}")

    run_id = a.run_id or default_run_id()
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    report = {"run_id": run_id, "date": date, "metrics": rows,
              "detail": {"workload": wl_detail, "m2": m2_detail, "f7": f7_detail},
              "overall": "FAIL" if any(r["status"] == "FAIL" for r in rows) else
                         "WARN" if any(r["status"] == "WARN" for r in rows) else "OK"}
    a.json_out.parent.mkdir(parents=True, exist_ok=True)
    a.json_out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not a.no_trend:
        entry = {"run_id": run_id, "date": date, **values}
        seen = False
        if a.trend.exists():
            for line in a.trend.read_text(encoding="utf-8").splitlines():
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("run_id") == run_id and all(o.get(k) == v for k, v in values.items()):
                    seen = True
        if not seen:
            with a.trend.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
    print(f"PERF_WATCH {report['overall']} run={run_id} json={rel(a.json_out)}")
    return 1 if report["overall"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
