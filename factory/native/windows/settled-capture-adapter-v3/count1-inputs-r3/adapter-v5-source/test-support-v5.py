#!/usr/bin/env python3
"""Pure support controls for overlay pins & canonical issued IDs."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "factory").is_dir())
spec = importlib.util.spec_from_file_location("support_v5", HERE / "support-v5.py")
support = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(support)
COUNT_ROOTS = support.COUNT_ROOTS
PROFILE = support.PROFILE
validate_issued_ids = support.validate_issued_ids
validate_overlay = support.validate_overlay
METADATA = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/coordinator-single-r1/issued-metadata.json"


def main():
    refs = PROFILE["executeR8"]
    overlay = {"kind": "factory-root-execution-overlay-v1", "status": "executed-source-ref-only", "overlayRoot": COUNT_ROOTS[1], "files": [dict(x) for x in refs]}
    validate_overlay(overlay, lambda ref: (REPO / ref["path"]).read_bytes(), 1)
    for mutate, message in (
        (lambda x: x.update(overlayRoot=COUNT_ROOTS[20]), "wrong overlay root"),
        (lambda x: x["files"][0].update(sha256="sha256:" + "0" * 64), "wrong source hash"),
    ):
        bad = copy.deepcopy(overlay); mutate(bad)
        try:
            validate_overlay(bad, lambda ref: (REPO / ref["path"]).read_bytes(), 1)
            raise AssertionError(message + " accepted")
        except ValueError:
            pass
    metadata = json.loads(METADATA.read_text(encoding="utf-8-sig"))
    # r7 metadata is used only as a source-shape fixture; no output is changed.
    validate_issued_ids(metadata, 1, metadata["runRoot"])
    bad = copy.deepcopy(metadata); bad["captures"][0]["captureID"] = "capture/" + "0" * 31
    try:
        validate_issued_ids(bad, 1, metadata["runRoot"])
        raise AssertionError("wrong native capture ID accepted")
    except ValueError:
        pass
    bad = copy.deepcopy(metadata); bad["runRoot"] = "actual-single-r1-wrong"
    try:
        validate_issued_ids(bad, 1, metadata["runRoot"])
        raise AssertionError("wrong recorded root accepted")
    except ValueError:
        pass
    print({"status": "pass", "positive": ["r8-overlay", "r7-issued-id-shape"], "faults": ["overlay-root", "source-hash", "capture-id", "recorded-root"], "nativeWindowActions": 0})


if __name__ == "__main__":
    main()
