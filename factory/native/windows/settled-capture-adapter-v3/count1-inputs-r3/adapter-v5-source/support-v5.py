#!/usr/bin/env python3
"""Exact source/profile admission for r8 Count1 & repeat5 Count20."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
PROFILE = json.loads((HERE / "source-profile-v5.json").read_text())
COUNT_ROOTS = {
    1: "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r8",
    20: "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6",
}
SUCCESSOR_ROOTS = {
    1: {COUNT_ROOTS[1]},
    20: {
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r5",
        COUNT_ROOTS[20],
    },
}
# Frozen overlay whitelist remains admissible for replay/source review.
# Successor roots above are prospective r8/r5 only.
OVERLAY_ROOTS = {
    1: {
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r4": {
            "coordinator-r4.ps1": "sha256:e949ad380d9cfe6ecd1bd2520b2689ac0f865f0a0c4d7561c213ae40b3aa580c",
            "interactive-task-r4.ps1": "sha256:3f7b4ab78cc46995992746cf7f24a25177ac4294ce9a29b306a295335611647f",
            "dispatch-r4.ps1": "sha256:699513f3758c567d0052c2ce10d135d14a6517a6d62c0aaa5c2141d83da37135",
            "capture-repeat-r4.ps1": "sha256:1183c5071e77fa67ee91d31edf3917ff63dc28d3d8922e29f17eab9e62efcb8a",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r5": {
            "coordinator-r5.ps1": "sha256:3e32c96c858f1233836ecb6a9191050dde39387fabe70c8cc1d8222e6cb83761",
            "interactive-task-r5.ps1": "sha256:6c9b9720ec840f62e4922dc3590709cf31e619fa9de2a29fa3b58a6f67c82f44",
            "dispatch-r5.ps1": "sha256:a5b147e031e156c6f31392d7167e21a2dfb45c7bd9b18099cfa7d54b7ffdd0dc",
            "capture-repeat-r5.ps1": "sha256:6580498b8e12636af46a9f180dfb606bc2f4e81ccd320c6c18969fc0abde8255",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r6": {
            "coordinator-r6.ps1": "sha256:7dc5df6b6425474643b1540ecbb10483e705be3846ca2b12e66330abb44281f4",
            "interactive-task-r6.ps1": "sha256:9e4c825373e41def23a6d5c376e90097bde95612bfa887cba836f73e96f2f528",
            "dispatch-r6.ps1": "sha256:df39a14812a80a3131485808766c5b617f5b61d365d0a5302b9363b1319a1340",
            "capture-repeat-r6.ps1": "sha256:12adb458565e0c6398625cae54e992230e17fa3c2aafb05353109e2d55fc1e8a",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r7": {
            "coordinator-r7.ps1": "sha256:1d959f332c31d4843ed1217f5994c05f0e1df3a5801385c9fbbed9c08be39fd8",
            "interactive-task-r7.ps1": "sha256:25f18fab1c286c9f4f121e59ce0955b3c3a7d02b7bea5ce3d56b25dcdb4893b4",
            "dispatch-r7.ps1": "sha256:33acdf62c846895a4c0360068917b89d657ace5f4ba68d503a454ea77ed493d0",
            "capture-repeat-r7.ps1": "sha256:049c9d39d80a9c30017190cb57ab6e55093b3e65926e18a019e5b6aa3090b2e3",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
    },
    20: {
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r2": {
            "resume-issued-coordinator-repeat-r2.ps1": "sha256:d4359512dd4f6efe2f13dad301b12d14b5099130185fbfcf9b4572f0ecbef043",
            "interactive-task-repeat-r2.ps1": "sha256:e9d2d2055f8c5e89439046e843cd11e5820aab742da88eda1c6f90ec7305a929",
            "dispatch-repeat-r2.ps1": "sha256:3b61a3d60ef5509ce6852a38e8441cdec44b7e05b989b02c018634f43ee507d1",
            "capture-repeat-r2.ps1": "sha256:45f795f3a41551a2931c50fbfd9763405f0ea6bac249edc93f8f42a12499a5d7",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r3": {
            "resume-issued-coordinator-repeat-r3.ps1": "sha256:c39fe732f62fb8a4a7de4d78908bc0161d2f523f062dbfd80247d8bb33ef216a",
            "interactive-task-repeat-r3.ps1": "sha256:77a1db2b317df603e6df046ea453510ee24a4f23e75bf2650dae603fcccef3b0",
            "dispatch-repeat-r3.ps1": "sha256:76879ae70a50139631905176900df4e17300ad136d604d9efd4ebf5b6a5f00d3",
            "capture-repeat-r3.ps1": "sha256:c7173928076d01a4776f5ce2e04e7b7e99b6ad98b4155f1c7115880dac075260",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
        "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r4": {
            "resume-issued-coordinator-repeat-r4.ps1": "sha256:b2889bac231d337f15c88ad7bb800ba44a2b0330de8be66163fbd2f4b648153b",
            "interactive-task-repeat-r4.ps1": "sha256:02d33efee1cb14f59e6182c63dc5490e06cd380b3f0dd25165b2f76e2ebd79f0",
            "dispatch-repeat-r4.ps1": "sha256:c96c0c8acdf6fd2bc042fd704544c318cecd2dc622eb938474f5eac971fbb695",
            "capture-repeat-r4.ps1": "sha256:52da5743464fc22b2ce5a81bb5099d138ab40a13602798d46f3f2a52bb5a81c5",
            "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
        },
    },
}
for _count, _root in COUNT_ROOTS.items():
    OVERLAY_ROOTS[_count][_root] = {Path(x["path"]).name: x["sha256"] for x in PROFILE["executeR8" if _count == 1 else "repeatR6"]}
OVERLAY_ROOTS[20]["factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r5"] = {Path(x["path"]).name: x["sha256"] for x in PROFILE["repeatR5"]}


def digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def require(value, message):
    if not value:
        raise ValueError(message)


def validate_overlay(overlay: dict, read_bytes, expected_count: int) -> bool:
    require(expected_count in (1, 20), "unsupported source count")
    root = overlay.get("overlayRoot") if isinstance(overlay, dict) else None
    require(root in OVERLAY_ROOTS[expected_count], "overlay root not admitted for count")
    require(isinstance(overlay, dict) and overlay.get("kind") == "factory-root-execution-overlay-v1", "overlay kind")
    require(overlay.get("status") == "executed-source-ref-only", "overlay status")
    require(overlay.get("overlayRoot") == root, "recorded overlay root")
    profile_key = "executeR8" if expected_count == 1 and root.endswith("/execute-r8") else ("repeatR6" if expected_count == 20 and root.endswith("/repeat-r6") else ("repeatR5" if expected_count == 20 and root.endswith("/repeat-r5") else None))
    entries = [{"path": f"{root}/{name}", "sha256": value, "bytes": (next(x["bytes"] for x in PROFILE[profile_key] if Path(x["path"]).name == name) if profile_key else len(read_bytes({"path": f"{root}/{name}", "sha256": value, "bytes": 0})))} for name, value in OVERLAY_ROOTS[expected_count][root].items()]
    files = overlay.get("files")
    require(isinstance(files, list) and len(files) == 5, "exact five successor files")
    by_name = {}
    for ref in files:
        require(isinstance(ref, dict) and isinstance(ref.get("path"), str), "overlay source ref")
        path = PurePosixPath(ref["path"])
        require(not path.is_absolute() and ".." not in path.parts and str(path) == ref["path"], "safe overlay source path")
        require(ref["path"].startswith(root + "/"), "overlay source root membership")
        require(path.name not in by_name, "duplicate successor source name")
        by_name[path.name] = ref
    for expected in entries:
        name = PurePosixPath(expected["path"]).name
        require(name in by_name, "missing pinned successor source:" + name)
        ref = by_name[name]
        require(ref.get("sha256") == expected["sha256"], "source pin:" + name)
        raw = read_bytes(ref)
        require(type(raw) is bytes and digest(raw) == ref["sha256"], "source byte/hash:" + name)
        if isinstance(ref.get("bytes"), int):
            require(len(raw) == ref["bytes"], "source byte count:" + name)
    return True


def validate_node_epochs(metadata: dict) -> bool:
    """Validate optional producer node epoch sequence when present."""
    epochs = metadata.get("nodeEpochs")
    if epochs is None:
        return True
    require(isinstance(epochs, list) and epochs, "node epochs must be non-empty list")
    require(all(type(x) is int and x >= 0 for x in epochs), "node epochs must be non-negative integers")
    require(epochs == sorted(set(epochs)), "node epochs must be unique and monotonic")
    return True


def validate_issued_ids(metadata: dict, expected_count: int, expected_run_root: str) -> bool:
    require(metadata.get("expectedCount") == expected_count, "issued count")
    require(metadata.get("runRoot") == expected_run_root, "recorded run root")
    captures = metadata.get("captures")
    require(isinstance(captures, list) and len(captures) == expected_count, "issued capture membership")
    ids = set(); images = set(); runs = []
    for capture in captures:
        cid = capture.get("captureID"); iid = capture.get("imageID"); run = capture.get("run")
        require(isinstance(cid, str) and re.fullmatch(r"capture/[0-9a-f]{32}", cid), "canonical capture ID")
        require(isinstance(iid, str) and re.fullmatch(r"image/[0-9a-f]{32}", iid), "canonical image ID")
        require(cid not in ids and iid not in images, "duplicate canonical ID")
        ids.add(cid); images.add(iid); runs.append(run)
    require(sorted(runs) == list(range(1, expected_count + 1)), "issued run sequence")
    return True
