#!/usr/bin/env python3
"""Fail-closed checks for duplicate identity evidence."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_RESPONSE = "sha256:352c81a020cd442aea487f0d74998f29b27d550b6958fd35582e4e14b3c1ef34"


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def resolve(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def check_receipts(value):
    if isinstance(value, dict):
        if "path" in value and "sha256" in value:
            assert digest(resolve(value["path"])) == value["sha256"], value["path"]
        if "exitCode" in value:
            assert value["exitCode"] == 0, value
        for nested in value.values():
            check_receipts(nested)
    elif isinstance(value, list):
        for nested in value:
            check_receipts(nested)


def main() -> None:
    raw = json.loads((HERE / "raw-record-evidence.json").read_text(encoding="utf-8"))
    evidence = json.loads((HERE / "duplicate-evidence.json").read_text(encoding="utf-8"))
    link = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    assert digest(link) == EXPECTED_LINK
    assert raw["summary"] == {"heldCaseCount": 5, "rawDuplicateRows": 5, "promotionsMade": 0}
    assert evidence["summary"] == {"allDuplicateRowsExact": True, "heldCaseCount": 5, "promotionsMade": 0}
    assert all(evidence["controls"].values())
    assert len(raw["rows"]) == len(evidence["rows"]) == 5
    for row in raw["rows"]:
        assert row["raw"]["recordCount"] == 2
        assert row["raw"]["fullRecordByteEqual"] is True
        assert row["raw"]["fullRecordShaEqual"] is True
        assert row["raw"]["parsedEntityEqual"] is True
        assert row["raw"]["records"][0]["text"] == row["raw"]["records"][1]["text"]
        assert row["raw"]["records"][0]["sha256"] == row["raw"]["records"][1]["sha256"]
        assert row["source"]["activeBranch"]["active"] is True
        assert row["source"]["activeBranch"]["conditions"] == ["compiler(>=5.3) && $TildeSendable"]
        assert row["source"]["lineNameOccurrenceCount"] == 1
    assert raw["receipts"]["sourcekit"]["stdout"]["sha256"] == EXPECTED_RESPONSE
    assert raw["receipts"]["sourcekit"]["frozenResponse"]["sha256"] == EXPECTED_RESPONSE
    assert raw["receipts"]["demangle"]["exitCode"] == 0
    assert raw["receipts"]["tildeSendableBranch"]["compile"]["exitCode"] == 0
    assert raw["receipts"]["tildeSendableBranch"]["run"]["exitCode"] == 0
    assert (HERE / "branch-output.txt").read_text(encoding="utf-8") == "selected=active\n"
    assert all(all(row["faultControls"].values()) for row in evidence["rows"])
    check_receipts(raw["receipts"])
    check_receipts(evidence["inputs"])
    print("duplicate identity evidence assertions passed")


if __name__ == "__main__":
    main()
