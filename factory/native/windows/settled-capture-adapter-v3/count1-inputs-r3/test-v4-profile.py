#!/usr/bin/env python3
"""Verify measured v4 producer profile closure & typed profile allow-list offline."""
from __future__ import annotations
import hashlib, importlib.util, json
from pathlib import Path

PACKET = Path(__file__).resolve().parent
REPO = PACKET.parents[4]
PROFILE = REPO / "factory/native/windows/settled-capture-adapter-v3/dependencies/producer-stage-v4.json"
TRANSFER = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/transfer-manifest.json"
V4 = "sha256:72016fe5689e9cb74ef851ab6be2665f74b1b5a73ec0711e406046748b287967"

def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    profile = json.loads(PROFILE.read_text())
    transfer = json.loads(TRANSFER.read_text(encoding="utf-8-sig"))
    assert digest(PROFILE) == V4
    assert profile["closure"]["sha256"] == digest(TRANSFER)
    assert len(profile["files"]) == 76
    assert profile["files"] == transfer["files"]
    for row in profile["files"]:
        path = REPO / row["path"]
        assert path.is_file(), row["path"]
        assert path.stat().st_size == row["bytes"], row["path"]
        assert digest(path) == row["sha256"], row["path"]
    source = PACKET / "adapter-v4.py"
    spec = importlib.util.spec_from_file_location("adapter_v4_profile_test", source)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    assert V4 in module.SUPPORTED_PROFILES
    assert module.SUPPORTED_PROFILES[V4]["capturePlanHash"] == digest(REPO / "factory/native/windows/padding-capture-lease-capture-v3/capture-plan.json")
    assert "sha256:" + "0" * 64 not in module.SUPPORTED_PROFILES
    print("PASS producer-stage-v4: 76 rows, closure hash, profile allow-list, unknown hash rejection")

if __name__ == "__main__":
    main()
