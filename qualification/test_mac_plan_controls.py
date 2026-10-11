#!/usr/bin/env python3
"""Semantic Mac/Windows plan controls; no native or GUI actions."""
import hashlib, json, shutil, tempfile
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("plan", ROOT / "qualification" / "verify-mac-plan.py")
plan = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(plan)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def case(name, mutate):
    work = Path(tempfile.mkdtemp(prefix=".mac-plan-control-"))
    try:
        dst = work / "probes/sr0-o/f1-cross/cross/F2"; dst.mkdir(parents=True)
        src = ROOT / "probes/sr0-o/f1-cross/cross/F2"
        for n in ("stimulus.json", "steps-mac.json", "steps-win.json"):
            shutil.copy2(src / n, dst / n)
        mutate(dst)
        try: plan.verify(work, "F2")
        except ValueError: return {"name": name, "passed": True}
        return {"name": name, "passed": False}
    finally: shutil.rmtree(work)

def main():
    rows = [{"name": "positive-all-three-joins", "passed": bool(plan.verify(ROOT, "F2")["stepIds"])}]
    rows += [case("mac-step-id-mutation", lambda d: mutate_json(d / "steps-mac.json", lambda x: x["steps"].__setitem__(1, dict(x["steps"][1], id="wrong")))),
             case("win-logical-action-mutation", lambda d: mutate_json(d / "steps-win.json", lambda x: x["steps"].__setitem__(1, dict(x["steps"][1], logicalAction="wrong")))),
             case("mac-fixture-mutation", lambda d: mutate_json(d / "steps-mac.json", lambda x: x["launchArgs"].__setitem__(1, "F1")))]
    result = {"kind": "sr0-mac-plan-semantic-controls-v1", "status": "passed" if all(x["passed"] for x in rows) else "failed", "scriptSha256": sha(Path(__file__)), "controls": rows}
    (ROOT / "qualification/mac-plan-controls-results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2)); return 0 if result["status"] == "passed" else 1

def mutate_json(path, fn):
    data = json.loads(path.read_text()); fn(data); path.write_text(json.dumps(data))

if __name__ == "__main__":
    import sys
    sys.exit(main())
