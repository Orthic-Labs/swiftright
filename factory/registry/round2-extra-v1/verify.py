#!/usr/bin/env python3
"""Strict offline verifier for held Round 2 source-bound candidates."""
from __future__ import annotations
import argparse, copy, hashlib, json, re
from pathlib import Path
from generate import BLOCKS, CATALOGUE, ACTIVE_MANIFEST, ACTIVE_REGISTRY, canonical, sha

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_CATALOGUE_SHA = "740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270"
EXPECTED_BLOCK_IDS = [x[0] for x in BLOCKS]
USR_RE = re.compile(r"^usr:s:.+")


def load(path: Path):
    raw = path.read_bytes()
    return json.loads(raw), raw


def check(manifest: dict, catalogue: dict, cat_raw: bytes) -> list[str]:
    errors=[]
    if manifest.get("kind") != "round2-extra-candidate-manifest" or manifest.get("version") != "0.1": errors.append("manifest kind/version")
    if manifest.get("activeRegistryMutation") is not False: errors.append("active registry mutation not false")
    if manifest.get("status") != "held-source-bound-candidates": errors.append("candidate status is not held")
    if manifest.get("catalogue", {}).get("sha256") != EXPECTED_CATALOGUE_SHA: errors.append("catalogue pin mismatch")
    if sha(cat_raw) != EXPECTED_CATALOGUE_SHA: errors.append("catalogue bytes mismatch")
    symbols=catalogue.get("symbols")
    if not isinstance(symbols,list): return errors+["catalogue symbols missing"]
    by_usr={}; by_path={}
    for i in symbols:
        if not isinstance(i,dict): return errors+["catalogue object missing"]
        if i.get("usr") in by_usr: return errors+["catalogue duplicate USR"]
        by_usr[i.get("usr")]=i; by_path.setdefault(i.get("path"),[]).append(i)
    blocks=manifest.get("blocks")
    if not isinstance(blocks,list) or [b.get("id") for b in blocks] != EXPECTED_BLOCK_IDS: errors.append("block ids/order")
    seen=set()
    for b in blocks if isinstance(blocks,list) else []:
        bid=b.get("id")
        if bid in seen: errors.append(f"duplicate block {bid}")
        seen.add(bid)
        spec=next((x for x in BLOCKS if x[0]==bid),None)
        if spec is None: errors.append(f"unknown block {bid}"); continue
        if b.get("candidateStatus")!="held-candidate" or b.get("coverageStatus")!="identity-only" or b.get("nativeCoverage")!="unsupported" or b.get("registryPromotion") is not False: errors.append(f"{bid}: promotion/status gate")
        if b.get("semanticDependencies") != []: errors.append(f"{bid}: unbound semantic deps")
        entries=b.get("symbols")
        if not isinstance(entries,list) or len(entries)!=len(spec[2]): errors.append(f"{bid}: symbol cardinality") ; continue
        by_expected_path={x["path"]:x for x in entries}
        if len(by_expected_path)!=len(entries): errors.append(f"{bid}: duplicate paths")
        for path in spec[2]:
            matches=by_path.get(path,[])
            e=by_expected_path.get(path)
            if len(matches)!=1 or not isinstance(e,dict): errors.append(f"{bid}: path {path}"); continue
            item=matches[0]
            if e.get("selector") != "usr:"+item["usr"]: errors.append(f"{bid}: selector binding {path}")
            if not isinstance(e.get("selector"),str) or not USR_RE.fullmatch(e["selector"]): errors.append(f"{bid}: malformed selector")
            if e.get("catalogueStatus") != item.get("status") or e.get("symbolEvidenceSha256") != sha(canonical(item)): errors.append(f"{bid}: evidence binding {path}")
            if item.get("status")=="hidden": errors.append(f"{bid}: hidden item")
    return errors


def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("manifest",type=Path,default=Path(__file__).with_name("candidate-manifest.json"),nargs="?"); args=ap.parse_args()
    m,mraw=load(args.manifest); c, craw=load(CATALOGUE)
    errors=check(m,c,craw)
    if errors:
        print(json.dumps({"ok":False,"errors":errors},sort_keys=True)); return 1
    print(json.dumps({"ok":True,"manifestSha256":sha(mraw),"catalogueSha256":sha(craw),"blocks":len(m["blocks"]),"symbols":sum(len(x["symbols"]) for x in m["blocks"])},sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
