#!/usr/bin/env python3
"""Replay raw external-owner capture without making eligibility claims."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EVIDENCE = HERE / "external-owner-evidence.json"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
CENSUS = ROOT / "factory/catalogue/public-ancestor-spike/raw/ancestor-census-v1.json"


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    payload = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    assert payload["status"] == "raw-facts-no-eligibility-decisions"
    assert payload["counts"] == {
        "crossModuleExtensionHeaders": 541,
        "extensionHeadersWithV12MemberRows": 508,
        "graphAbsentTargetPaths": 12,
        "graphPresentTargetPaths": 27,
        "nominalTargetRecordCount": 56,
        "uniqueTargetPaths": 39,
    }
    assert payload["pins"]["immutable836"]["sha256"] == digest(LINK)
    assert payload["pins"]["census"]["sha256"] == digest(CENSUS)
    assert len(payload["extensions"]) == 541
    assert sum(bool(item["memberRows"]) for item in payload["extensions"]) == 508
    assert len(set(tuple(item["targetPath"]) for item in payload["extensions"])) == 39

    swiftui_path = Path(payload["pins"]["swiftuiInterface"]["path"])
    core_path = Path(payload["pins"]["swiftuiCoreInterface"]["path"])
    swiftui_lines = swiftui_path.read_text(encoding="utf-8").splitlines()
    core_lines = core_path.read_text(encoding="utf-8").splitlines()
    for extension in payload["extensions"]:
        assert extension["sourceModule"] == "SwiftUI"
        assert extension["targetModule"] == "SwiftUICore"
        assert extension["sourceText"] == swiftui_lines[extension["sourceLine"] - 1]
        assert extension["extensionEntityStatus"] in {"present", "missing-in-pinned-index"}
        for entity in extension["rawExtensionEntities"]:
            assert entity["module"] == "SwiftUI"
            assert entity["line"] == extension["sourceLine"]
            assert entity["kind"].startswith("source.lang.swift.decl.extension.")
        for member in extension["memberRows"]:
            assert member["sourceText"] == swiftui_lines[member["line"] - 1]
            for entity in member["rawEntities"]:
                assert entity["module"] == "SwiftUI"
                assert entity["line"] == member["line"]
        for owner in extension["nominalOwnerRecords"]:
            assert owner["module"] == "SwiftUICore"
            assert owner["sourceText"] == core_lines[owner["line"] - 1]
            assert owner["path"] == extension["targetPath"]
            assert owner["ownerEntityStatus"] in {"present", "missing-in-pinned-index"}
            for entity in owner["rawEntities"]:
                assert entity["module"] == "SwiftUICore"
                assert entity["line"] == owner["line"]
            if owner["rawEntities"]:
                assert any(entity["name"] == owner["name"] for entity in owner["rawEntities"])
    print("external owner raw capture replay: PASS")


if __name__ == "__main__":
    main()
