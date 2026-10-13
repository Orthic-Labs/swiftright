#!/usr/bin/env python3
"""Focused immutable-input checks for ABI namespace correspondence evidence."""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "raw/abi-nominal-correspondence-v1.json"


def digest(p: Path) -> str:
    return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> None:
    subprocess.run(["python3", str(HERE / "capture_abi_nominal_correspondence.py")], check=True, cwd=ROOT)
    d = json.loads(EVIDENCE.read_text())
    assert d["schema"] == "abi-nominal-correspondence-v1"
    assert d["immutableLinkEvidence"]["sha256"] == "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
    assert len(d["correspondences"]) == 6
    names = [x["name"] for x in d["correspondences"]]
    assert names == ["AttributedTextFormatting", "AttributedTextFormatting.Transferable", "CustomHoverEffect", "HoverEffectContent", "TupleContent", "Text.LineStyle"]
    for x in d["correspondences"]:
        assert x["source"]["access"] == "public"
        assert x["importRef"]["module"] == "SwiftUI"
        assert x["importRef"]["usr"].startswith("s:7SwiftUI")
        assert x["interfaceExtensionAnchor"]["usr"].startswith("s:e:s:7SwiftUI")
        assert x["status"] in {"abi-namespace-mismatch-observed", "exact-imported-nested-ABI-ref"}
    assert d["correspondences"][0]["source"]["usr"] == "s:11SwiftUICore24AttributedTextFormattingO"
    assert d["correspondences"][2]["source"]["usr"] == "s:11SwiftUICore17CustomHoverEffectP"
    assert d["correspondences"][3]["source"]["usr"] == "s:11SwiftUICore18HoverEffectContentP"
    assert d["correspondences"][4]["source"]["usr"] == "s:11SwiftUICore12TupleContentV"
    assert d["correspondences"][5]["source"]["usr"] == "s:11SwiftUICore4TextV9LineStyleV"
    assert d["correspondences"][4]["rawDuplicateRefCount"] == 2
    assert d["controls"]["noBroadModuleAlias"] is True
    assert d["controls"]["noGraphAbsenceExclusion"] is True
    for module in ("SwiftUI", "SwiftUICore"):
        assert digest(ROOT / d["interfaces"][module]["path"]) == d["interfaces"][module]["sha256"]
    assert d["probe"]["typecheckExit"] == 0
    assert d["sourcekit"]["exit"] == 0
    assert d["demangle"]["exit"] == 0
    print("PASS abi-nominal-correspondence-v1: 5 nominal targets + nested Transferable")


if __name__ == "__main__":
    main()
