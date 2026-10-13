#!/usr/bin/env python3
"""Bounded source admission for fresh Padding packet; no native effects."""
from __future__ import annotations
import argparse, hashlib, json, os, stat, sys
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
MAX_REF = 8 * 1024 * 1024

def fail(msg: str) -> None:
    raise ValueError(msg)

def read_ref(root: Path, row: dict, *, json_value: bool = False):
    rel = row.get("path")
    if not isinstance(rel, str) or not rel or Path(rel).is_absolute() or ".." in Path(rel).parts:
        fail(f"unsafe reference path: {rel!r}")
    p = (root / rel)
    st = p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        fail(f"reference is not regular/non-reparse: {rel}")
    if st.st_size != int(row["bytes"]) or st.st_size > MAX_REF:
        fail(f"reference byte drift/limit: {rel}")
    h = hashlib.sha256()
    with p.open("rb") as f:
        while True:
            b = f.read(1024 * 1024)
            if not b: break
            h.update(b)
    got = h.hexdigest()
    if got != row["sha256"]:
        fail(f"reference hash drift: {rel}")
    if not json_value:
        return p
    if st.st_size > MAX_JSON:
        fail(f"JSON too large: {rel}")
    with p.open("rb") as f:
        return json.loads(f.read().decode("utf-8-sig"))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--packet", required=True, type=Path)
    args = ap.parse_args()
    root = args.root.resolve()
    packet_path = args.packet.resolve()
    if root not in packet_path.parents: fail("packet must be under root")
    st = packet_path.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_JSON: fail("invalid packet")
    packet = json.loads(packet_path.read_bytes().decode("utf-8-sig"))
    if packet.get("schema") != "factory-padding-fresh-source-packet-v1": fail("wrong packet schema")
    rows = packet.get("references")
    if not isinstance(rows, list) or len(rows) != len({r.get("name") for r in rows}): fail("reference names not unique")
    by_name = {r["name"]: r for r in rows}
    docs = {}
    for name in ("candidate-source-manifest.json", "seed-case.json", "fresh-case.json", "fresh-tuple.json", "fresh-witness.manifest.json", "mac-root-review.json", "mac-summary.json", "mac-compiler-receipt.json", "mac-host-build.json"):
        docs[name] = read_ref(root, by_name[name], json_value=True)
    read_ref(root, by_name["seed-witness.swift"])
    read_ref(root, by_name["fresh-witness.swift"])
    read_ref(root, by_name["mac-archive-manifest.json"])
    read_ref(root, by_name["mac-ax-run001.json"])
    fresh = packet["freshMac"]
    tup = docs["fresh-tuple.json"]["tuple"]
    case = docs["fresh-case.json"]
    if case["id"] != fresh["caseId"] or case["tuple"]["id"] != fresh["tupleId"]:
        fail("fresh case/tuple identity drift")
    if case["tuple"]["hostHashes"]["macos"] != "sha256:" + fresh["tupleMacHostSha256"] or case["tuple"]["hostHashes"]["windows"] != "sha256:" + fresh["tupleWindowsHostSha256"]:
        fail("fresh host hash drift")
    if case["tuple"].get("runtimeCommit") != fresh["runtimeCommit"]:
        fail("runtime commit drift")
    if case["tuple"].get("rendererHash") != "sha256:" + fresh["rendererSha256"]:
        fail("renderer hash drift")
    frozen_w = docs["fresh-witness.manifest.json"]
    if frozen_w.get("sourceHash") != "sha256:" + packet["source"]["witnessSha256"]:
        fail("frozen fresh witness top-level source hash drift")
    if not any(w.get("sourceHash") != "sha256:" + packet["source"]["witnessSha256"] for w in frozen_w.get("channels", {}).get("witnesses", [])):
        fail("stale frozen witness manifest was not detected")
    cm = docs["candidate-source-manifest.json"]
    ws = cm.get("witness", {}).get("sourceHash")
    if ws != "sha256:" + packet["source"]["witnessSha256"]:
        fail("candidate witness source hash mismatch")
    if cm.get("sourceHash") != "sha256:" + packet["source"]["witnessSha256"]:
        fail("candidate manifest source hash mismatch")
    if any(w.get("sourceHash") != "sha256:" + packet["source"]["witnessSha256"] for w in cm.get("channels", {}).get("witnesses", [])):
        fail("candidate witness source hash mismatch")
    if docs["mac-compiler-receipt.json"]["compiler"]["outputBinary"]["sha256"] != "sha256:" + fresh["tupleMacHostSha256"]:
        fail("compiler receipt/output mismatch")
    if docs["mac-host-build.json"]["binary"]["sha256"] != "sha256:" + fresh["tupleMacHostSha256"]:
        fail("host build/output mismatch")
    if docs["mac-host-build.json"]["source"]["sha256"] != "sha256:" + packet["source"]["witnessSha256"]:
        fail("host build/source mismatch")
    if docs["mac-summary.json"]["candidateOnly"] is not True or docs["mac-summary.json"]["acceptance"] != "not-promoted":
        fail("Mac evidence incorrectly promoted")
    if packet["historical"]["tupleMacHostSha256"] == fresh["tupleMacHostSha256"]:
        fail("historical donor unexpectedly equals fresh host")
    print(json.dumps({"status":"SOURCE_ADMISSION_PASS", "nativeActions":0, "caseId":fresh["caseId"], "tupleId":fresh["tupleId"], "candidateManifest":"candidate-source-manifest.json", "macObservation":"held-candidate-only"}, separators=(",", ":")))
    return 0

if __name__ == "__main__":
    try: raise SystemExit(main())
    except Exception as e:
        print(json.dumps({"status":"SOURCE_ADMISSION_HOLD", "reason":str(e), "nativeActions":0}, separators=(",", ":")))
        raise SystemExit(2)
