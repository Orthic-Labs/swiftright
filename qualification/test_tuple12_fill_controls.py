#!/usr/bin/env python3
"""Production tuple12-fill controls; each fault must reject before candidate write."""
import hashlib, json, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILL = ROOT / "qualification" / "tuple12-fill.py"
BASE = ROOT / "qualification" / "tuple12-candidate.json"
STATUS = ROOT / "STATUS.md"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def invoke(candidate, *args):
    return subprocess.run([sys.executable, str(FILL), "--candidate", str(candidate), *map(str, args)], cwd=ROOT, text=True, capture_output=True)

def fixture(work, populated=False):
    candidate = work / "candidate.json"
    data = json.loads(BASE.read_text())
    if populated:
        data["members"]["windows_renderer"] = {"what": "test", "sha256": sha(STATUS), "source": ["stale-source"]}
    candidate.write_text(json.dumps(data))
    receipt = work / "receipt.json"
    receipt.write_text(json.dumps({"sealed": True, "receipt_type": "binary", "artifact_path": str(STATUS), "artifact_sha256": sha(STATUS)}))
    return candidate, receipt

def main():
    work = Path(tempfile.mkdtemp(prefix=".tuple12-fill-controls-", dir=ROOT / "qualification"))
    rows = []
    try:
        candidate, receipt = fixture(work)
        ok = invoke(candidate, "--source", f"windows_renderer={receipt}")
        rows.append({"name": "positive-sealed-source", "passed": ok.returncode == 0, "exit": ok.returncode})
        candidate, receipt = fixture(work)
        ok = invoke(candidate, "--member", f"windows_renderer={'0'*64}", "--source", f"windows_renderer={receipt}")
        rows.append({"name": "member-byte-mismatch", "passed": ok.returncode != 0, "exit": ok.returncode})
        candidate, receipt = fixture(work, populated=True)
        ok = invoke(candidate, "--source", f"windows_fixture_exe={receipt}")
        rows.append({"name": "prepopulated-member-revalidation", "passed": ok.returncode != 0, "exit": ok.returncode})
        candidate, receipt = fixture(work)
        outside = Path(tempfile.mkstemp(prefix="tuple12-outside-")[1]); outside.write_text(receipt.read_text())
        ok = invoke(candidate, "--source", f"windows_renderer={outside}")
        rows.append({"name": "outside-source-path", "passed": ok.returncode != 0, "exit": ok.returncode})
        outside.unlink()
        candidate, receipt = fixture(work)
        link = work / "receipt-link.json"; link.symlink_to(receipt)
        ok = invoke(candidate, "--source", f"windows_renderer={link}")
        rows.append({"name": "symlink-source-path", "passed": ok.returncode != 0, "exit": ok.returncode})
        candidate, receipt = fixture(work)
        link = work / "candidate-link.json"; link.symlink_to(candidate)
        ok = invoke(link, "--source", f"windows_renderer={receipt}")
        rows.append({"name": "symlink-candidate-path", "passed": ok.returncode != 0, "exit": ok.returncode})
    finally:
        shutil.rmtree(work)
    result = {"kind": "sr0-tuple12-fill-controls-v1", "status": "passed" if all(r["passed"] for r in rows) else "failed", "scriptSha256": sha(FILL), "controls": rows}
    (ROOT / "qualification" / "tuple12-fill-controls-results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "passed" else 1

if __name__ == "__main__": sys.exit(main())
