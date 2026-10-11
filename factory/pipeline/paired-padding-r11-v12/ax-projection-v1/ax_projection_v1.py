#!/usr/bin/env python3
"""Source-bound AX projection for paired observational captures.

This successor keeps frozen capture/reader code untouched.  It removes only
explicitly listed Windows chrome, maps the selected Windows Text witness to
AXStaticText, and converts its measured pixels to DIP.  Every raw AX input is
bound by before/after hashes in output conditions.
"""
from __future__ import annotations

from copy import deepcopy
from decimal import Decimal, InvalidOperation
import hashlib
import json
import math
from typing import Any


class Hold(ValueError):
    pass


def stable_hash(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def number(value: Any, label: str) -> Decimal:
    if isinstance(value, bool):
        raise Hold(f"{label} must be numeric")
    if isinstance(value, int):
        return Decimal(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise Hold(f"{label} must be finite")
        return Decimal(str(value))
    if isinstance(value, dict) and set(value) == {"$decimal"} and isinstance(value["$decimal"], str):
        try:
            return Decimal(value["$decimal"])
        except InvalidOperation as exc:
            raise Hold(f"{label} decimal invalid") from exc
    raise Hold(f"{label} must be numeric")


def measured(value: Decimal) -> int | dict[str, str]:
    if value == value.to_integral_value():
        return int(value)
    return {"$decimal": format(value.normalize(), "f")}


def rect(raw: Any, label: str) -> dict[str, int | dict[str, str]]:
    if not isinstance(raw, dict) or set(raw) != {"x", "y", "width", "height"}:
        raise Hold(f"{label} bounds malformed")
    return {key: measured(number(raw[key], f"{label}.{key}")) for key in ("x", "y", "width", "height")}


def scaled_rect(raw: Any, scale: Decimal, label: str) -> dict[str, int | dict[str, str]]:
    if scale <= 0:
        raise Hold("Windows observed scale must be positive")
    values = rect(raw, label)
    return {key: measured(number(values[key], f"{label}.{key}") / scale) for key in ("x", "y", "width", "height")}


def require_node(node: Any, label: str) -> dict[str, Any]:
    if not isinstance(node, dict):
        raise Hold(f"{label} node malformed")
    for key in ("identity", "role", "actions", "bounds", "source"):
        if key not in node:
            raise Hold(f"{label} node missing {key}")
    if not isinstance(node["identity"], str) or not isinstance(node["role"], str):
        raise Hold(f"{label} node identity/role malformed")
    if not isinstance(node["actions"], list) or any(not isinstance(action, str) for action in node["actions"]):
        raise Hold(f"{label} node actions malformed")
    if node["source"] != "external":
        raise Hold(f"{label} node source is not external")
    rect(node.get("bounds"), label)
    return node


def exact(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise Hold(f"{label} changed")


def _witness_config(bundle: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], Decimal]:
    witness = bundle.get("witness")
    if not isinstance(witness, dict):
        raise Hold("explicit witness configuration missing")
    mac = witness.get("mac")
    win = witness.get("windows")
    if not isinstance(mac, dict) or not isinstance(win, dict):
        raise Hold("explicit mac/windows witness configuration missing")
    scale = number(win.get("observedScale"), "Windows observed scale")
    if scale != Decimal("2.5"):
        raise Hold("Windows observed scale must be measured 2.5")
    for config, label in ((mac, "Mac witness"), (win, "Windows witness")):
        for key in ("identity", "role"):
            if key not in config:
                raise Hold(f"{label} {key} missing")
    root = win.get("root")
    drop = win.get("dropIdentities")
    if not isinstance(root, dict) or not isinstance(drop, list) or any(not isinstance(item, str) for item in drop):
        raise Hold("Windows explicit root/drop witness configuration missing")
    for key in ("identity", "role"):
        if key not in root:
            raise Hold(f"Windows root {key} missing")
    if root["identity"] not in drop:
        raise Hold("Windows root must be explicitly listed as dropped chrome")
    if root["role"] != "Window":
        raise Hold("Windows dropped root role must be Window")
    return mac, win, scale


def _raw_windows_witness(ax: Any, win: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not isinstance(ax, list) or not ax:
        raise Hold("Windows AX tree missing")
    nodes = [require_node(node, f"Windows AX node {index}") for index, node in enumerate(ax)]
    root_cfg = win["root"]
    roots = [node for node in nodes if node["identity"] == root_cfg["identity"]]
    if len(roots) != 1:
        raise Hold("explicit Windows root missing or duplicated")
    root = roots[0]
    for key in ("identity", "role"):
        exact(root.get(key), root_cfg[key], f"Windows root {key}")
    drop = set(win["dropIdentities"])
    if {node["identity"] for node in nodes} - (drop | {win["identity"]}):
        raise Hold("unlisted Windows chrome/node cannot be stripped")
    if set(node["identity"] for node in nodes if node["identity"] in drop) != drop:
        raise Hold("explicit Windows chrome identity missing")
    children = [node for node in nodes if node["identity"] == win["identity"]]
    if len(children) != 1:
        raise Hold("explicit Windows witness missing or duplicated")
    child = children[0]
    if not isinstance(root.get("children"), list) or root["children"] != [child["identity"]]:
        raise Hold("Windows root-child witness join missing")
    return child, nodes


def _canonical_node(raw: dict[str, Any], config: dict[str, Any], *, scale: Decimal | None) -> dict[str, Any]:
    exact(raw.get("identity"), config["identity"], "witness identity")
    projected = deepcopy(raw)
    projected["bounds"] = scaled_rect(raw.get("bounds"), scale, "Windows witness") if scale is not None else rect(raw.get("bounds"), "Mac witness")
    if scale is not None and raw.get("role") == config.get("role"):
        projected["role"] = "AXStaticText"
    return projected


def project_capture(capture: dict[str, Any], mac: dict[str, Any], win: dict[str, Any], scale: Decimal) -> dict[str, Any]:
    if not isinstance(capture, dict) or capture.get("kind") != "capture" or capture.get("version") != "0.1":
        raise Hold("capture artifact malformed")
    platform = capture.get("platform")
    raw_ax = capture.get("ax")
    before = stable_hash(raw_ax)
    if platform == "macos":
        if not isinstance(raw_ax, list) or len(raw_ax) != 1:
            raise Hold("Mac explicit witness must contain exactly one AX node")
        raw = require_node(raw_ax[0], "Mac witness")
        projected = [_canonical_node(raw, mac, scale=None)]
    elif platform == "windows":
        raw, _ = _raw_windows_witness(raw_ax, win)
        projected = [_canonical_node(raw, win, scale=scale)]
    else:
        raise Hold("AX projection supports macos/windows only")
    output = deepcopy(capture)
    output["ax"] = projected
    conditions = output.setdefault("meta", {}).setdefault("conditions", {})
    evidence = conditions.get("readerEvidence")
    evidence_hashes = {}
    if isinstance(evidence, dict):
        for key in ("uiaSha256", "rawUIAHash", "pixelsReceiptSha256", "rawReceiptHash", "printWindowSha256", "stdoutSha256"):
            if isinstance(evidence.get(key), str):
                evidence_hashes[key] = evidence[key]
    conditions["axProjection"] = {
        "kind": "owned-witness-dip-v1",
        "platform": platform,
        "observedScale": measured(scale) if platform == "windows" else 1,
        "rawReference": {"captureID": capture.get("id"), "channel": "ax", "source": "input.capture.ax", "readerEvidenceHashes": evidence_hashes},
        "before": {"sha256": before, "nodeCount": len(raw_ax) if isinstance(raw_ax, list) else 0},
        "after": {"sha256": stable_hash(projected), "nodeCount": len(projected)},
        "droppedIdentities": list(win["dropIdentities"]) if platform == "windows" else [],
        "originStatus": "observed" if "observedOrigin" in conditions else "missing-observed-origin",
        "rawRetained": True,
    }
    return output


def normalize(bundle: dict[str, Any]) -> dict[str, Any]:
    if bundle.get("schema") != "factory-native-count20-r17-ax-projection-input-v1" or bundle.get("version") != 1:
        raise Hold("AX projection input schema mismatch")
    mac, win, scale = _witness_config(bundle)
    observations = bundle.get("observations")
    if not isinstance(observations, list) or len(observations) != 40:
        raise Hold("AX observations require Count20 per platform")
    projected: list[dict[str, Any]] = []
    seen: set[tuple[str, int]] = set()
    for index, entry in enumerate(observations, 1):
        if not isinstance(entry, dict) or not isinstance(entry.get("capture"), dict):
            raise Hold(f"observation {index} malformed")
        capture = entry["capture"]
        platform = capture.get("platform")
        run = entry.get("run", capture.get("meta", {}).get("run"))
        if platform not in ("macos", "windows") or type(run) is not int or not 1 <= run <= 20:
            raise Hold(f"observation {index} platform/run missing")
        key = (platform, run)
        if key in seen:
            raise Hold(f"observation {index} duplicate platform/run")
        seen.add(key)
        projected.append(project_capture(capture, mac, win, scale))
    if seen != {(platform, run) for platform in ("macos", "windows") for run in range(1, 21)}:
        raise Hold("AX observations must contain every Mac/Windows run 1..20")
    result = {
        "kind": "factory-native-count20-r17-ax-projected-v1",
        "version": 1,
        "typedStatus": "observational-only",
        "qualified": False,
        "nativeActions": 0,
        "lockActions": 0,
        "projection": {"kind": "owned-witness-dip-v1", "scaleWindows": measured(scale), "frozenRawPreserved": True, "frozenNormalizerUnchanged": True},
        "captures": projected,
    }
    controller = bundle.get("proofController")
    if isinstance(controller, dict):
        result["proofController"] = {"status": "external-admission-only", "receipt": deepcopy(controller), "metadataHelperInsufficient": True}
    return result
