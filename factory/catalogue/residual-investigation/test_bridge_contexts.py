#!/usr/bin/env python3
"""Assertions for structural F1 context bridge artifact."""
from __future__ import annotations

import json
import hashlib
import re
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "context-bridge-evidence.json"
sys.path.insert(0, str(HERE))
import bridge_contexts as bridge  # noqa: E402


def main() -> None:
    payload = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    summary = payload["summary"]
    assert payload["status"] == "review-only-structural-owner-bridge"
    assert payload["inputs"]["linkEvidenceSha256"] == (
        "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
    )
    assert payload["inputs"]["expectedImmutableLinkEvidenceSha256"] == payload["inputs"]["linkEvidenceSha256"]
    assert payload["inputs"]["bridgeSource"]["sha256"].startswith("sha256:")
    assert payload["inputs"]["investigatorSource"]["sha256"].startswith("sha256:")
    for receipt in (payload["inputs"]["bridgeSource"], payload["inputs"]["investigatorSource"]):
        path = HERE.parents[2] / receipt["path"]
        digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == receipt["sha256"]
    assert len(payload["rows"]) == 206
    assert len({tuple(row["key"]) for row in payload["rows"]}) == 206
    assert summary["rawEntityCardinalityOne"] == 206
    assert summary["structuralOwnerExact"] == 173
    assert summary["genuineStructuralMismatch"] == 33
    assert summary["moduleProvenanceMismatch"] == 33
    assert summary["unsupportedCompilerModuleAliasRows"] == 33
    assert summary["proposedBridgeEligible"] == 173
    assert len(payload["controlDetails"]) == 9
    assert all(item["baselineAccepted"] is True for item in payload["controlBases"])
    assert payload["lineage"]["immutableLinkEvidenceSha256"] == payload["inputs"]["linkEvidenceSha256"]
    assert summary["missingExpandedTree"] == 0
    assert summary["currentLinkPromotion"] == 0
    assert summary["rawContextEmpty"] == 33
    assert summary["rawContextImmediateSuffix"] == 173
    assert summary["genericReferenceRows"] == 2
    assert summary["repeatedDeclNameRows"] == 3
    assert all(payload["controls"].values())
    for row in payload["rows"]:
        expected = row["bridge"]["moduleProvenance"]["expectedNominalModule"]
        actual = row["compilerOwner"]["nominalModule"]
        assert row["bridge"]["proposedBridgeEligible"] is (expected == actual)
        assert row["bridge"]["kindMatch"] is True
        assert row["bridge"]["accessMatch"] is True
        assert row["bridge"]["strictContextMatch"] is False
        assert row["compilerOwner"]["directDeclarationPathCount"] == 1
        assert row["compilerOwner"]["functionLocalScope"] is False
    expanded = Path(payload["inputs"]["expandedOutput"]["path"])
    if not expanded.is_absolute():
        expanded = HERE.parents[2] / expanded
    raw = expanded.read_text(encoding="utf-8")
    sections = [part for part in re.split(r"(?=Demangling for \\$s)", raw) if part.strip()]
    try:
        bridge.parse_sections(raw + sections[0])
    except ValueError:
        pass
    else:
        raise AssertionError("duplicate demangle USR was accepted")
    broken = raw.replace("kind=", "unknown-record=", 1)
    try:
        bridge.parse_sections(broken)
    except ValueError:
        pass
    else:
        raise AssertionError("unknown demangle record was accepted")
    print("context bridge assertions passed")


if __name__ == "__main__":
    main()
