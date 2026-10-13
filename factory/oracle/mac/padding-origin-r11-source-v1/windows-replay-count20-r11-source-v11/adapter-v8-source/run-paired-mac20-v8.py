#!/usr/bin/env python3
"""Pair fresh Mac20 & reader-verified Windows20 through production comparator."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
from factory.comparison.comparator import ComparisonError, compare_case

def bounded(path: Path, limit=64 * 1024 * 1024) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit: raise ValueError("bounded JSON required")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict): raise ValueError("JSON object required")
    return value

def digest(raw): return "sha256:" + hashlib.sha256(raw).hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--plan", required=True, type=Path); ap.add_argument("--mac-refs", required=True, type=Path); ap.add_argument("--mac-report", required=True, type=Path); ap.add_argument("--windows-captures", required=True, type=Path); ap.add_argument("--reader-report", required=True, type=Path); ap.add_argument("--case", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args(); plan = bounded(args.plan); expected = plan["tuple"]; refs = bounded(args.mac_refs); mac_report = bounded(args.mac_report); windows = bounded(args.windows_captures); reader = bounded(args.reader_report); case = bounded(args.case)
    if plan.get("count") != 20 or reader.get("status") != "reader-verified" or reader.get("count") != 20: raise ValueError("fresh reader/count20 admission required")
    rows = refs.get("macCaptures");
    if not isinstance(rows, list) or len(rows) != 20: raise ValueError("fresh Mac20 refs required")
    mac = []
    for ordinal, row in enumerate(rows, 1):
        path = Path(row["path"]); st = path.stat()
        if path.is_symlink() or not path.is_file(): raise ValueError("Mac ref must be regular file")
        raw = path.read_bytes()
        if digest(raw) != row.get("sha256") or len(raw) != row.get("bytes"): raise ValueError("Mac ref drift:" + str(ordinal))
        value = json.loads(raw.decode("utf-8-sig"));
        if value.get("meta", {}).get("run") != ordinal: raise ValueError("Mac run order mismatch")
        mac.append(value)
    win = windows.get("captures")
    if not isinstance(win, list) or len(win) != 20: raise ValueError("fresh Windows20 captures required")
    cr = re.compile(plan["captureIdentity"]["capturePattern"]); ir = re.compile(plan["captureIdentity"]["imagePattern"])
    for value in win:
        if not cr.fullmatch(str(value.get("id"))) or not ir.fullmatch(str((value.get("images") or [{}])[0].get("id"))): raise ValueError("Windows provenance ID mismatch")
        if value.get("case", {}).get("id") != expected["caseID"] or value.get("case", {}).get("hash") != expected["caseHash"]: raise ValueError("Windows case join mismatch")
    try: comparison = compare_case(case, mac + win, acceptance_config={}, holds=["fresh paired parity/golden/freeze held"])
    except ComparisonError as exc: comparison = {"status": "blocked", "reason": "canonical tuple/case admission rejected", "error": str(exc), "parity": "held", "goldens": 0, "promotion": "held"}
    out = {"schema": "paired-padding-f10-comparison-diagnostic-v8", "status": "paired-comparison-diagnostic-complete", "candidateOnly": True, "reader": {"macRuns": 20, "windowsReaderVerified": 20}, "comparison": comparison, "parity": {"status": "held", "goldens": 0, "promotion": "held"}, "effects": {"nativeWindowActions": 0, "compilerActions": 0, "remoteActions": 0, "lockActions": 0, "sourceMutations": 0}}
    if args.output.exists(): raise ValueError("output must be fresh")
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": out["status"], "macRuns": 20, "windowsReaderVerified": 20, "nativeParity": "held"})); return 0

if __name__ == "__main__": raise SystemExit(main())
