"""Replay five archived Mac receipts through live origin guard; never executes tools."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
BASE = ROOT / "factory/oracle/mac/seed-origin-actual-v1"
MODULE = ROOT / "factory/gate/mac_origin_admission.py"
spec = importlib.util.spec_from_file_location("mac_origin_live", MODULE)
guard = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(guard)


def ref(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    return {"path": str(path), "sha256": "sha256:" + hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}


manifest = json.loads((BASE / "archive-map.json").read_text())
by_hash = {item["sha256"]: BASE / item["path"] for item in manifest["files"]}
cache: dict[str, bytes] = {}
reads: list[dict[str, object]] = []


def reader(value: dict[str, object]) -> bytes:
    expected = value["sha256"]
    if expected in cache:
        return cache[expected]
    if expected in by_hash:
        path = by_hash[expected]
        mode = "pinned-archive-by-exact-byte-hash"
    else:
        path = Path(str(value["path"]))
        if str(path) not in {"/usr/bin/xcrun"} and not str(path).startswith("/Applications/Xcode-27-RC.app/"):
            raise ValueError(f"unarchived path denied: {path}")
        mode = "current-original-tool-by-recorded-exact-hash"
    raw = path.read_bytes()
    actual = "sha256:" + hashlib.sha256(raw).hexdigest()
    if actual != expected:
        raise ValueError(f"hash mismatch: {path}")
    cache[expected] = raw
    reads.append({"semanticPath": value["path"], "readPath": str(path), "sha256": expected, "mode": mode, "bytes": len(raw)})
    return raw


rows = []
for folder in sorted(BASE.glob("swiftui.*")):
    summary_path = folder / "summary.json"
    if not summary_path.exists():
        continue
    summary = json.loads(summary_path.read_text())
    case = BASE / "input-snapshot" / (folder.name + ".json")
    archive = BASE / "archive" / folder.name
    source = archive / "source/Witness.swift"
    adapter = archive / "source/CaptureHost.swift"
    binary = archive / "binary/capture-host"
    capture = {
        "platform": "macos",
        "case": summary["case"],
        "meta": {"conditions": {"macOrigin": {
            "version": "1", "summary": ref(summary_path), "case": ref(case),
            "source": ref(source), "adapter": ref(adapter), "binary": ref(binary),
            "compilerReceipt": ref(folder / "compiler-receipt.json"),
            "auxiliaryAX": {"receipt": ref(BASE / "ax-compiler-receipt.json"),
                            "source": ref(BASE / "archive/auxiliary/source/AXClient.swift"),
                            "binary": ref(BASE / "archive/auxiliary/binary/f5-ax-client")},
        }}}
    }
    issues = guard.mac_origin_admission_issues(capture, reader)
    rows.append({"case": folder.name, "issues": issues, "passed": not issues})

print(json.dumps({
    "kind": "mac-origin-compatibility-replay-v3",
    "synthetic": False,
    "nativeOrCompilerRuns": 0,
    "archiveMap": ref(BASE / "archive-map.json"),
    "readPolicy": "Exact archive hash mapping; recorded Xcode/xcrun tool bytes only when absent archive; no execution.",
    "rows": rows,
    "reads": reads,
}, indent=2, sort_keys=True))
