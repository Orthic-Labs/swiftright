#!/usr/bin/env python3
"""Pure admission controls for tuple12 Mac F1 assembler; no native actions."""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/actual-mac20/F1"
PACKET = ROOT / "qualification/tuple12-mac-f1-packet.json"
SPEC = importlib.util.spec_from_file_location("macf1", ROOT / "qualification/assemble-tuple12-mac-f1.py")
MACF1 = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MACF1)


def copied() -> Path:
    out = Path(tempfile.mkdtemp(prefix=".tuple12-mac-f1-control-"))
    for p in ARCHIVE.iterdir():
        if p.is_file() and p.name.startswith(("mac-raw-", "mac-ev-", "mac-trace-", "mac-rec-")):
            shutil.copy2(p, out / p.name)
    return out


def mutate(out: Path, name: str, fn) -> dict:
    path = out / name
    data = json.loads(path.read_text(encoding="utf-8"))
    fn(data)
    path.write_text(json.dumps(data), encoding="utf-8")
    result = MACF1.collect(out, "ac6832b3a268f392d423728b043021859956e4206c416955875408be433a0a23")
    return {"status": result["status"], "failures": result["failures"]}


def main() -> int:
    if not ARCHIVE.is_dir():
        raise SystemExit("F1 actual archive unavailable")
    rows = []
    baseline = MACF1.collect(ARCHIVE, "ac6832b3a268f392d423728b043021859956e4206c416955875408be433a0a23")
    rows.append({"name": "positive-20-runs", "passed": baseline["status"] == "qualified"})
    cases = [
        ("trace-source-hash", "mac-trace-n1.json", lambda d: d.__setitem__("sourceHash", "sha256:" + "0" * 64)),
        ("raw-allOK", "mac-raw-n1.json", lambda d: d.__setitem__("allOK", False)),
        ("trace-fixture", "mac-trace-n1.json", lambda d: d.__setitem__("fixtureId", "F2")),
        ("trace-row-value", "mac-trace-n1.json", lambda d: d["observations"][2]["model"].__setitem__("row/F0000001-0000-4000-8000-000000000005", "wrong")),
    ]
    for name, file, fn in cases:
        out = copied()
        try:
            result = mutate(out, file, fn)
            rows.append({"name": name, "passed": result["status"] == "incomplete"})
        finally:
            shutil.rmtree(out)
    out = copied()
    try:
        (out / "mac-raw-n20.json").unlink()
        result = MACF1.collect(out, "ac6832b3a268f392d423728b043021859956e4206c416955875408be433a0a23")
        rows.append({"name": "missing-run", "passed": result["status"] == "incomplete"})
    finally:
        shutil.rmtree(out)
    status = "passed" if all(row["passed"] for row in rows) else "failed"
    print(json.dumps({"kind": "sr0-tuple12-mac-f1-controls-v1", "status": status,
                      "assemblerSha256": MACF1.digest(ROOT / "qualification/assemble-tuple12-mac-f1.py"),
                      "packetSha256": MACF1.digest(PACKET), "controls": rows}, indent=2))
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
