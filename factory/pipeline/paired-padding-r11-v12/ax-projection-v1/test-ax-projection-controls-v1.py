#!/usr/bin/env python3
"""Source controls for owned-witness AX projection; no native action."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ax_projection_v1 import Hold, normalize  # noqa: E402

MAX_JSON = 8 * 1024 * 1024


def fixture() -> dict:
    mac_node = {
        "identity": "swiftui.padding-frame.witness/ax/0", "role": "AXStaticText", "label": "Box", "value": "Box",
        "actions": [], "bounds": {"x": 185, "y": 552, "width": 23, "height": 16}, "source": "external",
    }
    win_root = {
        "identity": "root", "role": "Window", "label": "Alchemist FactoryProbe", "actions": [],
        "bounds": {"x": 1312, "y": 736, "width": 832, "height": 688}, "source": "external",
        "children": ["Root/#0/Modified/Modified/Text"],
    }
    win_node = {
        "identity": "Root/#0/Modified/Modified/Text", "role": "Text", "label": "Box",
        "value": {"isEnabled": True, "isOffscreen": False}, "actions": [],
        "bounds": {"x": 1483, "y": 828, "width": 65, "height": 60}, "source": "external",
        "children": [],
    }
    mac = {"kind": "capture", "version": "0.1", "id": "mac/1", "platform": "macos", "ax": [mac_node], "meta": {"run": 1, "conditions": {}}}
    win = {"kind": "capture", "version": "0.1", "id": "win/1", "platform": "windows", "ax": [win_root, win_node], "meta": {"run": 1, "conditions": {}}}
    return {
        "schema": "factory-native-count20-r17-ax-projection-input-v1", "version": 1,
        "witness": {
            "mac": {"identity": mac_node["identity"], "role": mac_node["role"], "label": mac_node["label"], "value": mac_node["value"], "actions": mac_node["actions"]},
            "windows": {
                "identity": win_node["identity"], "role": win_node["role"], "label": win_node["label"], "value": win_node["value"], "actions": win_node["actions"], "observedScale": 2.5,
                "root": {"identity": win_root["identity"], "role": win_root["role"], "label": win_root["label"], "actions": win_root["actions"]},
                "dropIdentities": [win_root["identity"]],
            },
        },
        "proofController": {"oldCompileSha256": "sha256:" + "1" * 64, "freshCompileSha256": "sha256:" + "2" * 64, "noOpFreshCompile": False, "status": "observed"},
        "observations": [
            *[{"run": index, "capture": {**copy.deepcopy(mac), "id": f"mac/{index}", "meta": {"run": index, "conditions": {}}}} for index in range(1, 21)],
            *[{"run": index, "capture": {**copy.deepcopy(win), "id": f"win/{index}", "meta": {"run": index, "conditions": {}}}} for index in range(1, 21)],
        ],
    }


def reject(label: str, bundle: dict) -> dict:
    try:
        normalize(bundle)
    except Hold as exc:
        return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit("control unexpectedly accepted: " + label)


def preserve(label: str, bundle: dict, baseline: dict, field: str) -> dict:
    try:
        result = normalize(bundle)
        expected = baseline["captures"][20]["ax"][0].get(field)
        actual = result["captures"][20]["ax"][0].get(field)
        if actual == expected:
            raise Hold(f"{label} was normalized away")
        return {"name": label, "status": "observed-mismatch-preserved", "field": field}
    except Hold as exc:
        raise SystemExit(f"control unexpectedly rejected observable {label}: {exc}") from exc


def validate_positive(result: dict) -> None:
    if result.get("typedStatus") != "observational-only" or result.get("qualified") is not False:
        raise Hold("positive projection became qualification")
    if result.get("proofController", {}).get("status") != "external-admission-only":
        raise Hold("proof controller incorrectly gates normalization")
    for capture in result.get("captures", []):
        projection = capture.get("meta", {}).get("conditions", {}).get("axProjection", {})
        if projection.get("rawRetained") is not True:
            raise Hold("raw AX before/after refs missing")
        if capture.get("platform") == "windows" and projection.get("before", {}).get("sha256") == projection.get("after", {}).get("sha256"):
            raise Hold("Windows DPI/root projection before/after refs missing")


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    base = fixture()
    try:
        positive = normalize(base)
        validate_positive(positive)
        faults: list[dict] = []
        for name, field, mutate in (
            ("changed-label", "label", lambda b: b["observations"][20]["capture"]["ax"][1].__setitem__("label", "Changed")),
            ("changed-value", "value", lambda b: b["observations"][20]["capture"]["ax"][1]["value"].__setitem__("isEnabled", False)),
            ("changed-action", "actions", lambda b: b["observations"][20]["capture"]["ax"][1]["actions"].append("invoke")),
            ("changed-role", "role", lambda b: b["observations"][20]["capture"]["ax"][1].__setitem__("role", "Button")),
            ("changed-size", "bounds", lambda b: b["observations"][20]["capture"]["ax"][1]["bounds"].__setitem__("width", 66)),
        ):
            mutant = copy.deepcopy(base); mutate(mutant); faults.append(preserve(name, mutant, positive, field))
        wrong_dpi = copy.deepcopy(base); wrong_dpi["witness"]["windows"]["observedScale"] = 2.0; faults.append(reject("wrong-dpi", wrong_dpi))
        unknown_chrome = copy.deepcopy(base); unknown_chrome["observations"][20]["capture"]["ax"].append(copy.deepcopy(unknown_chrome["observations"][20]["capture"]["ax"][1])); unknown_chrome["observations"][20]["capture"]["ax"][-1]["identity"] = "unlisted"; faults.append(reject("unlisted-chrome", unknown_chrome))
        same_hash = copy.deepcopy(base); same_hash["proofController"]["noOpFreshCompile"] = True; same_hash["proofController"]["freshCompileSha256"] = same_hash["proofController"]["oldCompileSha256"]
        same_hash_result = normalize(same_hash)
        if same_hash_result.get("proofController", {}).get("status") != "external-admission-only":
            raise Hold("fresh compile receipt incorrectly blocked semantic projection")
        output = {"schema": "factory-native-count20-r17-ax-projection-controls-v1", "status": "baseline-admitted-observable-differences-preserved", "faultControls": faults, "freshProofPolicyControl": "external-admission-only", "nativeActions": 0, "lockActions": 0}
        args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (Hold, OSError) as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status": output["status"], "faults": len(faults), "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
