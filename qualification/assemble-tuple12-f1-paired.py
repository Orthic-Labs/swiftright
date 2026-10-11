#!/usr/bin/env python3
"""Strict source-bound Mac/Windows F1 pair report; no native execution.

Both sides must already be independently qualified at exactly 20 runs. This
joins source/artifact/semantic identities, while timing remains observational.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path
from typing import Any

SHA256 = re.compile(r"^[0-9a-f]{64}$", re.I)
CASE = re.compile(r"^F1-r([1-9][0-9]*)-([0-9a-f]{32})$")
SOURCE = "0e201571e4320a3b6ccce14313fd2ad67e523904"
PRODUCT = "4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2"
STIMULUS = "ac6832b3a268f392d423728b043021859956e4206c416955875408be433a0a23"
STEPS = "20369cc4bf6854d4208e4e56f6c652665196102eafc3ed8a5c3bf03ea252c764"
FIXTURE = "0c9f380119c780e049c398e993c23dc74a150a43a3c049f0d5aa4154b5b0a904"
RECORDER = "39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4"
ASSEMBLER = "ffa92f848386e8d143b42ad7305ca18f8d62f2722b70cce25f10be43d37a96aa"
EXE = "87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374"
RENDERER = "7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2"
DRIVER = "34d28b1f4cc6a4fccb279639ae767c069a40ae081290ef2b11aebafd52b441b4"
WORKER = "8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6"
COORDINATOR = "4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4"
STEP_IDS = ["initial", "focus_row5", "type_abc", "engine_insert_above", "type_d"]

def local(path: Path, label: str) -> Path:
    p = path.expanduser()
    if not p.is_absolute(): raise ValueError(f"{label} must be absolute")
    cur = Path(p.anchor)
    for part in p.parts[1:]:
        cur /= part
        if cur.is_symlink(): raise ValueError(f"{label} symlink/reparse rejected: {cur}")
    return p

def obj(path: Path) -> dict[str, Any]:
    x = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(x, dict): raise ValueError(f"object required: {path}")
    return x

def require(condition: bool, message: str) -> None:
    if not condition: raise ValueError(message)

def runs20(report: dict[str, Any], side: str) -> None:
    require(report.get("status") == "qualified", f"{side} report not qualified")
    require(report.get("fixture") == "F1", f"{side} fixture mismatch")
    for key in ("requiredRuns", "observedRuns", "passedRuns"):
        require(report.get(key) == 20, f"{side} {key} != 20")
    require(report.get("failures") == [], f"{side} failures present")
    rows = report.get("runs")
    require(isinstance(rows, list) and len(rows) == 20, f"{side} run rows != 20")
    require([r.get("case") for r in rows] == [f"n{i}" for i in range(1, 21)] if side == "mac" else [r.get("run") for r in rows] == list(range(1, 21)), f"{side} run identity mismatch")
    for row in rows:
        require(all(isinstance(row.get(k), str) and SHA256.fullmatch(row[k]) for k in ("rawSha256", "traceSha256")) if side == "mac" else all(isinstance(row.get(k), str) and SHA256.fullmatch(row[k]) for k in ("receiptSha256", "traceSha256")), f"{side} run hash missing")

def check_mac(report: dict[str, Any]) -> None:
    runs20(report, "mac")
    candidate = report.get("candidate", {})
    require(candidate.get("sourceCommit") == PRODUCT, "mac product source mismatch")
    joins = report.get("joins", {})
    require(joins.get("capture", {}).get("sourceCommit") == SOURCE, "mac fixture source mismatch")
    require(joins.get("fixture", {}).get("sha256") == FIXTURE, "mac FixtureApp mismatch")
    require(joins.get("capture", {}).get("inputs", {}).get("F1MacRecord", [None])[0] == RECORDER, "mac recorder mismatch")
    require(joins.get("capture", {}).get("inputs", {}).get("F1Assemble", [None])[0] == ASSEMBLER, "mac assembler mismatch")
    plans = report.get("macPlans", {})
    require(plans.get("stepsSha256") == STEPS and plans.get("stimulusSha256") == STIMULUS, "mac plan mismatch")

def check_windows(report: dict[str, Any]) -> None:
    runs20(report, "windows")
    require(report.get("source", {}).get("commit") == SOURCE, "windows source mismatch")
    require(report.get("source", {}).get("manifestSha256") == "f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca", "windows manifest mismatch")
    artifacts = report.get("artifacts", {})
    require(artifacts == {"driver": DRIVER, "exe": EXE, "renderer": RENDERER}, "windows artifact pins mismatch")
    paths = report.get("source", {}).get("paths", {})
    require(str(paths.get("driver", {}).get("path", "")).lower().endswith("drive-fixture-noactivate-focus-r4.ps1"), "windows r4 driver path missing")
    require(str(paths.get("worker", {}).get("path", "")).lower().endswith("worker-v3.ps1"), "windows worker-v3 path missing")
    require(str(paths.get("coordinator", {}).get("path", "")).lower().endswith("coordinator-v3.ps1"), "windows coordinator-v3 path missing")

def check_mac_root(root: Path) -> dict[str, Any]:
    paths = sorted(p for p in root.glob("mac-trace-n*.json") if re.fullmatch(r"mac-trace-n[1-9][0-9]*\.json", p.name))
    require(len(paths) == 20, f"mac trace count {len(paths)} != 20")
    by_run = {}
    for p in paths:
        m = re.fullmatch(r"mac-trace-n([1-9][0-9]*)\.json", p.name)
        require(m is not None, f"unexpected Mac trace {p.name}")
        n = int(m.group(1)); require(n not in by_run and 1 <= n <= 20, "Mac run identity")
        x = obj(p)
        require(x.get("fixtureId") == "F1" and x.get("sourceHash") == f"sha256:{STIMULUS}", f"Mac trace source/fixture {p.name}")
        require([s.get("id") for s in x.get("steps", [])] == STEP_IDS, f"Mac steps {p.name}")
        obs = x.get("observations", [])
        require(len(obs) == 5 and [o.get("stepId") for o in obs] == STEP_IDS, f"Mac observations {p.name}")
        final = obs[-1]
        require(final.get("focusedNodeId") == "row/F0000001-0000-4000-8000-000000000005/field", f"Mac focus {p.name}")
        model = final.get("model", {})
        require(model.get("row/F0000001-0000-4000-8000-000000000005") == "Row 5abcd", f"Mac row5 {p.name}")
        require(model.get("row/F0000001-0000-4000-8000-000000000099") == "Engine 0", f"Mac row99 {p.name}")
        by_run[n] = {"path": str(p), "traceSha256": digest(p)}
    require(sorted(by_run) == list(range(1, 21)), "Mac runs incomplete")
    return by_run

def check_windows_root(root: Path) -> dict[str, Any]:
    rows = {}
    for case in sorted(root.iterdir()):
        if not case.is_dir() or case.is_symlink(): continue
        m = CASE.fullmatch(case.name)
        if not m: continue
        n = int(m.group(1)); require(n not in rows, "Windows duplicate run")
        traces = list(case.rglob("driver-trace.txt")); require(len(traces) == 1, f"Windows trace count {case.name}")
        text = traces[0].read_text(encoding="utf-8")
        for marker in ("SELFTEST F1: PASS (17/17", "ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS", "driver_abort=none", "run_summary keymode=char delivery=targeted fg_changes=0"):
            require(marker.lower() in text.lower(), f"Windows semantic marker {marker} {case.name}")
        rows[n] = {"path": str(traces[0]), "traceSha256": digest(traces[0])}
    require(sorted(rows) == list(range(1, 21)), "Windows runs incomplete")
    return rows

def digest(path: Path) -> str:
    h = hashlib.sha256();
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mac-report", type=Path, required=True)
    ap.add_argument("--windows-report", type=Path, required=True)
    ap.add_argument("--mac-root", type=Path, required=True)
    ap.add_argument("--windows-root", type=Path, required=True)
    ap.add_argument("--out", type=Path)
    ns = ap.parse_args()
    try:
        mrp, wrp, mr, wr = local(ns.mac_report, "mac report"), local(ns.windows_report, "windows report"), local(ns.mac_root, "mac root"), local(ns.windows_root, "windows root")
        m, w = obj(mrp), obj(wrp); check_mac(m); check_windows(w)
        require(mrp != wrp, "reports must differ"); require(mr.is_dir() and wr.is_dir(), "pair roots missing")
        mac_runs, win_runs = check_mac_root(mr), check_windows_root(wr)
        pair = [{"run": i, "mac": mac_runs[i], "windows": win_runs[i]} for i in range(1, 21)]
        report = {"kind": "sr0-tuple12-f1-paired-report-v1", "status": "qualified", "fixture": "F1", "runs": 20, "source": {"macFixtureSource": SOURCE, "windowsSource": SOURCE, "macProductSource": PRODUCT, "stimulusSha256": STIMULUS, "stepsSha256": STEPS}, "artifacts": {"macFixture": FIXTURE, "macRecorder": RECORDER, "macAssembler": ASSEMBLER, "windowsExe": EXE, "windowsRenderer": RENDERER, "windowsDriver": DRIVER, "windowsWorker": WORKER, "windowsCoordinator": COORDINATOR}, "pairs": pair, "timing": {"status": "observational-only", "compared": False, "ignored": ["Mac mono_ns/timestamps", "Windows UTC/start/end timestamps", "host scheduling latency"], "reason": "cross-platform timing is retained separately; semantic admission does not normalize or compare timestamps"}}
        encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if ns.out:
            out = local(ns.out, "output")
            if out.exists(): raise ValueError(f"output exists: {out}")
            out.parent.mkdir(parents=True, exist_ok=True)
            with out.open("x", encoding="utf-8", newline="") as f: f.write(encoded)
        print(encoded, end="")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"PAIR_FAIL {exc}", file=sys.stderr); return 2

if __name__ == "__main__": raise SystemExit(main())
