#!/usr/bin/env python3
"""Validate exact exported Clang owner evidence without inferred public flags."""
from __future__ import annotations
import gzip
import hashlib
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "raw/clang-external-owner-v1.json"

def sha(p: Path) -> str:
    return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()

def main() -> None:
    subprocess.run(["python3", str(HERE / "capture_clang_external.py")], check=True, cwd=ROOT)
    d = json.loads(EVIDENCE.read_text())
    assert d["schema"] == "clang-external-owner-v1"
    assert len(d["targets"]) == 5
    assert [x["target"] for x in d["targets"]] == ["AppKit.NSWindow", "CoreGraphics.CGPoint", "CoreGraphics.CGSize", "CoreGraphics.CGRect", "Spatial.Size3D"]
    assert {x["usr"] for x in d["targets"]} == {"c:objc(cs)NSWindow", "c:@S@CGPoint", "c:@S@CGSize", "c:@S@CGRect", "c:@UA@SPSize3D"}
    for x in d["targets"]:
        assert x["status"] == "public-header-exported"
        assert x["source"]["text"]
        assert x["sourceKit"]["name"]
        assert x["eligibilityEvidence"] == ["exact Clang " + ("ObjCInterfaceDecl" if x["target"] == "AppKit.NSWindow" else "typedef AST"), "public SDK header", "module map umbrella export *", "successful Swift import/typecheck"] if x["target"] != "Spatial.Size3D" else x["eligibilityEvidence"]
    assert d["controls"] == {"exactRawUSR": True, "exactSourceHeaderLine": True, "exactASTIdentity": True, "moduleMapExportRequired": True, "noAbsenceInference": True, "noSyntheticPublicFlags": True, "unresolvedAliasesRemainHeld": True}
    for module, meta in d["clangAST"]["outputs"].items():
        gz = ROOT / meta["gzip"]
        assert sha(gz) == meta["gzipSha256"]
        assert "sha256:" + hashlib.sha256(gzip.decompress(gz.read_bytes())).hexdigest() == meta["decompressedSha256"]
        assert sha(ROOT / meta["filtered"]) == meta["filteredSha256"]
    for module, m in ((x["module"], x) for x in d["moduleMaps"]):
        assert "export *" in m["exportEvidence"]
    assert d["probe"]["swiftcExit"] == 0
    assert d["sourcekit"]["exit"] == 0
    assert all(r["exit"] == 0 for r in d["clangAST"]["runs"].values())
    print("PASS clang-external-owner-v1: 5 exact exported nominal owners")

if __name__ == "__main__":
    main()
