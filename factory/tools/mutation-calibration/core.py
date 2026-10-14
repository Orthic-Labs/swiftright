"""Shared plumbing: stage a fixture into a scratch case dir, run the pipeline's own compare-only path on it, read the verdict.

The verdict is the exit status of `python3 factory/tools/pair.py <case> --recompare <run>`: the same entry point, gate dispatch (semantic_gate,
semantic_decides) and per-gate report generators the pipeline uses (factory/pipeline/consolidation/run_all.py records that exit status as the case verdict)."""
import json, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PAIR = ROOT / "factory/tools/pair.py"
FIX = ROOT / "factory/pipeline/mutation-calibration/fixtures"


class Ctx:
    """One staged copy of a fixture. Mutators edit files under .run (and .pair for the case config) and return a short description."""
    def __init__(self, bid, tmp):
        self.bid = bid
        src = json.loads((FIX / bid / "SOURCE.json").read_text())
        self.case = Path(tmp) / src["caseName"]
        self.run = self.case / "runs" / "fixture"
        self.run.parent.mkdir(parents=True)
        shutil.copytree(FIX / bid / "run", self.run)
        shutil.copy2(FIX / bid / "pair.json", self.case / "pair.json")
        self.cfg = json.loads((self.case / "pair.json").read_text())

    def save_cfg(self):
        (self.case / "pair.json").write_text(json.dumps(self.cfg, indent=1))

    def p(self, rel):
        return self.run / rel


def recompare(ctx, timeout=300):
    r = subprocess.run([sys.executable, str(PAIR), str(ctx.case), "--recompare", str(ctx.run)], capture_output=True, text=True, timeout=timeout)
    out = (r.stdout + r.stderr).strip().splitlines()
    out = [l for l in out if "Deprecat" not in l]
    return r.returncode, out


REPORTS = {"pixel": "report.json", "text": "text-report.json", "text-colour": "text-colour-report.json", "button": "button-report.json", "control": "control-report.json",
           "list": "list-report.json", "semantic": "semantic-report.json", "clock": "clock-report.json", "image": "image-report.json", "text-origin": "textorigin-report.json", "ime": "ime-report.json"}


def failed_reports(ctx):
    """which gate reports in the run dir say FAIL after the recompare (a gate that crashed before writing its report is listed as 'crash:<gate>')"""
    out = []
    for gate, name in REPORTS.items():
        p = ctx.run / name
        if not p.is_file():
            continue
        try:
            j = json.loads(p.read_text())
        except Exception:
            out.append(gate); continue
        bad = (j.get("fail", 0) > 0) if gate in ("pixel", "clock", "text-origin", "ime") else (j.get("fail", 0) > 0) if gate == "semantic" else (j.get("gatePassed", 0) < j.get("pairs", 0))
        if bad:
            out.append(gate)
    return out


def deciding(ctx):
    """the gates whose failure fails the case: pair.py's own rule (semantic_decides: pixels never decide a control/button/image/clock/report-only case)"""
    sys.path.insert(0, str(PAIR.parent))
    import pair
    return pair.semantic_decides(ctx.case) if (ctx.case / "pair.json").is_file() and ctx.cfg else False


def run_one(bid, mutate=None):
    """Stage `bid`, apply mutate(ctx) -> description, run the gate. Returns dict(rc, passed, desc, tail)."""
    with tempfile.TemporaryDirectory(prefix="mutcal-") as tmp:
        ctx = Ctx(bid, tmp)
        desc = mutate(ctx) if mutate else "unmutated"
        rc, out = recompare(ctx)
        reasons = [l.strip()[:240] for l in out if any(k in l for k in ("FAIL", "fail=", "mismatch", "Traceback", "Error", "error", "run 01", "run 1", "gate=", "textorigin run", "semantic run", "clock run")) ]
        tail = (reasons or out)[-6:]
        failed = failed_reports(ctx)
        crashed = any("Traceback" in l for l in out)
        return dict(rc=rc, passed=(rc == 0), desc=desc, tail=tail, failedReports=failed, pixelDecides=not deciding(ctx), crashed=crashed)


if __name__ == "__main__":
    bad = 0
    for d in sorted(FIX.iterdir()):
        if not d.is_dir():
            continue
        res = run_one(d.name)
        print(f"{d.name:22s} rc={res['rc']} {'ok' if res['passed'] else 'BASELINE FAILS'}")
        if not res["passed"]:
            bad += 1; print("   ", *res["tail"], sep="\n    ")
    sys.exit(1 if bad else 0)


class M:
    """One mutation. kind: 'catch' (the gate must FAIL the mutated run), 'near' (a near-miss inside the tolerance: the gate must PASS),
    'probe' (sensitivity sweep, reported only). design: when a documented decision says the property is deliberately not gated, its citation
    (a miss is then reported as a documented exclusion, not as a defect)."""
    def __init__(self, gate, base, name, kind, fn, what, design=None):
        assert kind in ("catch", "near", "probe")
        self.gate, self.base, self.name, self.kind, self.fn, self.what, self.design = gate, base, name, kind, fn, what, design
